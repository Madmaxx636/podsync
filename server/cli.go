package main

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"text/tabwriter"
	"time"

	"golang.org/x/term"
)

var version = "dev" // set at build time: -ldflags "-X main.version=1.2.3"

const usage = `PodSync server

Usage:
  podsync-server [serve] [-addr :8080] [-db podsync.db] [-signup=true] [-trust-proxy]
  podsync-server user add NAME         add a user (password from PODSYNC_PASSWORD, or asked)
  podsync-server user list
  podsync-server user passwd NAME      change a user's password and sign them out elsewhere
  podsync-server user delete NAME [-yes]
  podsync-server backup FILE           write a consistent copy of the database
  podsync-server healthcheck           exit 0 if the running server answers
  podsync-server version

Settings can also come from the environment: PODSYNC_ADDR, PODSYNC_DB, PODSYNC_SIGNUP
(true or false) and PODSYNC_TRUST_PROXY. A flag wins over the environment.
`

func envOr(env func(string) string, key, fallback string) string {
	if v := env(key); v != "" {
		return v
	}
	return fallback
}

func envBool(env func(string) string, key string, fallback bool) bool {
	switch strings.ToLower(env(key)) {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	}
	return fallback
}

// run is the whole command line, with its inputs passed in so tests can drive it.
func run(args []string, in io.Reader, out, errOut io.Writer, env func(string) string) int {
	if len(args) == 0 || strings.HasPrefix(args[0], "-") {
		args = append([]string{"serve"}, args...)
	}
	cmd, rest := args[0], args[1:]
	switch cmd {
	case "serve":
		return cmdServe(rest, out, errOut, env)
	case "user":
		return cmdUser(rest, in, out, errOut, env)
	case "backup":
		return cmdBackup(rest, out, errOut, env)
	case "healthcheck":
		return cmdHealth(rest, errOut, env)
	case "version", "-v", "--version":
		fmt.Fprintln(out, "podsync-server", version)
		return 0
	case "help", "-h", "--help":
		fmt.Fprint(out, usage)
		return 0
	}
	fmt.Fprintf(errOut, "unknown command %q\n\n%s", cmd, usage)
	return 2
}

func openFromFlags(name string, rest []string, errOut io.Writer, env func(string) string) (*Store, *flag.FlagSet, bool) {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	fs.SetOutput(errOut)
	db := fs.String("db", envOr(env, "PODSYNC_DB", "podsync.db"), "database file")
	fs.Bool("yes", false, "do not ask for confirmation (user delete)")
	if err := fs.Parse(rest); err != nil {
		return nil, nil, false
	}
	store, err := OpenStore(*db)
	if err != nil {
		fmt.Fprintf(errOut, "cannot open %s: %v\n", *db, err)
		return nil, nil, false
	}
	return store, fs, true
}

func cmdServe(rest []string, out, errOut io.Writer, env func(string) string) int {
	fs := flag.NewFlagSet("serve", flag.ContinueOnError)
	fs.SetOutput(errOut)
	addr := fs.String("addr", envOr(env, "PODSYNC_ADDR", ":8080"), "listen address")
	db := fs.String("db", envOr(env, "PODSYNC_DB", "podsync.db"), "database file")
	signup := fs.Bool("signup", envBool(env, "PODSYNC_SIGNUP", true), "let people register themselves")
	proxy := fs.Bool("trust-proxy", envBool(env, "PODSYNC_TRUST_PROXY", false), "trust X-Forwarded-For (only behind your own reverse proxy)")
	if err := fs.Parse(rest); err != nil {
		return 2
	}
	store, err := OpenStore(*db)
	if err != nil {
		fmt.Fprintf(errOut, "cannot open %s: %v\n", *db, err)
		return 1
	}
	defer store.Close()

	srv := NewServer(store, *signup, *proxy, version)
	httpServer := &http.Server{
		Addr:              *addr,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       60 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       2 * time.Minute,
	}

	users, _ := store.ListUsers()
	srv.logger.Printf("podsync-server %s listening on %s, database %s, %d users, self-registration %s",
		version, *addr, *db, len(users), map[bool]string{true: "on", false: "off"}[*signup])

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() { // forget sessions nobody has used for half a year
		tick := time.NewTicker(24 * time.Hour)
		defer tick.Stop()
		for {
			if n, err := store.PruneSessions(180 * 24 * time.Hour); err == nil && n > 0 {
				srv.logger.Printf("removed %d unused sessions", n)
			}
			select {
			case <-ctx.Done():
				return
			case <-tick.C:
			}
		}
	}()

	errs := make(chan error, 1)
	go func() { errs <- httpServer.ListenAndServe() }()
	select {
	case err := <-errs:
		fmt.Fprintf(errOut, "server stopped: %v\n", err)
		return 1
	case <-ctx.Done():
		srv.logger.Printf("shutting down")
		shutdown, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		httpServer.Shutdown(shutdown)
		return 0
	}
}

// readPassword takes the password from PODSYNC_PASSWORD, asks on a terminal (twice, hidden),
// or reads one line from a pipe.
func readPassword(in io.Reader, errOut io.Writer, env func(string) string, who string) (string, error) {
	if pw := env("PODSYNC_PASSWORD"); pw != "" {
		return pw, nil
	}
	if f, ok := in.(*os.File); ok && term.IsTerminal(int(f.Fd())) {
		fmt.Fprintf(errOut, "Password for %s: ", who)
		a, err := term.ReadPassword(int(f.Fd()))
		fmt.Fprintln(errOut)
		if err != nil {
			return "", err
		}
		fmt.Fprint(errOut, "Again: ")
		b, err := term.ReadPassword(int(f.Fd()))
		fmt.Fprintln(errOut)
		if err != nil {
			return "", err
		}
		if string(a) != string(b) {
			return "", errors.New("the two passwords do not match")
		}
		return string(a), nil
	}
	line, err := bufio.NewReader(in).ReadString('\n')
	if err != nil && line == "" {
		return "", errors.New("no password given (set PODSYNC_PASSWORD or pipe it in)")
	}
	return strings.TrimRight(line, "\r\n"), nil
}

func cmdUser(rest []string, in io.Reader, out, errOut io.Writer, env func(string) string) int {
	if len(rest) == 0 {
		fmt.Fprint(errOut, usage)
		return 2
	}
	sub, rest := rest[0], rest[1:]
	// The name comes first, then flags: "user delete bob -yes".
	var name string
	if sub != "list" && len(rest) > 0 && !strings.HasPrefix(rest[0], "-") {
		name, rest = rest[0], rest[1:]
	}
	store, fs, ok := openFromFlags("user "+sub, rest, errOut, env)
	if !ok {
		return 1
	}
	defer store.Close()

	needName := func() bool {
		if name == "" {
			fmt.Fprintf(errOut, "usage: podsync-server user %s NAME\n", sub)
			return false
		}
		return true
	}

	switch sub {
	case "add":
		if !needName() {
			return 2
		}
		if msg := ValidateUsername(normalizeUsername(name)); msg != "" {
			fmt.Fprintln(errOut, msg)
			return 1
		}
		pw, err := readPassword(in, errOut, env, name)
		if err != nil {
			fmt.Fprintln(errOut, err)
			return 1
		}
		if _, err := store.CreateUser(name, pw); err != nil {
			fmt.Fprintln(errOut, err)
			return 1
		}
		fmt.Fprintf(out, "added %s\n", normalizeUsername(name))
	case "passwd":
		if !needName() {
			return 2
		}
		if _, err := store.UserID(name); err != nil {
			fmt.Fprintln(errOut, err)
			return 1
		}
		pw, err := readPassword(in, errOut, env, name)
		if err != nil {
			fmt.Fprintln(errOut, err)
			return 1
		}
		if err := store.SetPassword(name, pw, ""); err != nil {
			fmt.Fprintln(errOut, err)
			return 1
		}
		fmt.Fprintf(out, "changed the password for %s; their devices will need to sign in again\n", normalizeUsername(name))
	case "delete":
		if !needName() {
			return 2
		}
		yes := fs.Lookup("yes").Value.String() == "true"
		if !yes {
			fmt.Fprintf(errOut, "This deletes %s and all of their synced data. Type the name to confirm: ", name)
			line, _ := bufio.NewReader(in).ReadString('\n')
			if normalizeUsername(line) != normalizeUsername(name) {
				fmt.Fprintln(errOut, "not deleted")
				return 1
			}
		}
		if err := store.DeleteUser(name); err != nil {
			fmt.Fprintln(errOut, err)
			return 1
		}
		fmt.Fprintf(out, "deleted %s\n", normalizeUsername(name))
	case "list":
		users, err := store.ListUsers()
		if err != nil {
			fmt.Fprintln(errOut, err)
			return 1
		}
		if len(users) == 0 {
			fmt.Fprintln(out, "no users yet")
			return 0
		}
		tw := tabwriter.NewWriter(out, 0, 4, 2, ' ', 0)
		fmt.Fprintln(tw, "USER\tCREATED\tRECORDS\tDEVICES\tLAST SEEN")
		for _, u := range users {
			created, seen := "-", "never"
			if !u.CreatedAt.IsZero() {
				created = u.CreatedAt.Format("2006-01-02")
			}
			if !u.LastSeen.IsZero() {
				seen = u.LastSeen.Format("2006-01-02 15:04")
			}
			fmt.Fprintf(tw, "%s\t%s\t%d\t%d\t%s\n", u.Name, created, u.Records, u.Sessions, seen)
		}
		tw.Flush()
	default:
		fmt.Fprintf(errOut, "unknown user command %q\n\n%s", sub, usage)
		return 2
	}
	return 0
}

func cmdBackup(rest []string, out, errOut io.Writer, env func(string) string) int {
	if len(rest) == 0 || strings.HasPrefix(rest[0], "-") {
		fmt.Fprintln(errOut, "usage: podsync-server backup FILE")
		return 2
	}
	file := rest[0]
	if _, err := os.Stat(file); err == nil {
		fmt.Fprintf(errOut, "%s already exists; choose a new name\n", file)
		return 1
	}
	store, _, ok := openFromFlags("backup", rest[1:], errOut, env)
	if !ok {
		return 1
	}
	defer store.Close()
	if err := store.Backup(file); err != nil {
		fmt.Fprintf(errOut, "backup failed: %v\n", err)
		return 1
	}
	fmt.Fprintf(out, "wrote %s\n", file)
	return 0
}

// cmdHealth asks the running server on this machine whether it is well. Used by the container's HEALTHCHECK.
func cmdHealth(rest []string, errOut io.Writer, env func(string) string) int {
	fs := flag.NewFlagSet("healthcheck", flag.ContinueOnError)
	fs.SetOutput(errOut)
	addr := fs.String("addr", envOr(env, "PODSYNC_ADDR", ":8080"), "address of the server")
	if err := fs.Parse(rest); err != nil {
		return 2
	}
	_, port, err := net.SplitHostPort(*addr)
	if err != nil {
		port = "8080"
	}
	client := http.Client{Timeout: 4 * time.Second}
	res, err := client.Get("http://127.0.0.1:" + port + "/api/health")
	if err != nil {
		fmt.Fprintln(errOut, err)
		return 1
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		fmt.Fprintf(errOut, "server answered HTTP %d\n", res.StatusCode)
		return 1
	}
	return 0
}
