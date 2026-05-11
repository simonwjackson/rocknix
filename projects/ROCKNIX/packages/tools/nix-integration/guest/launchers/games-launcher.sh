#!/bin/sh
# games-launcher.sh -- touch-friendly game picker pinned to DSI-2
#
# Pops a fuzzel menu on the bottom touchscreen with a list of game
# launchers. Tap an entry to start it. After the game exits, the
# menu reopens so the screen never goes idle on a blank fuzzel.
#
# Run from inside the Layer 14 nspawn guest:
#   /storage/.guest/games-launcher.sh
#
# Bind it to a sway hotkey for keyboard access:
#   bindsym $mod+g exec /storage/.guest/games-launcher.sh

set -eu

PATH=/run/current-system/sw/bin:/usr/bin:/bin
export PATH
export XDG_RUNTIME_DIR=/run/user/0
export WAYLAND_DISPLAY=wayland-1

# Discover sway socket so swaymsg works.
SOCK=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.0.*.sock 2>/dev/null | head -1 || true)
if [ -n "$SOCK" ]; then
  export SWAYSOCK="$SOCK"
fi

# Render the launcher on DSI-1 (Thor's bottom panel; DSI-2 is the
# main top screen where games render). fuzzel uses the focused
# output, so we have to re-focus DSI-1 before EVERY fuzzel call --
# launchers like botw-guest.sh focus DSI-2 to put cemu on the main
# screen, and that focus change carries over after the game exits.
focus_launcher_screen() {
  if [ -n "${SWAYSOCK:-}" ]; then
    swaymsg "focus output DSI-1" >/dev/null 2>&1 || true
  fi
}

# Game catalogue. Add entries here as more launchers are validated.
# Format:  Display Name|/path/to/launcher.sh [args...]
#
# All BOTW entries call the same parametric script with a profile name.
# Order: most aggressive at top, most conservative at bottom.
ENTRIES=$(cat <<'EOF'
🗡️  BOTW · 720p / 45 FPS  (FAST)|/storage/.guest/botw-guest.sh 720p-45
🗡️  BOTW · 540p / 45 FPS  (FAST)|/storage/.guest/botw-guest.sh 540p-45
🗡️  BOTW · 1080p / 30 FPS (NATIVE)|/storage/.guest/botw-guest.sh native-30
🗡️  BOTW · 900p / 30 FPS|/storage/.guest/botw-guest.sh 900p-30
🗡️  BOTW · 720p / 30 FPS|/storage/.guest/botw-guest.sh 720p-30
🗡️  BOTW · 540p / 30 FPS|/storage/.guest/botw-guest.sh 540p-30
🗡️  BOTW · 360p / 30 FPS (POTATO)|/storage/.guest/botw-guest.sh potato-30
EOF
)

# Loop forever so fuzzel reopens after the chosen launcher returns.
while :; do
  focus_launcher_screen
  CHOICE=$(printf '%s\n' "$ENTRIES" \
    | awk -F'|' '{ print $1 }' \
    | fuzzel \
        --dmenu \
        --prompt="🎮 " \
        --lines=10 \
        --width=36 \
        --font="monospace:size=18" \
        --no-icons \
        --background-color=000000ee \
        --text-color=ffffffff \
        --selection-color=ff8800ff \
        --selection-text-color=000000ff \
        --border-color=ff8800ff \
        --border-width=4 \
        --border-radius=12 \
      || true)

  # User pressed Esc / closed without choosing -> short pause then reopen.
  if [ -z "$CHOICE" ]; then
    sleep 1
    continue
  fi

  # Resolve display name back to launcher path.
  LAUNCHER=$(printf '%s\n' "$ENTRIES" \
    | awk -F'|' -v want="$CHOICE" '$1 == want { print $2; exit }')

  # Split launcher path from any args (sh-style word split is fine here).
  LAUNCHER_BIN=$(printf '%s\n' "$LAUNCHER" | awk '{ print $1 }')

  if [ -z "$LAUNCHER_BIN" ] || [ ! -x "$LAUNCHER_BIN" ]; then
    swaymsg "exec foot --title=launcher-error sh -c 'echo \"Launcher not found: $CHOICE -> $LAUNCHER\"; sleep 3'" >/dev/null 2>&1 || true
    sleep 1
    continue
  fi

  # Run launcher in foreground; menu blocks until game exits.
  # Use sh -c so the args after $LAUNCHER_BIN are word-split.
  sh -c "$LAUNCHER" || true
done
