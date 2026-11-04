package main

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
	_ "modernc.org/sqlite"
)

var (
	ErrExists       = errors.New("that username is taken")
	ErrNoUser       = errors.New("no such user")
	ErrBadLogin     = errors.New("invalid credentials")
	ErrBadToken     = errors.New("invalid or expired session")
	usernamePattern = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]{2,31}$`)
)

const (
	minPassword = 8
	maxPassword = 72 // bcrypt ignores everything after 72 bytes, so longer ones would be misleading
)

// Record is one synced item. The newest UpdatedAt wins when two devices change the same
// (Type, Key); Deleted keeps a tombstone so a removal reaches every device.
type Record struct {
	Type      string          `json:"type"`
	Key       string          `json:"key"`
	Data      json.RawMessage `json:"data"`
	UpdatedAt int64           `json:"updated_at"` // unix milliseconds, set by the client
	Deleted   bool            `json:"deleted"`
}

// Store is the SQLite database: users, sessions and synced records.
type Store struct {
	db        *sql.DB
	dummyHash []byte // compared against when a user does not exist, so timing does not reveal it
	now       func() time.Time
}

const schemaV1 = `
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  pass_hash BLOB NOT NULL,
  created_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  last_used INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions (user_id);
CREATE TABLE IF NOT EXISTS records (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  key TEXT NOT NULL,
  data TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  server_seq INTEGER NOT NULL,
  PRIMARY KEY (user_id, type, key)
);
CREATE INDEX IF NOT EXISTS records_seq ON records (user_id, server_seq);
`

func OpenStore(path string) (*Store, error) {
	// WAL for concurrent readers, a busy timeout instead of "database is locked", and foreign
	// keys so deleting a user removes their sessions and records with them.
	dsn := path + "?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=foreign_keys(1)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1) // one writer at a time keeps SQLite simple and fast enough for this
	s := &Store{db: db, now: time.Now}
	if err := s.migrate(); err != nil {
		db.Close()
		return nil, fmt.Errorf("preparing the database: %w", err)
	}
	hash, err := bcrypt.GenerateFromPassword([]byte("not a real password"), bcrypt.DefaultCost)
	if err != nil {
		return nil, err
	}
	s.dummyHash = hash
	return s, nil
}

func (s *Store) Close() error { return s.db.Close() }

// migrate brings any older database up to the current layout.
func (s *Store) migrate() error {
	var version int
	if err := s.db.QueryRow(`PRAGMA user_version`).Scan(&version); err != nil {
		return err
	}
	if version >= 1 {
		return nil
	}
	// Databases from before sessions were hashed have a raw-token "tokens" table. Those sessions
	// cannot be converted (the raw tokens are what we no longer keep), so people sign in again.
	if _, err := s.db.Exec(`DROP TABLE IF EXISTS tokens`); err != nil {
		return err
	}
	if _, err := s.db.Exec(schemaV1); err != nil {
		return err
	}
	// Older users tables lack created_at.
	rows, err := s.db.Query(`PRAGMA table_info(users)`)
	if err != nil {
		return err
	}
	has := false
	for rows.Next() {
		var cid int
		var name, typ string
		var notnull, pk int
		var dflt sql.NullString
		if rows.Scan(&cid, &name, &typ, &notnull, &dflt, &pk) == nil && name == "created_at" {
			has = true
		}
	}
	rows.Close()
	if !has {
		if _, err := s.db.Exec(`ALTER TABLE users ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0`); err != nil {
			return err
		}
	}
	_, err = s.db.Exec(`PRAGMA user_version = 1`)
	return err
}

func normalizeUsername(name string) string { return strings.ToLower(strings.TrimSpace(name)) }

// ValidateUsername and ValidatePassword return a sentence for the person, or "" when fine.
func ValidateUsername(name string) string {
	if !usernamePattern.MatchString(name) {
		return "username must be 3 to 32 characters: letters, numbers, dot, dash or underscore"
	}
	return ""
}

func ValidatePassword(pw string) string {
	switch {
	case len(pw) < minPassword:
		return fmt.Sprintf("password must be at least %d characters", minPassword)
	case len(pw) > maxPassword:
		return fmt.Sprintf("password must be at most %d characters", maxPassword)
	}
	return ""
}

func (s *Store) CreateUser(name, password string) (int64, error) {
	name = normalizeUsername(name)
	if msg := ValidateUsername(name); msg != "" {
		return 0, errors.New(msg)
	}
	if msg := ValidatePassword(password); msg != "" {
		return 0, errors.New(msg)
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return 0, err
	}
	res, err := s.db.Exec(`INSERT INTO users (username, pass_hash, created_at) VALUES (?, ?, ?)`, name, hash, s.now().Unix())
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE") {
			return 0, ErrExists
		}
		return 0, err
	}
	return res.LastInsertId()
}

// Authenticate checks a password. A wrong password and an unknown user look the same.
func (s *Store) Authenticate(name, password string) (int64, error) {
	var id int64
	var hash []byte
	err := s.db.QueryRow(`SELECT id, pass_hash FROM users WHERE username = ?`, normalizeUsername(name)).Scan(&id, &hash)
	if err != nil {
		bcrypt.CompareHashAndPassword(s.dummyHash, []byte(password)) // spend the same time either way
		return 0, ErrBadLogin
	}
	if bcrypt.CompareHashAndPassword(hash, []byte(password)) != nil {
		return 0, ErrBadLogin
	}
	return id, nil
}

// Username is the name behind an id ("" if the user is gone).
func (s *Store) Username(id int64) string {
	var name string
	s.db.QueryRow(`SELECT username FROM users WHERE id = ?`, id).Scan(&name)
	return name
}

func (s *Store) UserID(name string) (int64, error) {
	var id int64
	err := s.db.QueryRow(`SELECT id FROM users WHERE username = ?`, normalizeUsername(name)).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, ErrNoUser
	}
	return id, err
}

func (s *Store) DeleteUser(name string) error {
	res, err := s.db.Exec(`DELETE FROM users WHERE username = ?`, normalizeUsername(name))
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNoUser
	}
	return nil
}

// SetPassword changes a password and signs the user out everywhere except [keepToken] (may be "").
func (s *Store) SetPassword(name, password, keepToken string) error {
	if msg := ValidatePassword(password); msg != "" {
		return errors.New(msg)
	}
	id, err := s.UserID(name)
	if err != nil {
		return err
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	if _, err := s.db.Exec(`UPDATE users SET pass_hash = ? WHERE id = ?`, hash, id); err != nil {
		return err
	}
	_, err = s.db.Exec(`DELETE FROM sessions WHERE user_id = ? AND token_hash != ?`, id, hashToken(keepToken))
	return err
}

type UserInfo struct {
	Name      string
	CreatedAt time.Time
	Records   int
	Sessions  int
	LastSeen  time.Time // zero if never signed in
}

func (s *Store) ListUsers() ([]UserInfo, error) {
	rows, err := s.db.Query(`
SELECT u.username, u.created_at,
  (SELECT COUNT(*) FROM records r WHERE r.user_id = u.id AND r.deleted = 0),
  (SELECT COUNT(*) FROM sessions t WHERE t.user_id = u.id),
  COALESCE((SELECT MAX(last_used) FROM sessions t WHERE t.user_id = u.id), 0)
FROM users u ORDER BY u.username`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []UserInfo
	for rows.Next() {
		var u UserInfo
		var created, seen int64
		if err := rows.Scan(&u.Name, &created, &u.Records, &u.Sessions, &seen); err != nil {
			return nil, err
		}
		if created > 0 {
			u.CreatedAt = time.Unix(created, 0)
		}
		if seen > 0 {
			u.LastSeen = time.Unix(seen, 0)
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// ---- sessions ----------------------------------------------------------------------

// Only a hash of each token is stored, so a leaked database does not hand out working sessions.
func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func (s *Store) IssueToken(userID int64, device string) (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	token := hex.EncodeToString(b)
	if len(device) > 64 {
		device = device[:64]
	}
	now := s.now().Unix()
	_, err := s.db.Exec(`INSERT INTO sessions (token_hash, user_id, device, created_at, last_used) VALUES (?, ?, ?, ?, ?)`,
		hashToken(token), userID, device, now, now)
	return token, err
}

// TokenUser finds who a token belongs to, and notes that it was used (at most once an hour,
// to avoid a write on every sync).
func (s *Store) TokenUser(token string) (int64, error) {
	var id, last int64
	h := hashToken(token)
	if err := s.db.QueryRow(`SELECT user_id, last_used FROM sessions WHERE token_hash = ?`, h).Scan(&id, &last); err != nil {
		return 0, ErrBadToken
	}
	if now := s.now().Unix(); now-last > 3600 {
		s.db.Exec(`UPDATE sessions SET last_used = ? WHERE token_hash = ?`, now, h)
	}
	return id, nil
}

func (s *Store) RevokeToken(token string) error {
	_, err := s.db.Exec(`DELETE FROM sessions WHERE token_hash = ?`, hashToken(token))
	return err
}

type Session struct {
	Device   string `json:"device"`
	LastUsed int64  `json:"last_used"`
}

func (s *Store) Sessions(userID int64) ([]Session, error) {
	rows, err := s.db.Query(`SELECT device, last_used FROM sessions WHERE user_id = ? ORDER BY last_used DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Session{}
	for rows.Next() {
		var x Session
		if err := rows.Scan(&x.Device, &x.LastUsed); err != nil {
			return nil, err
		}
		out = append(out, x)
	}
	return out, rows.Err()
}

// PruneSessions drops sessions nobody has used for a long time. Returns how many.
func (s *Store) PruneSessions(unusedFor time.Duration) (int64, error) {
	res, err := s.db.Exec(`DELETE FROM sessions WHERE last_used < ?`, s.now().Add(-unusedFor).Unix())
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

// ---- sync ---------------------------------------------------------------------------

// Sync applies a device's changes (newest UpdatedAt wins) and returns everything that changed on
// the server since the sequence number the device last saw.
func (s *Store) Sync(userID, since int64, changes []Record) (int64, []Record, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return 0, nil, err
	}
	defer tx.Rollback()

	var seq int64
	tx.QueryRow(`SELECT COALESCE(MAX(server_seq), 0) FROM records WHERE user_id = ?`, userID).Scan(&seq)
	// A device ahead of the server means the server was restored from an older backup: start it over.
	if since > seq {
		since = 0
	}

	for _, c := range changes {
		if c.Type == "" || c.Key == "" || len(c.Type) > 32 || len(c.Key) > 2048 {
			continue
		}
		seq++
		data := string(c.Data)
		if data == "" {
			data = "null"
		}
		// The WHERE clause drops stale writes: only a newer updated_at replaces a row.
		if _, err := tx.Exec(`
INSERT INTO records (user_id, type, key, data, updated_at, deleted, server_seq)
VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT (user_id, type, key) DO UPDATE SET
  data = excluded.data, updated_at = excluded.updated_at,
  deleted = excluded.deleted, server_seq = excluded.server_seq
WHERE excluded.updated_at > records.updated_at`,
			userID, c.Type, c.Key, data, c.UpdatedAt, c.Deleted, seq); err != nil {
			return 0, nil, err
		}
	}

	rows, err := tx.Query(`SELECT type, key, data, updated_at, deleted, server_seq
FROM records WHERE user_id = ? AND server_seq > ? ORDER BY server_seq`, userID, since)
	if err != nil {
		return 0, nil, err
	}
	out := []Record{}
	high := since
	for rows.Next() {
		var rec Record
		var data string
		var rseq int64
		if rows.Scan(&rec.Type, &rec.Key, &data, &rec.UpdatedAt, &rec.Deleted, &rseq) != nil {
			continue
		}
		rec.Data = json.RawMessage(data)
		out = append(out, rec)
		if rseq > high {
			high = rseq
		}
	}
	rows.Close()
	if err := tx.Commit(); err != nil {
		return 0, nil, err
	}
	return high, out, nil
}

func (s *Store) CountRecords(userID int64) (int, error) {
	var n int
	err := s.db.QueryRow(`SELECT COUNT(*) FROM records WHERE user_id = ? AND deleted = 0`, userID).Scan(&n)
	return n, err
}

// Backup writes a consistent copy of the whole database to [path] (which must not exist).
func (s *Store) Backup(path string) error {
	_, err := s.db.Exec(`VACUUM INTO ?`, path)
	return err
}
