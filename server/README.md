# PodSync server

A small server that keeps your podcast data in step across your devices: subscriptions, listening
progress, the Up Next queue, favorites, ratings and playback settings. Many people can share one
server; each person only ever sees their own data.

One file to back up, one container to run, nothing else to install.

## Quickest way: the scripts

Everything below is wrapped in scripts in `scripts/`; run them from the `server` folder.

| Script | What it does |
|---|---|
| `./scripts/install.sh` | First setup: builds, starts, waits, prints the address for the app, offers to create your account |
| `./scripts/adduser.sh NAME` | Add a person (`--list`, `--passwd NAME`, `--delete NAME` too) |
| `./scripts/signup.sh off` | Close self-registration (`on` opens it again) |
| `./scripts/backup.sh` | Consistent backup into `backups/` (keeps 14); `--cron` schedules it daily |
| `./scripts/restore.sh FILE` | Put a backup back (takes a backup of the current data first) |
| `./scripts/update.sh` | Backup, `git pull`, rebuild |
| `./scripts/https.sh DOMAIN EMAIL` | Add Caddy for HTTPS with an automatic certificate |
| `./scripts/duckdns.sh` | Keep a DuckDNS name pointed at your network (`--cron` every 5 minutes) |

Set `PODSYNC_PORT=9090` before `install.sh` to use another port.

## Run it

```bash
cd server
docker compose up -d
```

The server now listens on port 8080. In the PodSync app, open Settings > Sync > PodSync server,
enter `http://YOUR-SERVER:8080` and create an account (or sign in).

Check it is up: `curl http://localhost:8080/api/health`

## People

By default anyone who can reach the server can create an account. That is fine at home. To close it
once everyone has one, set `PODSYNC_SIGNUP: "false"` in `docker-compose.yml` and run
`docker compose up -d` again. You can still add people yourself:

```bash
docker compose exec podsync podsync-server user add alice      # asks for a password
docker compose exec podsync podsync-server user list
docker compose exec podsync podsync-server user passwd alice   # also signs them out elsewhere
docker compose exec podsync podsync-server user delete alice   # and everything they synced
```

Usernames are 3 to 32 letters, numbers, dots, dashes or underscores, and are not case sensitive.
Passwords are 8 to 72 characters. Without a terminal you can give the password with
`-e PODSYNC_PASSWORD=...` on the `exec`.

## Use it over the internet

The server speaks plain HTTP. If it is reachable from outside your home, put it behind something
that adds HTTPS. With [Caddy](https://caddyserver.com) that is two lines:

```
sync.example.com {
    reverse_proxy localhost:8080
}
```

Then set `PODSYNC_TRUST_PROXY: "true"` so the server sees each person's real address (used to slow
down password guessing), and use `https://sync.example.com` in the app. Only turn that setting on
when the server can be reached *only* through your proxy.

## Backups

All data is in one SQLite file in the `podsync-data` volume. To take a consistent copy while the
server is running:

```bash
docker compose exec podsync podsync-server backup /data/backup-$(date +%F).db
docker compose cp podsync:/data/backup-$(date +%F).db .
```

To restore, stop the server, put the file back as `podsync.db` in the volume, and start it again.
Devices that are ahead of a restored backup start over and re-send what the server lost.

## Update

```bash
git pull
docker compose up -d --build
```

Data lives in the volume, so it survives. Updates keep everyone signed in.

## Settings

| Variable | Default | |
|---|---|---|
| `PODSYNC_ADDR` | `:8080` | address to listen on |
| `PODSYNC_DB` | `/data/podsync.db` | database file |
| `PODSYNC_SIGNUP` | `true` | may people register themselves |
| `PODSYNC_TRUST_PROXY` | `false` | read the client address from `X-Forwarded-For` |

## What it does and does not do

- Passwords are stored as bcrypt hashes. Session tokens are stored only as hashes, so a copy of the
  database does not contain working sessions. Sessions unused for 180 days are removed.
- Five wrong passwords for a name, or twenty from one address, lock that name or address for five
  minutes.
- It keeps only what the app syncs: no listening history beyond progress, no email addresses, no
  tracking. The access log has no query strings or bodies.
- It does not send email, so there is no "forgot password": the owner resets it with `user passwd`.
- It is not the gPodder protocol. The app can sync with gPodder servers separately, but a gPodder
  server cannot store the queue, favorites or settings, which is what this one is for.

## API (for the curious)

All JSON. Sessions are `Authorization: Bearer TOKEN`.

| | |
|---|---|
| `POST /api/register` `{username, password, device}` | create an account, returns `{token}` |
| `POST /api/login` `{username, password, device}` | returns `{token}` |
| `POST /api/logout` | ends this session |
| `GET /api/me` | your username, record count and signed-in devices |
| `POST /api/password` `{old, new}` | change password; other devices are signed out |
| `POST /api/sync` `{since, changes}` | send changes, get everything newer; newest `updated_at` wins |
| `GET /api/health` | `{status, version}`, no sign-in needed |

## Without Docker

```bash
go build -o podsync-server .
./podsync-server -addr :8080 -db podsync.db
```

Tests: `go test ./...`
