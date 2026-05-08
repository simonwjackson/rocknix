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
# Strategy A (per E4) keeps host InputPlumber, guest reads virtual
# event7/event8; the workaround is no longer required, but we keep it
# disabled by setting it explicitly to "0" so a future regression
# surfaces in soak.
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
    WLR_LIBINPUT_NO_DEVICES = "0";
  };
}
