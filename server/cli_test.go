package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type cliResult struct {
	code     int
	out, err string
}

func runCLI(t *testing.T, stdin string, env map[string]string, args ...string) cliResult {
	t.Helper()
	var out, errOut bytes.Buffer
	code := run(args, strings.NewReader(stdin), &out, &errOut, func(k string) string { return env[k] })
	return cliResult{code, out.String(), errOut.String()}
}

func TestUserCommands(t *testing.T) {
	db := filepath.Join(t.TempDir(), "cli.db")
	env := map[string]string{"PODSYNC_DB": db}

	r := runCLI(t, "", env, "user", "list")
	if r.code != 0 || !strings.Contains(r.out, "no users yet") {
		t.Fatalf("empty list: %+v", r)
	}

	// Password from the environment, from a pipe.
	r = runCLI(t, "", map[string]string{"PODSYNC_DB": db, "PODSYNC_PASSWORD": "from the env"}, "user", "add", "Alice")
	if r.code != 0 || !strings.Contains(r.out, "added alice") {
		t.Fatalf("add: %+v", r)
	}
	r = runCLI(t, "piped password\n", env, "user", "add", "bob")
	if r.code != 0 {
		t.Fatalf("add from pipe: %+v", r)
	}

	r = runCLI(t, "long enough pw\n", env, "user", "add", "ALICE")
	if r.code == 0 || !strings.Contains(r.err, "taken") {
		t.Fatalf("duplicate: %+v", r)
	}
	r = runCLI(t, "short\n", env, "user", "add", "carol")
	if r.code == 0 || !strings.Contains(r.err, "at least") {
		t.Fatalf("weak password: %+v", r)
	}
	r = runCLI(t, "long enough pw\n", env, "user", "add", "x")
	if r.code == 0 || !strings.Contains(r.err, "username must be") {
		t.Fatalf("bad name: %+v", r)
	}

	r = runCLI(t, "", env, "user", "list")
	if !strings.Contains(r.out, "alice") || !strings.Contains(r.out, "bob") || !strings.Contains(r.out, "USER") {
		t.Fatalf("list: %+v", r)
	}

	// The passwords really work.
	s, _ := OpenStore(db)
	if _, err := s.Authenticate("alice", "from the env"); err != nil {
		t.Fatal("alice cannot sign in")
	}
	if _, err := s.Authenticate("bob", "piped password"); err != nil {
		t.Fatal("bob cannot sign in")
	}
	id, _ := s.UserID("bob")
	tok, _ := s.IssueToken(id, "phone")
	s.Close()

	// Changing a password signs the person out.
	r = runCLI(t, "brand new password\n", env, "user", "passwd", "bob")
	if r.code != 0 || !strings.Contains(r.out, "sign in again") {
		t.Fatalf("passwd: %+v", r)
	}
	s, _ = OpenStore(db)
	if _, err := s.TokenUser(tok); err == nil {
		t.Fatal("bob's old session survived a password change")
	}
	if _, err := s.Authenticate("bob", "brand new password"); err != nil {
		t.Fatal("new password does not work")
	}
	s.Close()
	r = runCLI(t, "brand new password\n", env, "user", "passwd", "nobody")
	if r.code == 0 || !strings.Contains(r.err, "no such user") {
		t.Fatalf("passwd for nobody: %+v", r)
	}

	// Deleting asks you to type the name, unless told otherwise.
	r = runCLI(t, "wrong\n", env, "user", "delete", "bob")
	if r.code == 0 || !strings.Contains(r.err, "not deleted") {
		t.Fatalf("delete confirm: %+v", r)
	}
	r = runCLI(t, "bob\n", env, "user", "delete", "bob")
	if r.code != 0 || !strings.Contains(r.out, "deleted bob") {
		t.Fatalf("delete: %+v", r)
	}
	r = runCLI(t, "", env, "user", "delete", "alice", "-yes")
	if r.code != 0 {
		t.Fatalf("delete -yes: %+v", r)
	}
	r = runCLI(t, "", env, "user", "list")
	if !strings.Contains(r.out, "no users yet") {
		t.Fatalf("everyone deleted: %+v", r)
	}
}

func TestBackupCommand(t *testing.T) {
	dir := t.TempDir()
	env := map[string]string{"PODSYNC_DB": filepath.Join(dir, "a.db"), "PODSYNC_PASSWORD": "correct horse"}
	runCLI(t, "", env, "user", "add", "lane")
	copyTo := filepath.Join(dir, "backup.db")
	if r := runCLI(t, "", env, "backup", copyTo); r.code != 0 {
		t.Fatalf("backup: %+v", r)
	}
	if _, err := os.Stat(copyTo); err != nil {
		t.Fatal(err)
	}
	// It will not overwrite an existing file.
	if r := runCLI(t, "", env, "backup", copyTo); r.code == 0 || !strings.Contains(r.err, "already exists") {
		t.Fatalf("overwrite: %+v", r)
	}
	r := runCLI(t, "", map[string]string{"PODSYNC_DB": copyTo}, "user", "list")
	if !strings.Contains(r.out, "lane") {
		t.Fatalf("the backup is missing the user: %+v", r)
	}
}

func TestCommandLineBasics(t *testing.T) {
	if r := runCLI(t, "", nil, "version"); r.code != 0 || !strings.Contains(r.out, "podsync-server") {
		t.Fatalf("version: %+v", r)
	}
	if r := runCLI(t, "", nil, "help"); r.code != 0 || !strings.Contains(r.out, "user add") {
		t.Fatalf("help: %+v", r)
	}
	if r := runCLI(t, "", nil, "frobnicate"); r.code != 2 || !strings.Contains(r.err, "unknown command") {
		t.Fatalf("unknown: %+v", r)
	}
	if r := runCLI(t, "", map[string]string{"PODSYNC_DB": filepath.Join(t.TempDir(), "x.db")}, "user"); r.code != 2 {
		t.Fatalf("user without subcommand: %+v", r)
	}
	// With no server listening, the health check says so.
	if r := runCLI(t, "", map[string]string{"PODSYNC_ADDR": "127.0.0.1:1"}, "healthcheck"); r.code != 1 {
		t.Fatalf("healthcheck against nothing: %+v", r)
	}
}

func TestEnvironmentParsing(t *testing.T) {
	get := func(m map[string]string) func(string) string { return func(k string) string { return m[k] } }
	for in, want := range map[string]bool{"true": true, "1": true, "YES": true, "false": false, "off": false, "0": false} {
		if got := envBool(get(map[string]string{"X": in}), "X", !want); got != want {
			t.Errorf("envBool(%q) = %v", in, got)
		}
	}
	if envBool(get(nil), "X", true) != true || envBool(get(map[string]string{"X": "maybe"}), "X", false) != false {
		t.Error("fallbacks")
	}
	if envOr(get(map[string]string{"A": "set"}), "A", "d") != "set" || envOr(get(nil), "A", "d") != "d" {
		t.Error("envOr")
	}
}
