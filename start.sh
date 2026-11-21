#!/bin/sh
# Start gonic on Railway.
# 1. Keep all state on the volume mounted at /data.
# 2. gonic creates its first user as admin/admin. On a fresh volume, run gonic
#    on loopback only, change that password to GONIC_ADMIN_PASSWORD through
#    gonic's own admin form, check the new login works, and stop it again.
#    Only then listen on $PORT. If that fails, exit non-zero rather than serve
#    a public admin/admin login.
# 3. Listen on 0.0.0.0:$PORT (Railway) or 4747.
set -eu

log() { echo "gonic-railway: $*"; }

DATA_DIR="${GONIC_DATA_DIR:-/data}"
PORT="${PORT:-4747}"
MARKER="$DATA_DIR/.railway-admin-password-set"
SETUP_PORT=4799
SETUP="http://127.0.0.1:$SETUP_PORT"

mkdir -p "$DATA_DIR" "$GONIC_MUSIC_PATH" "$GONIC_PODCAST_PATH" "$GONIC_PLAYLISTS_PATH" "$GONIC_CACHE_PATH"
if [ ! -w "$DATA_DIR" ]; then
  log "ERROR: $DATA_DIR is not writable; attach a Railway volume at $DATA_DIR"
  exit 1
fi

# curl reads form fields from stdin (-K -), so the password never shows in the
# process list. Escape for curl's config syntax.
cfg_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# login USER PASSWORD JAR -> prints where gonic redirects (…/admin/home on success)
login() {
  u="$(cfg_escape "$1")"; p="$(cfg_escape "$2")"
  curl -sS --max-time 10 -o /dev/null -w '%{redirect_url}' -c "$3" -b "$3" \
    -X POST "$SETUP/admin/login_do" -K - <<CFG
data-urlencode = "username=$u"
data-urlencode = "password=$p"
CFG
}

set_admin_password() {
  password="${GONIC_ADMIN_PASSWORD:-}"
  if [ -z "$password" ] || [ "$password" = "admin" ]; then
    log "ERROR: GONIC_ADMIN_PASSWORD is empty or 'admin'; set it in the service variables"
    return 1
  fi

  GONIC_LISTEN_ADDR="127.0.0.1:$SETUP_PORT" GONIC_SCAN_AT_START_ENABLED=false \
    GONIC_SCAN_WATCHER_ENABLED=false GONIC_SCAN_INTERVAL=0 GONIC_HTTP_LOG=false \
    gonic >/tmp/gonic-setup.log 2>&1 &
  pid=$!

  i=0
  until curl -fsS --max-time 2 "$SETUP/ping" >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge 120 ] || ! kill -0 "$pid" 2>/dev/null; then
      log "setup instance did not start:"; cat /tmp/gonic-setup.log
      kill "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 0.5
  done

  jar="$(mktemp)"; rc=1
  case "$(login admin admin "$jar")" in
    */admin/home)
      p="$(cfg_escape "$password")"
      curl -sS --max-time 10 -o /dev/null -c "$jar" -b "$jar" \
        -X POST "$SETUP/admin/change_password_do?user=admin" -K - <<CFG
data-urlencode = "password_one=$p"
data-urlencode = "password_two=$p"
CFG
      : >"$jar"
      case "$(login admin "$password" "$jar")" in
        */admin/home) log "set the password of user 'admin' from GONIC_ADMIN_PASSWORD"; rc=0 ;;
        *) log "ERROR: the new admin password did not work after changing it" ;;
      esac
      ;;
    *)
      # admin/admin no longer works: someone already changed it (or renamed admin).
      log "the default admin/admin login is already gone; leaving accounts alone"
      rc=0
      ;;
  esac
  rm "$jar"

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  [ "$rc" -eq 0 ] && : >"$MARKER"
  return "$rc"
}

if [ ! -e "$MARKER" ]; then
  log "first start on this volume: replacing the default admin/admin login"
  if ! set_admin_password; then
    log "ERROR: could not replace the default admin password; refusing to start"
    exit 1
  fi
fi

export GONIC_LISTEN_ADDR="0.0.0.0:$PORT"
log "starting gonic on $GONIC_LISTEN_ADDR"
exec gonic "$@"
