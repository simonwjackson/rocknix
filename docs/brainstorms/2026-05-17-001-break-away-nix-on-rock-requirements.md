---
date: 2026-05-17
topic: break-away-nix-on-rock
---

# Break Away Nix-on-ROCK

## Summary

Define Nix-on-ROCK as the SM8550 product boundary, with ROCKNIX treated as an upstream substrate source rather than the identity and validation authority. The first breakaway proof is an independent SM8550 build lane and release posture that can continue without perpetual rebasing.

---

## Problem Frame

The current work lives inside a ROCKNIX fork and still inherits upstream assumptions: rebasing is the normal integration model, CI compares against upstream distribution state, artifact names and docs primarily speak ROCKNIX, and many product boundaries are implicit. That works while the delta is small, but the SM8550 thin-host plus Nix guest architecture is becoming a product direction of its own.

The pain is not only merge conflict volume. The deeper risk is that product decisions remain framed as downstream patches, so every new change has to answer two incompatible questions at once: “does this fit upstream ROCKNIX?” and “does this advance Nix-on-ROCK?” Breaking away needs to make the second question primary while preserving enough upstream compatibility to keep boot, packaging, and device support viable.

---

## Actors

- A1. Product maintainer: decides product identity, scope, release posture, and acceptable upstream dependency level.
- A2. Build/release operator: needs repeatable SM8550 artifacts without depending on frequent upstream rebases.
- A3. Device operator: installs and recovers Nix-on-ROCK on supported SM8550 devices.
- A4. Future planning/implementation agent: needs a clear boundary so implementation does not invent product shape.
- A5. ROCKNIX upstream: remains a source of substrate code and fixes, but is no longer the product authority for Nix-on-ROCK decisions.

---

## Key Flows

- F1. Boundary definition
  - **Trigger:** The fork reaches a point where rebasing against ROCKNIX is no longer sustainable.
  - **Actors:** A1, A4
  - **Steps:** Name the product boundary, decide what Nix-on-ROCK owns, decide what remains borrowed from ROCKNIX, and record what upstream alignment is valuable but non-authoritative.
  - **Outcome:** Planning can distinguish product work from upstream-sync work.
  - **Covered by:** R1, R2, R3, R8

- F2. Independent SM8550 build proof
  - **Trigger:** A maintainer wants confidence that the product can ship without rebase-first workflow.
  - **Actors:** A1, A2, A4
  - **Steps:** Run an SM8550 build path whose validation treats Nix-on-ROCK branch state as authoritative, preserves useful substrate checks, and emits artifacts that are understandable as Nix-on-ROCK outputs.
  - **Outcome:** The product has a repeatable build proof that is not merely “ROCKNIX fork still rebases.”
  - **Covered by:** R4, R5, R6, R9

- F3. Upstream intake after breakaway
  - **Trigger:** ROCKNIX upstream changes in ways that may matter to boot, packaging, kernel/device support, or security.
  - **Actors:** A1, A2, A5
  - **Steps:** Review upstream changes intentionally, classify them as necessary substrate fixes, optional improvements, or irrelevant product changes, then import only selected changes.
  - **Outcome:** Upstream remains useful without controlling Nix-on-ROCK release cadence.
  - **Covered by:** R3, R7, R10

---

## Requirements

**Product boundary**
- R1. Nix-on-ROCK must be defined as the product that owns the SM8550 thin host, Nix guest lifecycle, recovery posture, storage contract, seed/update flow, and operator guidance.
- R2. ROCKNIX must be described as an upstream substrate source for inherited boot/build/package/device machinery, not as the product identity or final validation authority for Nix-on-ROCK.
- R3. The breakaway model must preserve intentional upstream intake: upstream fixes can still be imported, but rebasing must stop being the default measure of health.

**First proof**
- R4. The first technical milestone must be an SM8550-only build lane that validates Nix-on-ROCK on its own branch terms.
- R5. The first proof must remove or invert checks that assume upstream ROCKNIX is the source of truth for the product branch, while retaining checks that catch real local quality problems.
- R6. The first proof must produce artifacts and logs that a maintainer can understand as Nix-on-ROCK outputs, even if some internal build variables still use inherited ROCKNIX names during the transition.

**Release and maintenance posture**
- R7. The product must have a documented upstream intake policy that distinguishes critical substrate fixes from optional upstream churn.
- R8. The product must have a durable requirements/strategy artifact before large repo extraction work starts, so extraction follows product decisions rather than file-copy momentum.
- R9. The breakaway path must prioritize the smallest independent shipping loop over broad renaming or repo surgery.
- R10. The product must keep recovery and install safety as first-class acceptance criteria during breakaway; independence is not successful if it makes device recovery less reliable.

---

## Acceptance Examples

- AE1. **Covers R1, R2, R8.** Given a future agent is asked whether a change belongs to Nix-on-ROCK or upstream ROCKNIX, when it reads the breakaway requirements, it can classify thin-host guest lifecycle and storage-contract work as Nix-on-ROCK product work without inventing the boundary.
- AE2. **Covers R4, R5, R6.** Given the branch has diverged from upstream, when an SM8550 build runs, it can pass or fail based on Nix-on-ROCK quality gates rather than failing solely because the branch is not cleanly comparable to upstream distribution state.
- AE3. **Covers R3, R7.** Given upstream ROCKNIX ships a relevant substrate fix, when the maintainer evaluates it, the decision is “import this fix intentionally” rather than “rebase everything and resolve whatever breaks.”
- AE4. **Covers R9, R10.** Given there is pressure to rename everything immediately, when planning starts, the first slice still protects build/recovery/install confidence before broad branding cleanup.

---

## Success Criteria

- The next planning step can identify one concrete first implementation slice without debating whether Nix-on-ROCK is a fork, product, or patch stack.
- A maintainer can explain what Nix-on-ROCK owns in one paragraph.
- CI/build validation no longer encodes upstream ROCKNIX branch comparability as the central proof of product health for the Nix-on-ROCK branch.
- Upstream intake becomes deliberate and reviewable rather than an endless rebase obligation.
- SM8550 install and recovery confidence is preserved through the first breakaway slice.

---

## Scope Boundaries

### Deferred for later

- Full repository extraction into a new standalone repo.
- Complete renaming of every project variable, artifact, service, package, or historical reference.
- Multi-device expansion beyond the currently proven SM8550 direction.
- Public release branding, website, distribution channel, or end-user marketing.
- Automated upstream cherry-pick tooling beyond a documented intake policy.

### Outside this product's identity

- Becoming a general ROCKNIX replacement for all supported devices.
- Preserving upstream compatibility at the cost of Nix-on-ROCK product direction.
- Treating the guest as a temporary experiment inside ROCKNIX rather than the main product architecture.
- Building a generic Linux distro unrelated to the ROCKNIX-derived handheld substrate.

---

## Key Decisions

- Product-first boundary before repo extraction: Moving files first would create a new repository with the same ambiguous identity problem.
- First proof is build/release independence, not branding cleanup: It directly attacks the “cannot rebase forever” pain while minimizing carrying cost.
- Upstream becomes supplier, not authority: ROCKNIX still provides valuable substrate work, but Nix-on-ROCK needs its own validation posture.
- Keep SM8550 narrow at first: The current validated work and risk surface are SM8550-specific; expanding device scope now would hide the core breakaway problem.

---

## Dependencies / Assumptions

- The current branch already contains enough SM8550-specific substrate work to justify a separate product boundary.
- ROCKNIX-derived build machinery remains useful in the near term.
- The existing Nix-on-ROCK storage contract work is the clearest first example of product-owned behavior.
- Some inherited names may remain during the first breakaway slice if changing them would increase risk without improving independence.
- The current GitHub Actions build has been triggered for the storage-contract branch and can inform confidence, but breakaway planning should not depend on that run succeeding before requirements are useful.

---

## Outstanding Questions

### Resolve Before Planning

None.

### Deferred to Planning

- [Affects R4, R5][Technical] Which existing CI checks should be retained as local quality gates, which should be removed, and which should become optional upstream-drift reports?
- [Affects R6][Technical] What minimal artifact naming or release-note change is enough to make outputs legible as Nix-on-ROCK without broad rename churn?
- [Affects R7][Needs research] What cadence and format should upstream intake use: periodic manual review, topic-based cherry-picks, or a tracked upstream-import branch?
- [Affects R10][Technical] What on-device smoke should gate the first independent build proof: host SSH, recovery flags, guest active, seed migration, or full clean-storage install?
