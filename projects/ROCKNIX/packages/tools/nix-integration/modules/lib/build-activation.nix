# Helper kept as a stable import point for future module tooling.
# The first Layer 13 implementation emits activation manifests directly from
# lib/eval-rocknix.nix so shell-side nixctl can consume them without JSON tools.
{ evalResult }:
{
  manifest = evalResult.activationManifest;
  lines = evalResult.activationLines;
}
