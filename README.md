[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/gonic?utm_medium=integration&utm_source=button&utm_campaign=gonic)

# gonic on Railway

[gonic](https://github.com/sentriz/gonic) (GPL-3.0) as a Railway template: a lightweight music server that speaks the Subsonic API, so you can stream your own music library to Subsonic and OpenSubsonic apps (Symfonium, Amperfy, DSub, Ultrasonic, Tempus, Feishin, airsonic-refix, Strawberry and many more). The service builds from this repository, so when `main` moves to a newer gonic release, Railway offers the update to everyone who deployed the template.

Version: **gonic v0.23.0**, official image `sentriz/gonic:v0.23.0@sha256:7b2298d905149ecb7e57cdd3bf7a40082758b9bda2e24454b41c17c99bf25e8f`.

## What it deploys

| Railway service | Source | Volume | Role |
|---|---|---|---|
| `gonic` | this repo (`Dockerfile`, `start.sh`) | `/data` | Subsonic API (`/rest`), admin web UI (`/admin`) and health check (`/ping`) on a public domain |

gonic keeps everything in an embedded SQLite database, so there is no separate database service. Everything lives on the one volume:

- `/data/gonic.db`: users, play counts, starred items, settings and sessions
- `/data/music`: your music library, one folder per album (scanned at start, on file changes and every 6 hours)
- `/data/podcasts`: podcast episodes you subscribe to in the web UI
- `/data/playlists`: m3u playlists, one folder per user id
- `/data/cache`: transcodes (capped at 1 GB) and cover art (capped at 256 MB)

It needs very little: about 30 MB of RAM idle, so it runs on Railway's smallest plans. Transcoding uses ffmpeg and takes more CPU while it runs.

## First boot and login

Upstream gonic creates its first user as `admin` / `admin`. On a fresh volume, `start.sh` first runs gonic on loopback only, changes that password to the generated `GONIC_ADMIN_PASSWORD`, checks the new login works, and only then listens on the public port. If that fails, the container exits with an error instead of serving the default login. It runs once per volume, so a redeploy never resets a password you changed in the web UI.

1. Open the public URL; it redirects to `/admin`.
2. Sign in as **admin** with the password from the service's **Variables** tab (`GONIC_ADMIN_PASSWORD`).
3. Change the password (and create more users) in the web UI if you like. Changing the variable later does not change the account.
4. In your Subsonic app, use the public URL as the server address and the same user and password.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `GONIC_ADMIN_PASSWORD` | `${{secret(24, …)}}` | Generated password that replaces `admin`/`admin` on first start |
| `PORT` | `4747` | Port gonic listens on and the domain targets |

Optional: `TZ` for the server's time zone, and any gonic setting from the [configuration options](https://github.com/sentriz/gonic#configuration-options) as an environment variable, for example `GONIC_SCAN_INTERVAL` (minutes, default `360` here), `GONIC_TRANSCODE_CACHE_SIZE` (MB, default `1024` here), `GONIC_PODCAST_PURGE_AGE` or `GONIC_EXCLUDE_PATTERN`. Last.fm and ListenBrainz scrobbling are set up per user in the web UI. Jukebox mode (server-side playback) is off, because a Railway server has no speakers.

## Adding music

gonic has no web upload. Put files on the volume with the Railway CLI (run `railway link` in a folder first). Paths in `railway volume files` start at the volume root, which is `/data` inside the container:

```sh
railway volume files upload ./Artist/Album /music/Artist/Album
```

The file watcher picks up new files within seconds; you can also start a scan from the web UI. Keep each album in its own folder (see [directory structure](https://github.com/sentriz/gonic#directory-structure)). Size the volume for your library.

## Updates

Each release of this repo pins one gonic version by tag and digest in `Dockerfile`. When it changes on `main`, Railway shows deployers an update notice; read [CHANGELOG.md](CHANGELOG.md) first (breaking changes are listed first), then apply it. gonic migrates its database on start. Take a volume backup in Railway before big jumps.

## Local test

```sh
docker build -t gonic-railway .
docker run --rm -p 4747:4747 -v gonic-data:/data -e GONIC_ADMIN_PASSWORD=change-me gonic-railway
```

Then open http://localhost:4747 and sign in as `admin` / `change-me`.
