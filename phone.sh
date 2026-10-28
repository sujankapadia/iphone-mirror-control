#!/usr/bin/env bash
# Drive the iPhone through macOS iPhone Mirroring: capture the window, post
# synthetic input into it. See SKILL.md for the model and the caveats.
set -euo pipefail

APP="iPhone Mirroring"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="${TMPDIR:-/tmp}/phone"
BIN="$STATE/input"
SIDECAR="$STATE/last.geom"
mkdir -p "$STATE"

# Compile the CGEvent helper on first use, or whenever the source is newer.
if [ ! -x "$BIN" ] || [ "$DIR/input.swift" -nt "$BIN" ]; then
  swiftc -O -o "$BIN" "$DIR/input.swift" 2>/dev/null \
    || { echo "failed to build input helper from $DIR/input.swift" >&2; exit 1; }
fi

usage() {
  cat <<'USAGE'
phone.sh <command>

  shot [-o FILE]        capture the mirrored screen; prints the path
  tap X Y               tap at IMAGE pixel coords from the last shot
  swipe X1 Y1 X2 Y2 [MS]  drag between image coords (default 400ms)
  scroll X Y LINES      scroll at image coords (+ up, - down)
  type "TEXT"           type text
  key NAME              return|delete|escape|tab|space|up|down|left|right
  home | apps | spotlight   navigate via the View menu
  status                is the session up?
  quit                  end the mirroring session

Coordinates are ALWAYS image pixels read off the last `shot`. The script
converts to screen points itself and refuses if the window has moved since.
USAGE
}

running() { pgrep -xq "$APP" 2>/dev/null; }

require_running() {
  running || { echo "iPhone Mirroring is not running. Start it with: open -a '$APP'" >&2; exit 1; }
}

# Live window id + geometry from the window server. Never cache across
# commands: the window moves and resizes when the session connects, and stale
# coordinates silently address the wrong part of the screen.
geom() {
  "$BIN" window "$APP" 2>/dev/null   # -> "id x y w h"
}

activate() {
  # Load-bearing. A synthetic click on a background window is consumed
  # activating it and never reaches the phone UI.
  osascript -e "tell application \"$APP\" to activate" >/dev/null 2>&1
  sleep 0.3
}

# Translate image pixels -> screen points using the scale recorded at shot time.
to_screen() {
  [ -f "$SIDECAR" ] || { echo "no previous shot; run: phone.sh shot" >&2; exit 1; }
  # shellcheck disable=SC1090
  . "$SIDECAR"
  local now; now=$(geom)
  [ -n "$now" ] || { echo "no mirroring window" >&2; exit 1; }
  read -r nid nx ny nw nh <<<"$now"
  if [ "$nx $ny $nw $nh" != "$SX $SY $SW $SH" ]; then
    echo "window moved since last shot ($SX $SY $SW $SH -> $nx $ny $nw $nh)." >&2
    echo "coordinates would be wrong; run: phone.sh shot" >&2
    exit 1
  fi
  SCR_X=$(awk -v o="$SX" -v p="$1" -v s="$SCALE" 'BEGIN{printf "%.0f", o + p/s}')
  SCR_Y=$(awk -v o="$SY" -v p="$2" -v s="$SCALE" 'BEGIN{printf "%.0f", o + p/s}')
}

menu_item() {
  require_running; activate
  osascript -e "tell application \"System Events\" to tell process \"$APP\" to click menu item \"$1\" of menu 1 of menu bar item \"View\" of menu bar 1" >/dev/null
  echo "$1"
}

cmd="${1:-}"; shift || true
case "$cmd" in

  shot)
    require_running
    OUT=""
    [ "${1:-}" = "-o" ] && { OUT="$2"; shift 2; }
    [ -n "$OUT" ] || OUT="$STATE/shot-$(date +%H%M%S).png"
    g=$(geom); [ -n "$g" ] || { echo "no mirroring window" >&2; exit 1; }
    read -r id x y w h <<<"$g"
    # -l<id> captures the window itself. -R would capture the screen region and
    # hand back whatever app happens to be stacked on top of the phone.
    screencapture -o -x -l"$id" "$OUT"
    pw=$(sips -g pixelWidth "$OUT" 2>/dev/null | awk '/pixelWidth/{print $2}')
    scale=$(awk -v p="$pw" -v w="$w" 'BEGIN{printf "%.4f", p/w}')
    printf 'SX=%s\nSY=%s\nSW=%s\nSH=%s\nSCALE=%s\n' "$x" "$y" "$w" "$h" "$scale" > "$SIDECAR"
    echo "$OUT"
    ;;

  tap)
    [ $# -ge 2 ] || { echo "tap X Y" >&2; exit 1; }
    require_running; activate
    to_screen "$1" "$2"
    "$BIN" click "$SCR_X" "$SCR_Y" >/dev/null
    echo "tapped image($1,$2) -> screen($SCR_X,$SCR_Y)"
    ;;

  swipe)
    [ $# -ge 4 ] || { echo "swipe X1 Y1 X2 Y2 [MS]" >&2; exit 1; }
    require_running; activate
    to_screen "$1" "$2"; ax=$SCR_X; ay=$SCR_Y
    to_screen "$3" "$4"; bx=$SCR_X; by=$SCR_Y
    "$BIN" drag "$ax" "$ay" "$bx" "$by" "${5:-400}" >/dev/null
    echo "swiped ($1,$2) -> ($3,$4)"
    ;;

  scroll)
    [ $# -ge 3 ] || { echo "scroll X Y LINES" >&2; exit 1; }
    require_running; activate
    to_screen "$1" "$2"
    "$BIN" scroll "$SCR_X" "$SCR_Y" "$3" >/dev/null
    echo "scrolled $3 at ($1,$2)"
    ;;

  type)
    [ $# -ge 1 ] || { echo 'type "TEXT"' >&2; exit 1; }
    require_running; activate
    osascript -e "tell application \"System Events\" to keystroke \"$(printf '%s' "$1" | sed 's/[\\"]/\\&/g')\"" >/dev/null
    echo "typed ${#1} chars"
    ;;

  key)
    [ $# -ge 1 ] || { echo "key NAME" >&2; exit 1; }
    case "$1" in
      return) c=36 ;; delete) c=51 ;; escape) c=53 ;; tab) c=48 ;; space) c=49 ;;
      left) c=123 ;; right) c=124 ;; down) c=125 ;; up) c=126 ;;
      *) echo "unknown key: $1" >&2; exit 1 ;;
    esac
    require_running; activate
    osascript -e "tell application \"System Events\" to key code $c" >/dev/null
    echo "key $1"
    ;;

  home)      menu_item "Home Screen" ;;
  apps)      menu_item "App Switcher" ;;
  spotlight) menu_item "Spotlight" ;;

  status)
    if running; then
      g=$(geom)
      if [ -n "$g" ]; then
        read -r id x y w h <<<"$g"
        echo "running; window id $id at $x,$y size ${w}x${h}"
      else
        echo "running; no window (not connected?)"
      fi
    else
      echo "not running"
    fi
    ;;

  quit)
    running && osascript -e "tell application \"$APP\" to quit" >/dev/null 2>&1 || true
    rm -f "$SIDECAR"
    echo "session ended"
    ;;

  ""|-h|--help|help) usage ;;
  *) echo "unknown command: $cmd" >&2; usage >&2; exit 1 ;;
esac
