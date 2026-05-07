# Default ROCKNIX Layer 10b/12 guest profile.
#
# Kept as the stable import target for existing flake consumers while the
# implementation is split into reusable NixOS modules under guest/modules/ and
# guest/profiles/.
{
  imports = [ ./profiles/ssh.nix ];
}
