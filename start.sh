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
WORK="$(mktemp -d)"
trap 'rm -r "$WORK"' EXIT

mkdir -p "$DATA_DIR" "$GONIC_MUSIC_PATH" "$GONIC_PODCAST_PATH" "$GONIC_PLAYLISTS_PATH" "$GONIC_CACHE_PATH"
if [ ! -w "$DATA_DIR" ]; then
  log "ERROR: $DATA_DIR is not writable; attach a Railway volume at $DATA_DIR"
  exit 1
fi

# Percent-encode every byte, so any password survives the form post.
urlencode() { printf '%s' "$1" | od -An -tx1 -v | tr -d ' \n' | sed 's/../%&/g'; }

# post PATH BODYFILE [COOKIE] -> raw HTTP response headers. BusyBox wget follows
# gonic's 303 as another POST and loses the session cookie, so speak HTTP/1.0
# over BusyBox nc instead. The body comes from a file and printf is a shell
# builtin, so the password never shows in the process list.
post() {
  {
    printf 'POST %s HTTP/1.0\r\nHost: 127.0.0.1\r\n' "$1"
    printf 'Content-Type: application/x-www-form-urlencoded\r\nContent-Length: %s\r\n' "$(wc -c <"$2" | tr -d ' ')"
    [ -n "${3:-}" ] && printf 'Cookie: %s\r\n' "$3"
    printf '\r\n'
    cat "$2"
  } | nc -w 10 127.0.0.1 "$SETUP_PORT" 2>/dev/null | sed '/^\r*$/q' || true
}
first_location() { grep -i -m1 '^location:' | sed 's/^[Ll]ocation: *//' | tr -d '\r'; }
first_cookie() { grep -i -m1 '^set-cookie:' | sed 's/^[Ss]et-[Cc]ookie: *//; s/;.*//' | tr -d '\r'; }

# login USER PASSWORD -> writes headers to $WORK/login.h
login() {
  printf 'username=%s&password=%s' "$(urlencode "$1")" "$(urlencode "$2")" >"$WORK/login.b"
  post /admin/login_do "$WORK/login.b" >"$WORK/login.h"
}
login_ok() { [ "$(first_location <"$WORK/login.h")" = "/admin/home" ]; }

set_admin_password() {
  password="${GONIC_ADMIN_PASSWORD:-}"
  if [ -z "$password" ] || [ "$password" = "admin" ]; then
    log "ERROR: GONIC_ADMIN_PASSWORD is empty or 'admin'; set it in the service variables"
    return 1
  fi

  GONIC_LISTEN_ADDR="127.0.0.1:$SETUP_PORT" GONIC_SCAN_AT_START_ENABLED=false \
    GONIC_SCAN_WATCHER_ENABLED=false GONIC_SCAN_INTERVAL=0 GONIC_HTTP_LOG=false \
    gonic >"$WORK/setup.log" 2>&1 &
  pid=$!

  i=0
  until wget -q -T 2 -O /dev/null "$SETUP/ping" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 120 ] || ! kill -0 "$pid" 2>/dev/null; then
      log "setup instance did not start:"; cat "$WORK/setup.log"
      kill "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 0.5
  done

  rc=1
  login admin admin
  if login_ok; then
    cookie="$(first_cookie <"$WORK/login.h")"
    enc="$(urlencode "$password")"
    printf 'password_one=%s&password_two=%s' "$enc" "$enc" >"$WORK/pw.b"
    post "/admin/change_password_do?user=admin" "$WORK/pw.b" "$cookie" >/dev/null
    login admin "$password"
    if login_ok; then
      log "set the password of user 'admin' from GONIC_ADMIN_PASSWORD"; rc=0
    else
      log "ERROR: the new admin password did not work after changing it"
    fi
  else
    # admin/admin no longer works: the password (or the user name) was already changed.
    log "the default admin/admin login is already gone; leaving accounts alone"
    rc=0
  fi

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

rm -r "$WORK"; trap - EXIT
export GONIC_LISTEN_ADDR="0.0.0.0:$PORT"
log "starting gonic on $GONIC_LISTEN_ADDR"
exec gonic "$@"
