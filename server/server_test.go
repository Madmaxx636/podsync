package main

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type fixture struct {
	t     *testing.T
	store *Store
	srv   *Server
	ts    *httptest.Server
	clock *fakeClock
}

type fakeClock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *fakeClock) Advance(d time.Duration) {
	c.mu.Lock()
	c.t = c.t.Add(d)
	c.mu.Unlock()
}

func newFixture(t *testing.T, signup bool) *fixture {
	t.Helper()
	store, err := OpenStore(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	clock := &fakeClock{t: time.Unix(1_800_000_000, 0)}
	store.now = clock.Now
	srv := NewServer(store, signup, false, "test")
	srv.throttle = newThrottle(clock.Now)
	srv.logger = log.New(io.Discard, "", 0)
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(func() { ts.Close(); store.Close() })
	return &fixture{t: t, store: store, srv: srv, ts: ts, clock: clock}
}

// call sends JSON and returns the status and the decoded object (nil for empty bodies).
func (f *fixture) call(method, path, token string, body any) (int, map[string]any) {
	f.t.Helper()
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, f.ts.URL+path, rd)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		f.t.Fatal(err)
	}
	defer res.Body.Close()
	var out map[string]any
	raw, _ := io.ReadAll(res.Body)
	json.Unmarshal(raw, &out)
	return res.StatusCode, out
}

func (f *fixture) register(name, pw string) string {
	f.t.Helper()
	code, body := f.call("POST", "/api/register", "", map[string]string{"username": name, "password": pw, "device": "test"})
	if code != 200 {
		f.t.Fatalf("register %s: %d %v", name, code, body)
	}
	return body["token"].(string)
}

func (f *fixture) login(name, pw string) (int, string) {
	code, body := f.call("POST", "/api/login", "", map[string]string{"username": name, "password": pw})
	tok, _ := body["token"].(string)
	return code, tok
}

func rec(typ, key string, at int64, data string) Record {
	return Record{Type: typ, Key: key, UpdatedAt: at, Data: json.RawMessage(data)}
}

func (f *fixture) sync(token string, since int64, changes ...Record) (int64, []Record) {
	f.t.Helper()
	code, body := f.call("POST", "/api/sync", token, map[string]any{"since": since, "changes": changes})
	if code != 200 {
		f.t.Fatalf("sync: %d %v", code, body)
	}
	raw, _ := json.Marshal(body["changes"])
	var out []Record
	json.Unmarshal(raw, &out)
	return int64(body["seq"].(float64)), out
}

func TestSignUpSignInAndSync(t *testing.T) {
	f := newFixture(t, true)
	tokA := f.register("Lane", "correct horse") // names are not case sensitive
	code, tokB := f.login("lane", "correct horse")
	if code != 200 || tokB == "" || tokB == tokA {
		t.Fatalf("second device sign-in: %d", code)
	}

	seq, _ := f.sync(tokA, 0, rec("sub", "https://x/feed", 100, `{"title":"X"}`), rec("progress", "x|1", 200, `{"pos":5000}`))
	if seq != 2 {
		t.Fatalf("seq = %d", seq)
	}
	// The other device pulls both.
	_, got := f.sync(tokB, 0)
	if len(got) != 2 {
		t.Fatalf("device B saw %d records", len(got))
	}
	// A stale write loses, a newer one wins, and a tombstone propagates.
	f.sync(tokA, seq, rec("progress", "x|1", 50, `{"pos":1}`))
	_, got = f.sync(tokB, 0)
	for _, r := range got {
		if r.Key == "x|1" && !strings.Contains(string(r.Data), "5000") {
			t.Fatalf("stale write replaced newer data: %s", r.Data)
		}
	}
	seq2, _ := f.sync(tokA, seq, Record{Type: "sub", Key: "https://x/feed", UpdatedAt: 300, Deleted: true, Data: json.RawMessage(`{}`)})
	_, got = f.sync(tokB, seq)
	if len(got) != 1 || !got[0].Deleted {
		t.Fatalf("deletion did not reach device B: %+v (seq %d)", got, seq2)
	}
}

func TestPeopleAreIsolated(t *testing.T) {
	f := newFixture(t, true)
	alice := f.register("alice", "alice-password")
	bob := f.register("bob", "bob-password!")
	f.sync(alice, 0, rec("queue", "main", 10, `{"items":["secret"]}`))
	_, got := f.sync(bob, 0)
	if len(got) != 0 {
		t.Fatalf("bob can see alice's data: %+v", got)
	}
	// Same keys for both users do not clash.
	f.sync(bob, 0, rec("queue", "main", 5, `{"items":["bob's"]}`))
	_, a := f.sync(alice, 0)
	_, b := f.sync(bob, 0)
	if !strings.Contains(string(a[0].Data), "secret") || !strings.Contains(string(b[0].Data), "bob's") {
		t.Fatalf("each person should keep their own: %s / %s", a[0].Data, b[0].Data)
	}
}

func TestSinceBeyondServerStartsOver(t *testing.T) {
	// A device that remembers a position the server no longer has (restored from an older backup)
	// is given everything again instead of silence.
	f := newFixture(t, true)
	tok := f.register("lane", "correct horse")
	f.sync(tok, 0, rec("sub", "a", 1, `{}`), rec("sub", "b", 2, `{}`))
	seq, got := f.sync(tok, 999)
	if len(got) != 2 || seq != 2 {
		t.Fatalf("seq=%d records=%d", seq, len(got))
	}
}

func TestRegistrationRules(t *testing.T) {
	f := newFixture(t, true)
	f.register("lane", "correct horse")

	cases := []struct {
		name, pw string
		want     int
	}{
		{"LANE", "another password", http.StatusConflict}, // same name, different case
		{"ab", "long enough pw", http.StatusBadRequest},   // too short
		{"has space", "long enough pw", http.StatusBadRequest},
		{"-leading", "long enough pw", http.StatusBadRequest},
		{"newperson", "short", http.StatusBadRequest},
		{"newperson", strings.Repeat("x", 73), http.StatusBadRequest},
		{"new.person-1_x", "long enough pw", http.StatusOK},
	}
	for _, c := range cases {
		code, body := f.call("POST", "/api/register", "", map[string]string{"username": c.name, "password": c.pw})
		if code != c.want {
			t.Errorf("register %q: got %d (%v), want %d", c.name, code, body, c.want)
		}
		if c.want == http.StatusBadRequest && body["error"] == "" {
			t.Errorf("register %q: no explanation", c.name)
		}
	}
}

func TestRegistrationCanBeTurnedOff(t *testing.T) {
	f := newFixture(t, false)
	code, body := f.call("POST", "/api/register", "", map[string]string{"username": "lane", "password": "correct horse"})
	if code != http.StatusForbidden || !strings.Contains(body["error"].(string), "turned off") {
		t.Fatalf("got %d %v", code, body)
	}
	// An owner adds people from the command line, and they can sign in.
	if _, err := f.store.CreateUser("lane", "correct horse"); err != nil {
		t.Fatal(err)
	}
	if code, _ := f.login("lane", "correct horse"); code != 200 {
		t.Fatalf("added user cannot sign in: %d", code)
	}
}

func TestWrongPasswordAndUnknownUserLookAlike(t *testing.T) {
	f := newFixture(t, true)
	f.register("lane", "correct horse")
	c1, b1 := f.call("POST", "/api/login", "", map[string]string{"username": "lane", "password": "wrong password"})
	c2, b2 := f.call("POST", "/api/login", "", map[string]string{"username": "nobody", "password": "wrong password"})
	if c1 != 401 || c2 != 401 || b1["error"] != b2["error"] {
		t.Fatalf("%d %v vs %d %v", c1, b1, c2, b2)
	}
}

func TestTooManyWrongPasswordsLocksThenFrees(t *testing.T) {
	f := newFixture(t, true)
	f.register("lane", "correct horse")
	f.register("other", "other password")
	for i := 0; i < userFailLimit; i++ {
		if code, _ := f.login("lane", "nope nope nope"); code != 401 {
			t.Fatalf("attempt %d: %d", i, code)
		}
	}
	// Locked: even the right password waits.
	req, _ := http.NewRequest("POST", f.ts.URL+"/api/login", strings.NewReader(`{"username":"lane","password":"correct horse"}`))
	res, _ := http.DefaultClient.Do(req)
	if res.StatusCode != 429 || res.Header.Get("Retry-After") == "" {
		t.Fatalf("expected a lock with Retry-After, got %d", res.StatusCode)
	}
	// Someone else on the same server is unaffected.
	if code, _ := f.login("other", "other password"); code != 200 {
		t.Fatalf("other user caught in the lock: %d", code)
	}
	f.clock.Advance(lockFor + time.Second)
	if code, _ := f.login("lane", "correct horse"); code != 200 {
		t.Fatalf("still locked after the wait: %d", code)
	}
}

func TestSuccessClearsTheCount(t *testing.T) {
	f := newFixture(t, true)
	f.register("lane", "correct horse")
	for round := 0; round < 3; round++ { // 3 x 4 misses would lock if successes did not reset
		for i := 0; i < userFailLimit-1; i++ {
			f.login("lane", "nope nope nope")
		}
		if code, _ := f.login("lane", "correct horse"); code != 200 {
			t.Fatalf("round %d: %d", round, code)
		}
	}
}

func TestLogoutEndsOnlyThatSession(t *testing.T) {
	f := newFixture(t, true)
	phone := f.register("lane", "correct horse")
	_, laptop := f.login("lane", "correct horse")
	if code, _ := f.call("POST", "/api/logout", phone, nil); code != 204 {
		t.Fatalf("logout: %d", code)
	}
	if code, _ := f.call("GET", "/api/me", phone, nil); code != 401 {
		t.Fatalf("the signed-out token still works: %d", code)
	}
	if code, _ := f.call("GET", "/api/me", laptop, nil); code != 200 {
		t.Fatalf("the other device was signed out too: %d", code)
	}
}

func TestTokensAreStoredHashed(t *testing.T) {
	f := newFixture(t, true)
	tok := f.register("lane", "correct horse")
	var count int
	f.store.db.QueryRow(`SELECT COUNT(*) FROM sessions WHERE token_hash = ?`, tok).Scan(&count)
	if count != 0 {
		t.Fatal("the raw token is in the database")
	}
	f.store.db.QueryRow(`SELECT COUNT(*) FROM sessions WHERE token_hash = ?`, hashToken(tok)).Scan(&count)
	if count != 1 {
		t.Fatal("the hashed token is not in the database")
	}
}

func TestMeShowsAccountAndDevices(t *testing.T) {
	f := newFixture(t, true)
	tok := f.register("lane", "correct horse")
	f.sync(tok, 0, rec("sub", "a", 1, `{}`), rec("sub", "b", 2, `{}`))
	code, me := f.call("GET", "/api/me", tok, nil)
	if code != 200 || me["username"] != "lane" || me["records"].(float64) != 2 {
		t.Fatalf("%d %v", code, me)
	}
	if len(me["sessions"].([]any)) != 1 {
		t.Fatalf("sessions: %v", me["sessions"])
	}
}

func TestChangePassword(t *testing.T) {
	f := newFixture(t, true)
	phone := f.register("lane", "correct horse")
	_, laptop := f.login("lane", "correct horse")

	if code, _ := f.call("POST", "/api/password", phone, map[string]string{"old": "wrong one", "new": "a new password"}); code != 401 {
		t.Fatalf("wrong current password: %d", code)
	}
	if code, _ := f.call("POST", "/api/password", phone, map[string]string{"old": "correct horse", "new": "short"}); code != 400 {
		t.Fatalf("weak new password: %d", code)
	}
	if code, _ := f.call("POST", "/api/password", phone, map[string]string{"old": "correct horse", "new": "a new password"}); code != 204 {
		t.Fatalf("change: %d", code)
	}
	if code, _ := f.call("GET", "/api/me", phone, nil); code != 200 {
		t.Fatalf("the device that changed it should stay signed in: %d", code)
	}
	if code, _ := f.call("GET", "/api/me", laptop, nil); code != 401 {
		t.Fatalf("other devices should be signed out: %d", code)
	}
	if code, _ := f.login("lane", "correct horse"); code != 401 {
		t.Fatal("old password still works")
	}
	if code, _ := f.login("lane", "a new password"); code != 200 {
		t.Fatal("new password does not work")
	}
}

func TestSyncNeedsASession(t *testing.T) {
	f := newFixture(t, true)
	for _, tok := range []string{"", "nope", strings.Repeat("a", 64)} {
		if code, _ := f.call("POST", "/api/sync", tok, map[string]any{"since": 0}); code != 401 {
			t.Errorf("token %q: %d", tok, code)
		}
	}
}

func TestRequestLimits(t *testing.T) {
	f := newFixture(t, true)
	tok := f.register("lane", "correct horse")
	big := `{"username":"` + strings.Repeat("a", 1<<17) + `"}`
	res, _ := http.Post(f.ts.URL+"/api/login", "application/json", strings.NewReader(big))
	if res.StatusCode != http.StatusRequestEntityTooLarge {
		t.Errorf("oversized login body: %d", res.StatusCode)
	}
	if code, _ := f.call("POST", "/api/sync", tok, nil); code != 400 {
		t.Errorf("empty sync body: %d", code)
	}
	res, _ = http.Post(f.ts.URL+"/api/login", "application/json", strings.NewReader("not json"))
	if res.StatusCode != 400 {
		t.Errorf("bad JSON: %d", res.StatusCode)
	}
}

func TestOddRecordsAreSkippedNotFatal(t *testing.T) {
	f := newFixture(t, true)
	tok := f.register("lane", "correct horse")
	seq, got := f.sync(tok, 0, rec("", "k", 1, `{}`), rec("t", "", 1, `{}`), rec(strings.Repeat("t", 40), "k", 1, `{}`), rec("ok", "k", 1, `{}`))
	if len(got) != 1 || got[0].Type != "ok" {
		t.Fatalf("seq=%d got=%+v", seq, got)
	}
}

func TestDeletingAUserRemovesEverything(t *testing.T) {
	f := newFixture(t, true)
	tok := f.register("lane", "correct horse")
	f.register("keep", "keep password")
	f.sync(tok, 0, rec("sub", "a", 1, `{}`))
	if err := f.store.DeleteUser("LANE"); err != nil {
		t.Fatal(err)
	}
	if code, _ := f.call("GET", "/api/me", tok, nil); code != 401 {
		t.Fatalf("a deleted user's session still works: %d", code)
	}
	var n int
	f.store.db.QueryRow(`SELECT COUNT(*) FROM records`).Scan(&n)
	if n != 0 {
		t.Fatalf("%d records left behind", n)
	}
	if err := f.store.DeleteUser("lane"); err != ErrNoUser {
		t.Fatalf("deleting twice: %v", err)
	}
	users, _ := f.store.ListUsers()
	if len(users) != 1 || users[0].Name != "keep" {
		t.Fatalf("users: %+v", users)
	}
}

func TestOldSessionsArePruned(t *testing.T) {
	f := newFixture(t, true)
	old := f.register("lane", "correct horse")
	f.clock.Advance(200 * 24 * time.Hour)
	_, fresh := f.login("lane", "correct horse")
	n, err := f.store.PruneSessions(180 * 24 * time.Hour)
	if err != nil || n != 1 {
		t.Fatalf("pruned %d, %v", n, err)
	}
	if code, _ := f.call("GET", "/api/me", old, nil); code != 401 {
		t.Fatal("the stale session survived")
	}
	if code, _ := f.call("GET", "/api/me", fresh, nil); code != 200 {
		t.Fatal("the recent session was removed")
	}
}

func TestHealth(t *testing.T) {
	f := newFixture(t, false)
	code, body := f.call("GET", "/api/health", "", nil)
	if code != 200 || body["status"] != "ok" || body["version"] != "test" || body["signup"] != false {
		t.Fatalf("%d %v", code, body)
	}
}

func TestProxyHeaderIsOnlyTrustedWhenAsked(t *testing.T) {
	f := newFixture(t, true)
	r := httptest.NewRequest("GET", "/", nil)
	r.RemoteAddr = "10.0.0.5:1234"
	r.Header.Set("X-Forwarded-For", "203.0.113.9, 10.0.0.1")
	if ip := f.srv.clientIP(r); ip != "10.0.0.5" {
		t.Fatalf("untrusted: %s", ip)
	}
	f.srv.trustProxy = true
	if ip := f.srv.clientIP(r); ip != "203.0.113.9" {
		t.Fatalf("trusted: %s", ip)
	}
}

func TestBackupIsAWorkingDatabase(t *testing.T) {
	f := newFixture(t, true)
	tok := f.register("lane", "correct horse")
	f.sync(tok, 0, rec("sub", "a", 1, `{"title":"A"}`))
	file := filepath.Join(t.TempDir(), "copy.db")
	if err := f.store.Backup(file); err != nil {
		t.Fatal(err)
	}
	copyStore, err := OpenStore(file)
	if err != nil {
		t.Fatal(err)
	}
	defer copyStore.Close()
	id, err := copyStore.Authenticate("lane", "correct horse")
	if err != nil {
		t.Fatalf("the copy lacks the user: %v", err)
	}
	_, got, _ := copyStore.Sync(id, 0, nil)
	if len(got) != 1 {
		t.Fatalf("the copy lacks the data: %+v", got)
	}
}

func TestOldDatabasesAreUpgraded(t *testing.T) {
	// The first version stored raw tokens in "tokens" and had no created_at on users.
	path := filepath.Join(t.TempDir(), "old.db")
	old, err := OpenStore(path)
	if err != nil {
		t.Fatal(err)
	}
	old.db.Exec(`PRAGMA user_version = 0`)
	old.db.Exec(`DROP TABLE sessions`)
	old.db.Exec(`DROP TABLE users`)
	old.db.Exec(`CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL, pass_hash BLOB NOT NULL)`)
	old.db.Exec(`CREATE TABLE tokens (token TEXT PRIMARY KEY, user_id INTEGER NOT NULL, device TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL)`)
	old.Close()

	s, err := OpenStore(path)
	if err != nil {
		t.Fatalf("upgrade failed: %v", err)
	}
	defer s.Close()
	if _, err := s.CreateUser("lane", "correct horse"); err != nil {
		t.Fatalf("users table not upgraded: %v", err)
	}
	var v int
	s.db.QueryRow(`PRAGMA user_version`).Scan(&v)
	if v != 1 {
		t.Fatalf("user_version = %d", v)
	}
}
