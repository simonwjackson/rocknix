# AYN Odin2 UCM

Guest-owned ALSA UCM2 policy for the SM8550 AYN Odin2 / Thor audio card.

The source policy is copied from ROCKNIX's SM8550 `alsa-ucm-conf` patches so the NixOS guest can own audio routing without binding the host `/usr/share/alsa` tree. The package layers the Odin2 files onto nixpkgs `alsa-ucm-conf` so shared Qualcomm codec includes remain available.
