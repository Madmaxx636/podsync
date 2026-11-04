// podsync-server: a small self-hosted sync server.
//
// Everything the clients sync (subscriptions, episode progress, the queue,
// settings) is stored as generic records keyed by (type, key). The newest
// updated_at wins, so any client can push and pull at any time.
package main

import (
	"crypto/rand"
	"crypto/subtle"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"flag"
	"log"
	"net/http"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
	_ "modernc.org/sqlite"
)

type Record struct {
	Type      string          `json:"type"`
	Key       string          `json:"key"`
	Data      json.RawMessage `json:"data"`
	UpdatedAt int64           `json:"updated_at"` // unix milliseconds, set by the client
	Deleted   bool            `json:"deleted"`
}

type server struct {
	db        *sql.DB
	allowSign bool
}

const schema = `
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  pass_hash BLOB NOT NULL
);
CREATE TABLE IF NOT EXISTS tokens (
  token TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL,
  device TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS records (
  user_id INTEGER NOT NULL,
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

func main() {
	addr := flag.String("addr", ":8080", "listen address")
	dbPath := flag.String("db", "podsync.db", "sqlite database path")
	signup := flag.Bool("signup", true, "allow new registrations")
	flag.Parse()

	db, err := sql.Open("sqlite", *dbPath+"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)")
	if err != nil {
		log.Fatal(err)
	}
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(schema); err != nil {
		log.Fatal(err)
	}

	s := &server{db: db, allowSign: *signup}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/register", s.register)
	mux.HandleFunc("POST /api/login", s.login)
	mux.HandleFunc("POST /api/sync", s.auth(s.sync))
	mux.HandleFunc("GET /api/health", func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte("ok"))
	})
	log.Printf("listening on %s", *addr)
	log.Fatal(http.ListenAndServe(*addr, mux))
}

type creds struct {
	Username string `json:"username"`
	Password string `json:"password"`
	Device   string `json:"device"`
}

func (s *server) register(w http.ResponseWriter, r *http.Request) {
	if !s.allowSign {
		http.Error(w, "registration disabled", http.StatusForbidden)
		return
	}
	var c creds
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<16)).Decode(&c) != nil ||
		len(c.Username) < 2 || len(c.Password) < 8 {
		http.Error(w, "username (2+) and password (8+) required", http.StatusBadRequest)
		return
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(c.Password), bcrypt.DefaultCost)
	if err != nil {
		http.Error(w, "server error", 500)
		return
	}
	res, err := s.db.Exec(`INSERT INTO users (username, pass_hash) VALUES (?, ?)`,
		strings.ToLower(c.Username), hash)
	if err != nil {
		http.Error(w, "username taken", http.StatusConflict)
		return
	}
	id, _ := res.LastInsertId()
	s.issueToken(w, id, c.Device)
}

func (s *server) login(w http.ResponseWriter, r *http.Request) {
	var c creds
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<16)).Decode(&c) != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	var id int64
	var hash []byte
	err := s.db.QueryRow(`SELECT id, pass_hash FROM users WHERE username = ?`,
		strings.ToLower(c.Username)).Scan(&id, &hash)
	if err != nil {
		bcrypt.CompareHashAndPassword([]byte("$2a$10$invalidinvalidinvalidinvalidinvalidinvalidinvalidinvalidi"), []byte(c.Password))
		http.Error(w, "invalid credentials", http.StatusUnauthorized)
		return
	}
	if bcrypt.CompareHashAndPassword(hash, []byte(c.Password)) != nil {
		http.Error(w, "invalid credentials", http.StatusUnauthorized)
		return
	}
	s.issueToken(w, id, c.Device)
}

func (s *server) issueToken(w http.ResponseWriter, userID int64, device string) {
	b := make([]byte, 32)
	rand.Read(b)
	tok := hex.EncodeToString(b)
	if _, err := s.db.Exec(`INSERT INTO tokens (token, user_id, device, created_at) VALUES (?, ?, ?, ?)`,
		tok, userID, device, time.Now().Unix()); err != nil {
		http.Error(w, "server error", 500)
		return
	}
	json.NewEncoder(w).Encode(map[string]string{"token": tok})
}

func (s *server) auth(next func(http.ResponseWriter, *http.Request, int64)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		tok := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		var id int64
		var stored string
		err := s.db.QueryRow(`SELECT user_id, token FROM tokens WHERE token = ?`, tok).Scan(&id, &stored)
		if err != nil || subtle.ConstantTimeCompare([]byte(tok), []byte(stored)) != 1 {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next(w, r, id)
	}
}

type syncReq struct {
	Since   int64    `json:"since"` // last server_seq the client has seen
	Changes []Record `json:"changes"`
}

type syncResp struct {
	Seq     int64    `json:"seq"` // new high-water mark to send as `since` next time
	Changes []Record `json:"changes"`
}

// sync applies the client's changes (last write wins on updated_at), then
// returns everything that changed on the server since the client's `since`.
func (s *server) sync(w http.ResponseWriter, r *http.Request, uid int64) {
	var req syncReq
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<20)).Decode(&req) != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	tx, err := s.db.Begin()
	if err != nil {
		http.Error(w, "server error", 500)
		return
	}
	defer tx.Rollback()

	var seq int64
	tx.QueryRow(`SELECT COALESCE(MAX(server_seq), 0) FROM records WHERE user_id = ?`, uid).Scan(&seq)

	for _, c := range req.Changes {
		if c.Type == "" || c.Key == "" {
			continue
		}
		seq++
		data := string(c.Data)
		if data == "" {
			data = "null"
		}
		// The WHERE clause drops stale writes: only a newer updated_at replaces a row.
		_, err := tx.Exec(`
INSERT INTO records (user_id, type, key, data, updated_at, deleted, server_seq)
VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT (user_id, type, key) DO UPDATE SET
  data = excluded.data, updated_at = excluded.updated_at,
  deleted = excluded.deleted, server_seq = excluded.server_seq
WHERE excluded.updated_at > records.updated_at`,
			uid, c.Type, c.Key, data, c.UpdatedAt, c.Deleted, seq)
		if err != nil {
			http.Error(w, "server error", 500)
			return
		}
	}

	rows, err := tx.Query(`SELECT type, key, data, updated_at, deleted, server_seq
FROM records WHERE user_id = ? AND server_seq > ? ORDER BY server_seq`, uid, req.Since)
	if err != nil {
		http.Error(w, "server error", 500)
		return
	}
	resp := syncResp{Seq: req.Since, Changes: []Record{}}
	for rows.Next() {
		var rec Record
		var data string
		var rseq int64
		if rows.Scan(&rec.Type, &rec.Key, &data, &rec.UpdatedAt, &rec.Deleted, &rseq) != nil {
			continue
		}
		rec.Data = json.RawMessage(data)
		resp.Changes = append(resp.Changes, rec)
		if rseq > resp.Seq {
			resp.Seq = rseq
		}
	}
	rows.Close()
	if err := tx.Commit(); err != nil {
		http.Error(w, "server error", 500)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
