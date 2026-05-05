# Layer 7 app experiment contract

Layer 7 validates manually launched Nix-managed apps and UI dependencies on
ROCKNIX without changing the base OS, default UI startup, or package ownership
model.

Layer 7 is not an app catalog and does not replace ROCKNIX services. It is a
narrow compatibility layer for proving that one useful app can be supplied by
Nix, exposed through a reversible storage-local launcher, launched under Sway,
and removed cleanly.

## Responsibilities

Layer 7 may:

- depend on packages installed through standard `nix profile` commands
- provide a launcher under `/storage/bin/<name>` through Layer 6 activation
- provide an app-specific profile snippet under `/storage/.config/profile.d/<name>` through Layer 6 activation
- create app experiment state only under explicit Layer 7 storage roots
- report readiness through `nixctl status` and `nix-doctor`
- document app-specific Wayland, GPU, audio, input, fullscreen, and reboot findings

Layer 7 must not:

- install or remove Nix packages itself
- replace EmulationStation, `essway`, Sway startup, or ROCKNIX default UI startup
- add autostart or systemd integration
- mutate `/usr`, `/flash`, `/boot`, kernel modules, firmware, or ROCKNIX services
- manage ROMs, saves, Steam/FEX state, existing browser profiles, or broad dotfiles
- treat app-specific graphical failures as lower-layer Nix failures without evidence

## Package and launcher split

Package install remains Layer 5 / standard Nix:

```sh
nix profile install nixpkgs#<app>
```

Launcher activation remains Layer 6:

```sh
nixctl user-env preflight /path/to/layer7-bundle
nixctl user-env activate /path/to/layer7-bundle
```

Layer 7 status and doctor checks can report whether the expected app binary and
launcher are ready, but they should not become another package manager.

## Allowed persistent surfaces

Layer 7 uses only the Layer 6 first-iteration surfaces:

```text
/storage/bin/<launcher>
/storage/.config/profile.d/<snippet>
```

The Layer 6 manifest remains the activation contract:

```text
surface|name|source|mode
```

## App state roots

The first Layer 7 iteration may create app experiment state only under one of
these roots:

```text
/storage/.local/share/nix-apps/layer7/<app>
/storage/.config/nix-apps/layer7/<app>
/storage/.cache/nix-apps/layer7/<app>
```

Tests may override `HOME` and use the same relative roots below that home.
Browser-like launchers should set `CHROME_CONFIG_HOME`, `XDG_CONFIG_HOME`, and
`XDG_CACHE_HOME` to Layer 7 experiment roots before launching, because some
helpers such as Crashpad can otherwise write to default browser config paths
even when `--user-data-dir` is set. Layer 7 should refuse or warn on paths that
point at existing browser, Steam, FEX, ROM, save, or system locations.

## Nix-backed binary proof

A Layer 7 app is ready only when the selected binary resolves through the Nix
profile or store, for example:

```text
/storage/.nix-profile/bin/<app>
/nix/store/.../<app>
```

A command found in `/usr`, `/bin`, or an unrelated `/storage/bin` path is not a
valid Layer 7 app dependency, even if it has the expected name.

## Graphical validation

Default static and runtime tests must not launch graphical apps. Hardware
validation is opt-in and should record:

- selected Nix package and resolved binary path
- launcher flags required by the ROCKNIX/root runtime, such as Chromium's `--no-sandbox`
- launcher bundle path and Layer 6 generation
- app state path
- Sway launch context
- visible window result
- input/touch/controller behavior when relevant
- audio behavior when relevant
- fullscreen/window behavior
- exit behavior and UI recovery
- reboot relaunch result
- cleanup result

## Stopping rules

Stop Layer 7 or switch candidate apps if:

- the app requires mutating forbidden base OS or user-data surfaces
- the launcher cannot prove a Nix-backed binary origin
- graphical launch strands SSH, Sway, EmulationStation, Steam/FEX, or recovery
- app state grows without a clear cleanup path
- Layer 6 activation cannot deactivate the launcher cleanly
- app-specific compatibility failures dominate and no useful candidate remains
