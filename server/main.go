// podsync-server: a small self-hosted sync server for PodSync. Many people can have an account on
// one server; each person's subscriptions, progress, queue, favorites, ratings and settings sync
// between their own devices. Run it with `podsync-server`, manage people with `podsync-server user`.
package main

import "os"

func main() {
	os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr, os.Getenv))
}
