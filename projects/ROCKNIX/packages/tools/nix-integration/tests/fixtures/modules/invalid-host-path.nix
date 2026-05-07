{
  # This is intentionally invalid at the shell activation layer: target names
  # must be safe storage-local basenames.
  rocknix.files.bin."../usr-bin-bad".source = builtins.toFile "bad" "bad";
}
