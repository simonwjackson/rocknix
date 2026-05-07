{ pkgs, ... }:
{
  # This is intentionally invalid at the shell activation layer: only named
  # storage surfaces are supported, not absolute host paths.
  rocknix.files.bin."../usr-bin-bad".source = pkgs.writeText "bad" "bad";
}
