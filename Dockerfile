# gonic packaged for Railway: the official image, pinned by version and digest,
# plus a small start script. Bump the tag and digest together and add a
# CHANGELOG.md entry: a merge to main notifies everyone who deployed the template.
FROM sentriz/gonic:v0.23.0@sha256:7b2298d905149ecb7e57cdd3bf7a40082758b9bda2e24454b41c17c99bf25e8f

# curl is only used by the start script, on loopback, to replace gonic's
# built-in admin/admin login with GONIC_ADMIN_PASSWORD on a fresh volume.
RUN apk add --no-cache curl

# Everything gonic writes lives under /data (the Railway volume):
#   /data/gonic.db    SQLite database (users, play counts, settings, sessions)
#   /data/music       your music library (one folder per album)
#   /data/podcasts    podcast episodes downloaded from the web UI
#   /data/playlists   m3u playlists, one folder per user id
#   /data/cache       transcodes and cover art (size-capped below)
ENV GONIC_DB_PATH=/data/gonic.db \
    GONIC_MUSIC_PATH=/data/music \
    GONIC_PODCAST_PATH=/data/podcasts \
    GONIC_PLAYLISTS_PATH=/data/playlists \
    GONIC_CACHE_PATH=/data/cache \
    GONIC_SCAN_AT_START_ENABLED=true \
    GONIC_SCAN_WATCHER_ENABLED=true \
    GONIC_SCAN_INTERVAL=360 \
    GONIC_TRANSCODE_CACHE_SIZE=1024 \
    GONIC_TRANSCODE_EJECT_INTERVAL=60 \
    GONIC_COVER_CACHE_SIZE=256 \
    GONIC_COVER_EJECT_INTERVAL=60

COPY start.sh /usr/local/bin/gonic-railway-start
RUN chmod 0755 /usr/local/bin/gonic-railway-start

EXPOSE 4747
# tini (from the upstream image) forwards signals and reaps ffmpeg/mpv children.
# An unexpected stop exits non-zero, so Railway's ON_FAILURE policy restarts it.
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/gonic-railway-start"]
