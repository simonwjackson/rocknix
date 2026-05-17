# Nix-on-ROCK Upstream Intake Policy

Nix-on-ROCK treats ROCKNIX as an upstream substrate supplier, not as the product authority. Upstream changes are reviewed intentionally and imported when they improve or protect the SM8550 Nix-on-ROCK product lane.

## When to review upstream

Run an upstream intake review:

- before marking a product-lane artifact `DeviceAccepted`;
- when ROCKNIX lands changes in boot, kernel, firmware, package infrastructure, update/image assembly, recovery, or SM8550-adjacent device support;
- when security, stability, or build failures suggest an upstream substrate fix may matter;
- periodically during active development, even if the outcome is “no relevant changes.”

Product-lane CI may include non-blocking drift context, but upstream drift does not fail a `BuildProof` by itself.

## Classification

Classify each reviewed upstream change as one of:

- **Critical substrate fix** — security, bootability, recovery, kernel/device support, image/update correctness, or build breakage that affects Nix-on-ROCK.
- **Optional substrate improvement** — useful but not urgent build/package/device improvement.
- **Conflicting product change** — upstream direction that would weaken Nix-on-ROCK product-owned behavior or recovery guarantees.
- **Irrelevant upstream product churn** — changes for devices, UI, emulators, or workflows outside the current SM8550 Nix-on-ROCK lane.

## Intake record

Each intake review should record:

- upstream commit, tag, or range reviewed;
- classification for relevant changes;
- touched subsystem;
- impact on Nix-on-ROCK product invariants;
- import decision: import now, defer, reject, or no relevant changes;
- validation evidence used for the decision;
- follow-up owner or plan when applicable.

A review that finds nothing relevant should still record the upstream range and `no relevant changes` outcome. This makes “not rebasing” an explicit decision rather than an omission.

## Product invariants to check before import

Any upstream import that touches these areas needs explicit review against the Nix-on-ROCK product boundary:

- `/storage/nix-on-rock` layout or migration behavior;
- update tar `target/seed/` payload handling;
- SM8550 `SYSTEM` budget and thin-host package set;
- `rocknix-main-space.target` and guest startup ordering;
- `/flash/rocknix.no-nspawn`, `rocknix.safe=1`, and `/flash/rocknix.reseed-guest` recovery behavior;
- host SSH/network recovery;
- guest seed compatible-string checks;
- image/update artifact safety gates.

## Import posture

Prefer narrow imports over broad rebases. A broad rebase is acceptable only when the maintainer deliberately chooses it as an upstream-intake action and records the validation evidence that makes it safe for Nix-on-ROCK.
