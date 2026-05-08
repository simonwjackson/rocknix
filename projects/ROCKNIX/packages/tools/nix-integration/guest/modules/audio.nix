# Layer 14 audio module: pipewire + wireplumber + bluez.
#
# Tier E5a/b confirmed:
#   - guest can grab /dev/snd/pcmC0D0p; SIGKILL releases cleanly
#   - host pipewire reclaims via socket activation after guest exit
#   - guest hciconfig flips hci0 UP/DOWN; host bluetooth.service
#     reclaims to UP RUNNING PSCAN
#
# bluez needs D-Bus to run its full daemon; we enable services.dbus
# explicitly. Without D-Bus, bluetoothd exits early (E5b finding).
{ pkgs, ... }:

{
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  services.dbus.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
    settings = {
      General = {
        FastConnectable = "true";
        JustWorksRepairing = "always";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    alsa-utils
    pulseaudio
    bluez
    bluez-tools
  ];
}
