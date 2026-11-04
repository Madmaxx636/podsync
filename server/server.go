package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Server is the HTTP API.
type Server struct {
	store      *Store
	signup     bool // may new people register themselves?
	trustProxy bool // read the client address from X-Forwarded-For (only behind a proxy you control)
	version    string
	throttle   *throttle
	logger     *log.Logger
}

func NewServer(store *Store, signup, trustProxy bool, version string) *Server {
	return &Server{
		store:      store,
		signup:     signup,
		trustProxy: trustProxy,
		version:    version,
		throttle:   newThrottle(time.Now),
		logger:     log.Default(),
	}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health", s.health)
	mux.HandleFunc("POST /api/register", s.register)
	mux.HandleFunc("POST /api/login", s.login)
	mux.HandleFunc("POST /api/logout", s.auth(s.logout))
	mux.HandleFunc("GET /api/me", s.auth(s.me))
	mux.HandleFunc("POST /api/password", s.auth(s.changePassword))
	mux.HandleFunc("POST /api/sync", s.auth(s.sync))
	return s.recoverer(s.accessLog(mux))
}

// ---- helpers ----------------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func fail(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

// decode reads a small JSON body. Too-large bodies answer 413.
func decode(w http.ResponseWriter, r *http.Request, limit int64, into any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	if err := json.NewDecoder(r.Body).Decode(into); err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			fail(w, http.StatusRequestEntityTooLarge, "request is too large")
		} else {
			fail(w, http.StatusBadRequest, "request is not valid JSON")
		}
		return false
	}
	return true
}

func (s *Server) clientIP(r *http.Request) string {
	if s.trustProxy {
		if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
			return strings.TrimSpace(strings.Split(fwd, ",")[0])
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

// accessLog writes one line per request: no query strings and no bodies, so no secrets.
func (s *Server) accessLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: 200}
		next.ServeHTTP(sw, r)
		if r.URL.Path == "/api/health" {
			return // the container health check would fill the log
		}
		s.logger.Printf("%s %s %s %d %s", s.clientIP(r), r.Method, r.URL.Path, sw.status, time.Since(start).Round(time.Millisecond))
	})
}

func (s *Server) recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				s.logger.Printf("panic serving %s %s: %v", r.Method, r.URL.Path, v)
				fail(w, http.StatusInternalServerError, "server error")
			}
		}()
		next.ServeHTTP(w, r)
	})
}

type ctxKey int

const tokenKey ctxKey = 1

func bearer(r *http.Request) string {
	return strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
}

// auth wraps a handler that needs a signed-in user.
func (s *Server) auth(next func(http.ResponseWriter, *http.Request, int64)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		tok := bearer(r)
		id, err := s.store.TokenUser(tok)
		if tok == "" || err != nil {
			fail(w, http.StatusUnauthorized, "not signed in")
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), tokenKey, tok)), id)
	}
}

// ---- handlers ---------------------------------------------------------------------

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	if _, err := s.store.CountRecords(0); err != nil {
		fail(w, http.StatusServiceUnavailable, "database not reachable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok", "version": s.version, "signup": s.signup})
}

type creds struct {
	Username string `json:"username"`
	Password string `json:"password"`
	Device   string `json:"device"`
}

func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	if !s.signup {
		fail(w, http.StatusForbidden, "registration is turned off on this server; ask its owner to add you")
		return
	}
	var c creds
	if !decode(w, r, 1<<16, &c) {
		return
	}
	id, err := s.store.CreateUser(c.Username, c.Password)
	switch {
	case errors.Is(err, ErrExists):
		fail(w, http.StatusConflict, err.Error())
		return
	case err != nil:
		// Validation errors are sentences meant for the person; anything else is a server fault.
		if ValidateUsername(normalizeUsername(c.Username)) != "" || ValidatePassword(c.Password) != "" {
			fail(w, http.StatusBadRequest, err.Error())
		} else {
			s.logger.Printf("create user: %v", err)
			fail(w, http.StatusInternalServerError, "server error")
		}
		return
	}
	s.issue(w, id, c.Device)
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var c creds
	if !decode(w, r, 1<<16, &c) {
		return
	}
	name, ip := normalizeUsername(c.Username), s.clientIP(r)
	if ok, wait := s.throttle.allow(name, ip); !ok {
		w.Header().Set("Retry-After", strconv.Itoa(int(wait.Seconds())+1))
		fail(w, http.StatusTooManyRequests, "too many failed sign-ins; wait a few minutes and try again")
		return
	}
	id, err := s.store.Authenticate(name, c.Password)
	if err != nil {
		s.throttle.fail(name, ip)
		fail(w, http.StatusUnauthorized, ErrBadLogin.Error())
		return
	}
	s.throttle.succeed(name, ip)
	s.issue(w, id, c.Device)
}

func (s *Server) issue(w http.ResponseWriter, userID int64, device string) {
	tok, err := s.store.IssueToken(userID, device)
	if err != nil {
		s.logger.Printf("issue token: %v", err)
		fail(w, http.StatusInternalServerError, "server error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"token": tok})
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request, _ int64) {
	s.store.RevokeToken(r.Context().Value(tokenKey).(string))
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) me(w http.ResponseWriter, r *http.Request, uid int64) {
	name := s.store.Username(uid)
	records, _ := s.store.CountRecords(uid)
	sessions, _ := s.store.Sessions(uid)
	writeJSON(w, http.StatusOK, map[string]any{"username": name, "records": records, "sessions": sessions})
}

func (s *Server) changePassword(w http.ResponseWriter, r *http.Request, uid int64) {
	var req struct {
		Old string `json:"old"`
		New string `json:"new"`
	}
	if !decode(w, r, 1<<16, &req) {
		return
	}
	name := s.store.Username(uid)
	ip := s.clientIP(r)
	if ok, wait := s.throttle.allow(name, ip); !ok {
		w.Header().Set("Retry-After", strconv.Itoa(int(wait.Seconds())+1))
		fail(w, http.StatusTooManyRequests, "too many failed attempts; wait a few minutes")
		return
	}
	if _, err := s.store.Authenticate(name, req.Old); err != nil {
		s.throttle.fail(name, ip)
		fail(w, http.StatusUnauthorized, "current password is wrong")
		return
	}
	s.throttle.succeed(name, ip)
	if msg := ValidatePassword(req.New); msg != "" {
		fail(w, http.StatusBadRequest, msg)
		return
	}
	// Other devices are signed out; this one stays signed in.
	if err := s.store.SetPassword(name, req.New, r.Context().Value(tokenKey).(string)); err != nil {
		s.logger.Printf("set password: %v", err)
		fail(w, http.StatusInternalServerError, "server error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type syncReq struct {
	Since   int64    `json:"since"` // last server_seq the client has seen
	Changes []Record `json:"changes"`
}

type syncResp struct {
	Seq     int64    `json:"seq"` // new high-water mark to send as `since` next time
	Changes []Record `json:"changes"`
}

func (s *Server) sync(w http.ResponseWriter, r *http.Request, uid int64) {
	var req syncReq
	if !decode(w, r, 16<<20, &req) {
		return
	}
	seq, changes, err := s.store.Sync(uid, req.Since, req.Changes)
	if err != nil {
		s.logger.Printf("sync: %v", err)
		fail(w, http.StatusInternalServerError, "server error")
		return
	}
	writeJSON(w, http.StatusOK, syncResp{Seq: seq, Changes: changes})
}

// ---- login throttling ---------------------------------------------------------------

const (
	userFailLimit = 5  // wrong passwords for one username
	ipFailLimit   = 20 // wrong passwords from one address, across usernames
	failWindow    = 10 * time.Minute
	lockFor       = 5 * time.Minute
)

type failure struct {
	count int
	first time.Time
	until time.Time // locked until
}

// throttle slows down password guessing: five misses on a username, or twenty from an address,
// lock that name or address for five minutes. A correct sign-in clears the username's count.
type throttle struct {
	mu   sync.Mutex
	now  func() time.Time
	seen map[string]*failure
}

func newThrottle(now func() time.Time) *throttle {
	return &throttle{now: now, seen: map[string]*failure{}}
}

func (t *throttle) allow(user, ip string) (bool, time.Duration) {
	t.mu.Lock()
	defer t.mu.Unlock()
	now := t.now()
	for _, k := range []string{"u:" + user, "ip:" + ip} {
		if f := t.seen[k]; f != nil && now.Before(f.until) {
			return false, f.until.Sub(now)
		}
	}
	return true, 0
}

func (t *throttle) fail(user, ip string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	now := t.now()
	for k, limit := range map[string]int{"u:" + user: userFailLimit, "ip:" + ip: ipFailLimit} {
		f := t.seen[k]
		if f == nil || now.Sub(f.first) > failWindow {
			f = &failure{first: now}
			t.seen[k] = f
		}
		f.count++
		if f.count >= limit {
			f.until = now.Add(lockFor)
		}
	}
	// Keep the map from growing without bound.
	if len(t.seen) > 10000 {
		for k, f := range t.seen {
			if now.Sub(f.first) > failWindow && now.After(f.until) {
				delete(t.seen, k)
			}
		}
	}
}

func (t *throttle) succeed(user, ip string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	delete(t.seen, "u:"+user)
}
