# Changelog

Each entry is one version of this template. Breaking changes are listed first.
Applying an update rebuilds the service from this repo; your volume (`/data`) is kept.

## gonic v0.23.0 (2026-11-21)

- First release of the template: official image `sentriz/gonic:v0.23.0`, pinned by digest
  `sha256:7b2298d905149ecb7e57cdd3bf7a40082758b9bda2e24454b41c17c99bf25e8f`.
- All state on one volume at `/data` (database, music, podcasts, playlists, cache).
- The built-in `admin`/`admin` login is replaced on first start with the generated `GONIC_ADMIN_PASSWORD`.
- Health check `/ping`; library scan at start, on file changes and every 6 hours; transcode cache capped at 1 GB.
