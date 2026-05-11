#!/bin/sh
# remote-cemu-build-fingerprint.sh -- host-side Cemu build/runtime fingerprint.
#
# Runs on the ROCKNIX host. Creates a timestamped report under
# /storage/.guest/runs and compares the ROCKNIX host Cemu binary with
# guest Cemu binaries without mutating runtime state.
set -u

PATH=/run/current-system/sw/bin:/usr/bin:/bin:/storage/.guest:$PATH
export PATH

TS="$(date '+%Y%m%d-%H%M%S')"
RUN_DIR="${FINGERPRINT_RUN_DIR:-/storage/.guest/runs/${TS}-cemu-build-fingerprint}"
REPORT="$RUN_DIR/report.md"
HOST_CEMU="${HOST_CEMU:-/usr/bin/cemu}"
GUEST_CEMU="${GUEST_CEMU:-/run/current-system/sw/bin/cemu}"
CANDIDATE_CEMU="${CANDIDATE_CEMU:-}"
CEMU_COMMIT="6f6c1299e29fa6e1062ae283a035b4ef787cc397"

mkdir -p "$RUN_DIR"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$RUN_DIR/status.log" >&2; }

host_cmd() {
  command -v "$1" >/dev/null 2>&1
}

guest_pid() {
  main="$(systemctl show -p MainPID --value rocknix-guest-v2.service 2>/dev/null || true)"
  [ -n "$main" ] && [ "$main" != "0" ] || return 1
  pgrep -P "$main" 2>/dev/null | head -1
}

run_guest() {
  gp="$(guest_pid)" || return 1
  nsenter -t "$gp" -m -u -i -n -p -r -w /bin/sh -c "$1"
}

append_cmd() {
  title="$1"
  shift
  {
    printf '\n#### %s\n\n```text\n' "$title"
    "$@" 2>&1 || printf 'command failed: %s\n' "$*"
    printf '\n```\n'
  } >> "$REPORT"
}

append_guest_cmd() {
  title="$1"
  cmd="$2"
  {
    printf '\n#### %s\n\n```text\n' "$title"
    run_guest "$cmd" 2>&1 || printf 'guest command failed: %s\n' "$cmd"
    printf '\n```\n'
  } >> "$REPORT"
}

host_file_section() {
  label="$1"
  bin="$2"
  printf '\n### %s\n' "$label" >> "$REPORT"
  printf '\n- Expected source commit: `%s`\n' "$CEMU_COMMIT" >> "$REPORT"
  printf -- '- Binary: `%s`\n' "$bin" >> "$REPORT"
  if [ ! -e "$bin" ]; then
    printf -- '- Status: missing\n' >> "$REPORT"
    return 0
  fi
  [ -x "$bin" ] && printf -- '- Executable: yes\n' >> "$REPORT" || printf -- '- Executable: no\n' >> "$REPORT"
  append_cmd "$label --version" "$bin" --version
  host_cmd file && append_cmd "$label file" file "$bin" || printf '\n#### %s file\n\n```text\nmissing: file\n```\n' "$label" >> "$REPORT"
  host_cmd readelf && append_cmd "$label ELF header" readelf -h "$bin" || printf '\n#### %s ELF header\n\n```text\nmissing: readelf\n```\n' "$label" >> "$REPORT"
  host_cmd readelf && append_cmd "$label dynamic NEEDED" sh -c "readelf -d '$bin' | grep -E 'NEEDED|RUNPATH|RPATH|FLAGS' || true" || true
  host_cmd ldd && append_cmd "$label ldd" ldd "$bin" || printf '\n#### %s ldd\n\n```text\nmissing: ldd\n```\n' "$label" >> "$REPORT"
  host_cmd strings && append_cmd "$label selected strings" sh -c "strings '$bin' | grep -Ei 'cemu|sdl|vulkan|wayland|wx|gcc|clang|glibc|openssl|cubeb' | head -200" || true
}

guest_file_section() {
  label="$1"
  bin="$2"
  printf '\n### %s\n' "$label" >> "$REPORT"
  printf '\n- Expected source commit: `%s`\n' "$CEMU_COMMIT" >> "$REPORT"
  printf -- '- Binary: `%s`\n' "$bin" >> "$REPORT"
  append_guest_cmd "$label existence" "if [ -e '$bin' ]; then ls -l '$bin'; [ -x '$bin' ] && echo executable=yes || echo executable=no; else echo missing; fi"
  append_guest_cmd "$label --version" "if [ -x '$bin' ]; then '$bin' --version; else echo missing-or-not-executable; fi"
  append_guest_cmd "$label wrapper head" "if [ -f '$bin' ]; then first=\$(dd if='$bin' bs=2 count=1 2>/dev/null || true); if [ \"\$first\" = '#!' ]; then sed -n '1,80p' '$bin' 2>/dev/null || true; else echo 'binary-or-non-script wrapper; head skipped'; fi; fi"
  append_guest_cmd "$label package entry point" "out=\$(dirname \$(dirname '$bin')); for f in \"\$out/bin/cemu\" \"\$out/bin/Cemu\"; do if [ -e \"\$f\" ]; then ls -l \"\$f\"; first=\$(dd if=\"\$f\" bs=2 count=1 2>/dev/null || true); if [ \"\$first\" = '#!' ]; then echo --- \"\$f\"; sed -n '1,80p' \"\$f\"; fi; else echo missing: \"\$f\"; fi; done"
  wrapped="$(dirname "$bin")/.Cemu-wrapped"
  append_guest_cmd "$label wrapped binary" "if [ -e '$wrapped' ]; then ls -l '$wrapped'; else echo missing: '$wrapped'; fi"
  append_guest_cmd "$label file" "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin; if command -v file >/dev/null 2>&1 && [ -e '$bin' ]; then file '$bin'; elif command -v file >/dev/null 2>&1 && [ -e '$wrapped' ]; then file '$wrapped'; else echo 'missing file tool or binary'; fi"
  append_guest_cmd "$label readelf" "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin; target='$bin'; [ -e '$wrapped' ] && target='$wrapped'; if command -v readelf >/dev/null 2>&1 && [ -e \"\$target\" ]; then readelf -h \"\$target\"; else echo 'missing readelf or binary'; fi"
  append_guest_cmd "$label dynamic NEEDED" "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin; target='$bin'; [ -e '$wrapped' ] && target='$wrapped'; if command -v readelf >/dev/null 2>&1 && [ -e \"\$target\" ]; then readelf -d \"\$target\" | grep -E 'NEEDED|RUNPATH|RPATH|FLAGS' || true; else echo 'missing readelf or binary'; fi"
  append_guest_cmd "$label ldd" "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin; target='$bin'; [ -e '$wrapped' ] && target='$wrapped'; if command -v ldd >/dev/null 2>&1 && [ -e \"\$target\" ]; then ldd \"\$target\"; else echo 'missing ldd or binary'; fi"
  append_guest_cmd "$label runtime data" "out=\$(dirname \$(dirname '$bin')); for d in \"\$out/share/Cemu/gameProfiles/default\" \"\$out/share/Cemu/resources\"; do if [ -d \"\$d\" ]; then echo present-dir: \"\$d\"; find \"\$d\" -maxdepth 2 -type f | head -20; else echo missing-dir: \"\$d\"; fi; done; for f in \"\$out/share/Cemu/resources/sharedFonts/CafeCn.ttf\" \"\$out/share/Cemu/config/SM8550/settings.xml\"; do if [ -f \"\$f\" ]; then ls -l \"\$f\"; else echo missing: \"\$f\"; fi; done"
  append_guest_cmd "$label build evidence" "out=\$(dirname \$(dirname '$bin')); evidence=\"\$out/nix-support/rocknix-cemu-build\"; if [ -d \"\$evidence\" ]; then find \"\$evidence\" -maxdepth 1 -type f -printf '%f\\n' 2>/dev/null | sort; for f in manifest.txt compiler-version.txt link-lines.txt build-env.txt cubeb-evidence.txt readelf-header.txt readelf-dynamic.txt; do [ -f \"\$evidence/\$f\" ] && { echo --- \"\$f\"; sed -n '1,160p' \"\$evidence/\$f\"; }; done; if [ -f \"\$evidence/CMakeCache.txt\" ]; then echo --- CMakeCache-selected; grep -E 'ENABLE_|CMAKE_(CXX|C|EXE|BUILD|INTERPROCEDURAL)|cubeb|SDL|Vulkan|glslang|wxWidgets|GTK|OPENSSL|ZArchive|fmt|Boost' \"\$evidence/CMakeCache.txt\" | head -240 || true; fi; else echo 'no rocknix-cemu-build evidence directory'; fi"
  append_guest_cmd "$label nix references" "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin; target='$bin'; [ -e '$wrapped' ] && target='$wrapped'; if command -v nix-store >/dev/null 2>&1 && [ -e \"\$target\" ]; then nix-store -q --references \"\$target\" 2>/dev/null | sort; else echo 'missing nix-store or binary'; fi"
}

log "writing fingerprint report to $REPORT"
cat > "$REPORT" <<EOF
# Cemu build/runtime fingerprint

- Timestamp: $(date -Iseconds)
- Expected upstream commit: $CEMU_COMMIT
- Host Cemu: $HOST_CEMU
- Guest Cemu: $GUEST_CEMU
- Candidate Cemu: ${CANDIDATE_CEMU:-not provided}

## Known comparison points

| Surface | ROCKNIX host Cemu | Current guest Nix Cemu | Why it matters |
|---|---|---|---|
| Source commit | $CEMU_COMMIT | $CEMU_COMMIT | Source parity alone does not imply build/runtime parity. |
| Build system | ROCKNIX package.mk/toolchain | nixpkgs derivation + overrides | CMake flags, hardening, wrappers, and libraries can differ. |
| SDL layer | ROCKNIX SDL2 package | nixpkgs SDL2/sdl2-compat stack unless candidate changes it | SDL/windowing path can affect frame pacing and crashes. |
| Vulkan loader | ROCKNIX loader | Nix loader | Mixed loaders are known-bad; coherent per-build stacks are required. |
| Mesa/Turnip | ROCKNIX Mesa on host | Nix Mesa by default in guest | Mesa-only swaps did not explain the live gameplay gap, but must be recorded. |
| Runtime cache | host /storage conventions | guest XDG/cache conventions under /storage | Cache path and shader behavior can affect loading and gameplay stutter. |
| Cubeb linkage | bundled Cubeb expected | external \`libcubeb.so.0\` is a parity suspect | Current slow candidates reported \`Cubeb: not supported\`; dynamic Cubeb linkage must be surfaced. |
| ELF type | host binary fingerprints as \`EXEC\` | Nix wrapped binary previously fingerprinted as \`DYN\` | Non-PIE vs PIE may affect Cemu AArch64 backend/runtime behavior and must be measured. |

EOF

printf '\n## Host environment\n' >> "$REPORT"
append_cmd "host os-release" sh -c 'cat /etc/os-release 2>/dev/null || true'
append_cmd "host tool versions" sh -c 'for c in cemu vulkaninfo glxinfo strings readelf file ldd; do printf "%s: " "$c"; command -v "$c" || echo missing; done'
append_cmd "host Vulkan ICDs" sh -c 'ls -l /usr/share/vulkan/icd.d 2>/dev/null || true; for f in /usr/share/vulkan/icd.d/*.json; do [ -f "$f" ] && { echo "--- $f"; cat "$f"; }; done'
host_file_section "ROCKNIX host Cemu" "$HOST_CEMU"

printf '\n## Guest environment\n' >> "$REPORT"
if guest_pid >/dev/null 2>&1; then
  append_guest_cmd "guest os-release" 'cat /etc/os-release 2>/dev/null || true'
  append_guest_cmd "guest tool versions" 'PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin; for c in cemu Cemu vulkaninfo strings readelf file ldd nix-store; do printf "%s: " "$c"; command -v "$c" || echo missing; done'
  append_guest_cmd "guest Vulkan ICDs" 'for d in /run/opengl-driver/share/vulkan/icd.d /usr/share/vulkan/icd.d /nix/var/nix/profiles/per-user/root/profile/share/vulkan/icd.d; do [ -d "$d" ] || continue; echo "== $d =="; ls -l "$d"; for f in "$d"/*.json; do [ -f "$f" ] && { echo "--- $f"; cat "$f"; }; done; done'
  guest_file_section "Current guest Nix Cemu" "$GUEST_CEMU"
  if [ -n "$CANDIDATE_CEMU" ]; then
    guest_file_section "Candidate guest Cemu" "$CANDIDATE_CEMU"
  fi
else
  printf '\nGuest service is not running; guest sections skipped.\n' >> "$REPORT"
fi

printf '\n## Build source references\n' >> "$REPORT"
printf '\n- Host package: `projects/ROCKNIX/packages/emulators/standalone/cemu-sa/package.mk`\n' >> "$REPORT"
printf -- '- Guest package repo: `github:simonwjackson/nix-sm8550`\n' >> "$REPORT"
printf -- '- Guest package manifest: `packages/cemu/manifest.nix`\n' >> "$REPORT"
printf -- '- Guest package derivation: `packages/cemu/package.nix`\n' >> "$REPORT"

log "fingerprint done: $RUN_DIR"
printf '%s\n' "$RUN_DIR"
