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
# main top screen where games render). fuzzel uses focused output.
if [ -n "${SWAYSOCK:-}" ]; then
  swaymsg "focus output DSI-1" >/dev/null 2>&1 || true
fi

# Game catalogue. Add entries here as more launchers are validated.
# Format:  Display Name|/path/to/launcher.sh
ENTRIES=$(cat <<'EOF'
🗡️  BOTW · 540p / 30 FPS|/storage/.guest/botw-540p-30-guest.sh
EOF
)

# Loop forever so fuzzel reopens after the chosen launcher returns.
while :; do
  CHOICE=$(printf '%s\n' "$ENTRIES" \
    | awk -F'|' '{ print $1 }' \
    | fuzzel \
        --dmenu \
        --prompt="🎮 " \
        --lines=8 \
        --width=28 \
        --font="monospace:size=20" \
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

  if [ -z "$LAUNCHER" ] || [ ! -x "$LAUNCHER" ]; then
    # Fallback: notify and loop. Foot is available if notify-send is not.
    swaymsg "exec foot --title=launcher-error sh -c 'echo \"Launcher not found: $CHOICE -> $LAUNCHER\"; sleep 3'" >/dev/null 2>&1 || true
    sleep 1
    continue
  fi

  # Run launcher in foreground; menu blocks until game exits.
  "$LAUNCHER" || true
done
