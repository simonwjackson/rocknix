# Layer 14 display module: sway-on-DRM with Mesa freedreno/turnip.
#
# Tier B confirmed:
#   - nixpkgs Mesa with freedreno provides Vulkan turnip on Adreno 740
#   - sway took DRM master on /dev/dri/card0 (msm)
#   - DSI-1 (1080x1240) and DSI-2 (1920x1080) lit
#   - GLES2 + UBWC working from guest closure
#
# WLR_LIBINPUT_NO_DEVICES=1 was needed under the broad-bind unit because
# host libinput was fighting guest sway over input devices. Layer 14
# main-space rediscovered the same need on Thor 2026-05-08 -- under
# nspawn with --bind=/dev/input but without udev/sysfs symlink support,
# libinput sees zero devices and aborts wlroots backend init with:
#   [ERROR] backend/libinput/backend.c:111 libinput initialization failed
# Setting WLR_LIBINPUT_NO_DEVICES=1 makes wlroots skip libinput's device
# probe; sway then reaches the DRM backend cleanly.
{ pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = false;
  };

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  environment.systemPackages = with pkgs; [
    foot
    swaybg
    swaylock
    wl-clipboard
    grim
    slurp
    mesa-demos
    vulkan-tools
  ];

  environment.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS = "1";
    WLR_LIBINPUT_NO_DEVICES = "1";
  };
}
