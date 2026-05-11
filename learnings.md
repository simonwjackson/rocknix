## Institutional Learnings Search Results

### Search Context
- **Feature/Task**: Follow-up plan for ROCKNIX Layer 14 Cemu to reach host-like parity, then simplify/remove diagnostic complexity.
- **Keywords Used**: Cemu, Layer 14, layer-14, Nix, Nix store, closure import, systemd-nspawn, Vulkan, Mesa, Turnip/freedreno, graphics passthrough, host recovery, cleanup, simplification, diagnostics, lifecycle.
- **Files Scanned**: 19 total files under `docs/solutions/` (grep pre-filtered; 10 candidates examined).
- **Relevant Matches**: 9 files; top 5 distilled below.

### Critical Patterns
No `docs/solutions/patterns/critical-patterns.md` exists in this repo.

### Relevant Learnings

#### 1. ROCKNIX Layer 14 Cemu performance audit (2026-05-09)
- **File**: `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md`
- **Module**: ROCKNIX Layer 14 Cemu performance (inferred)
- **Problem Type**: performance_issue (inferred; no YAML frontmatter)
- **Relevance**: This is the directly applicable prior investigation for Cemu/BOTW guest-vs-host parity, Vulkan/Mesa experiments, and diagnostic harnesses.
- **Key Insight**: The guest display/GPU path was proven not to be the main limiter: host `vkcube`/`glmark2` and guest Nix demos through guest sway were within ~5–16%, and host ROCKNIX Cemu through guest sway hit ~45 FPS. The parity path should therefore replicate ROCKNIX `cemu-sa` as a coherent Nix derivation/launcher, not productize host Mesa shims, broad host binds, or host Vulkan loader preloads. The doc also records that 720p-45 under max power was the strongest headless result and that profile-power caused hitches.
- **Important Currency Note**: The doc’s last direct package-replica note says Thor was offline and `.#cemu-rocknix-package` was not live-tested. Your current context supersedes that: the direct Nix Cemu package plus Vulkan loader fix now reaches ~38–40 FPS. Keep the document’s diagnosis/replication checklist, but update the measured-results section after the next validation.

#### 2. ROCKNIX Layer 14 main-space: cold-boot autostart on AYN Thor
- **File**: `docs/solutions/best-practices/rocknix-layer14-main-space-cold-boot-autostart-2026-05-08.md`
- **Module**: ROCKNIX Layer 14 main-space / graphics passthrough (inferred)
- **Problem Type**: best_practice (inferred; no YAML frontmatter)
- **Relevance**: Defines the validated Layer 14 host/guest boundary, recovery toggle, nspawn invocation shape, DRM/TTY/libseat requirements, udev scrubbing, and guest sway bring-up assumptions that Cemu must preserve.
- **Key Insight**: Keep the host as the thin recovery/control plane and the guest as the graphical app plane. Critical pitfalls already found: bind `/dev/tty0` and `/dev/tty1` but not `/dev/console`; set unified cgroup hierarchy; scrub InputPlumber-hidden udev records before binding `/run/udev`; disable guest firewall/nftables because the host owns shared-netns trust; avoid PAM/logind/greetd paths inside nspawn; launch clients as systemd units when `swaymsg exec` is unreliable.

#### 3. ROCKNIX nix-portable remote copy can create profile/store visibility mismatches
- **File**: `docs/solutions/runtime-errors/rocknix-nix-remote-copy-profile-store-mismatch-2026-05-05.md`
- **Module**: ROCKNIX nix-integration
- **Problem Type**: runtime_error
- **Relevance**: Directly applies to importing Fuji-built Cemu closures into Thor/guest Nix stores and avoiding false-positive `nix copy` success.
- **Key Insight**: Do not route Layer 4+ store/profile operations through nix-portable or `ssh-ng` wrappers that may operate in a different namespace. Use real `/nix/var/nix/profiles/default/bin/nix` and `nix-store`, classic `ssh://...remote-program=...nix-store`, and verify with host-visible `ls /nix/store/...`, profile symlink resolution, and runtime fingerprinting.
- **Severity**: medium

#### 4. ROCKNIX Layer 9 systemd-nspawn guest proof
- **File**: `docs/solutions/developer-experience/nix-layer-9-nspawn-guest-proof-rocknix-2026-05-06.md`
- **Module**: ROCKNIX nix-integration
- **Problem Type**: developer_experience
- **Relevance**: Captures the recovery boundary philosophy that still applies to Layer 14: ROCKNIX owns boot, firmware, host recovery, and cleanup; nspawn guests must remain removable and non-authoritative.
- **Key Insight**: Guest experimentation should not widen host blast radius. Preserve `systemd-nspawn` in the ROCKNIX project override, use `--register=no` because `machined=false`, and keep host Layers 4/8 as recovery paths. Guest cleanup must not touch host `/nix`, profiles, or daemon state. This matters when removing diagnostic harnesses: delete Cemu/run artifacts and guest-only state, not recovery-plane mechanisms.
- **Severity**: medium

#### 5. ROCKNIX Layer 10 must not trust stale guest running metadata
- **File**: `docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md`
- **Module**: ROCKNIX nix-integration
- **Problem Type**: runtime_error
- **Relevance**: Applies to cleanup/simplification after performance work: avoid simplifying diagnostics into stale or misleading status markers.
- **Key Insight**: `running` is a live condition, not durable metadata. Status/cleanup/doctor paths must prove liveness from host-owned evidence such as active systemd units or `systemd-nspawn` processes referencing the guest root. Durable state files can record `failed`, `stopped`, or `configured`; they must not be the sole proof that Cemu/gamescope/guest services are active.
- **Severity**: medium

### Recommendations
- Treat `rocknix-layer14-cemu-performance-audit` as the primary checklist, but amend it with the newer 38–40 FPS direct-package result and the Vulkan loader fix so future work does not chase already-closed deltas.
- Keep the next parity run narrow: same BOTW profile, same guest sway path, same power mode, same host-control vs direct-Nix package session; compare logs for Cemu version/data paths/RPL-HLE timing/Vulkan ICD/loader before changing multiple variables.
- Do not productize diagnostic-only mixed runtime paths unless they are the only validated product path. Prior learning favors a coherent guest-native Nix Cemu package and launcher over host Mesa shims, broad host binds, or preloaded host Vulkan loaders.
- Preserve host recovery boundaries while simplifying: `/flash/rocknix.no-nspawn`, host SSH, Layer 4/8 recovery, and `rocknix-recovery-toggle` are safety mechanisms, not diagnostics to delete.
- Use real Nix store tools for closure import and verify materialization from normal filesystem access; avoid any nix-portable/namespace ambiguity.
- Adjacent docs worth checking during implementation: `stage-nspawn-rootfs-from-onboard-nix-closures-rocknix-2026-05-06.md` for closure-staging traps, `rocknix-sm8550-power-profiling-2026-05-04.md` for reversible CPU/GPU max-power/restore handling, `nix-layer-6-managed-user-environment-rocknix-2026-05-05.md` and `nix-layer-7-app-ui-experiments-rocknix-2026-05-05.md` for reversible launcher/app integration, and `fast-iter-and-local-rocknix-build-2026-05-08.md` for image-only iteration when changes stay in `nix-integration`/post-install surfaces.
