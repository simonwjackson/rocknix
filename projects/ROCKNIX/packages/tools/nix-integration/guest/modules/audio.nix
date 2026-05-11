# Layer 14 audio module: guest-owned PipeWire + WirePlumber + AYN Odin2 UCM.
#
# The host passes kernel devices and staged udev metadata into the guest, but
# normal audio policy lives here. Do not bind host /usr/share/alsa or host
# PipeWire/PulseAudio sockets into the guest; that would make ROCKNIX the audio
# policy owner again.
{ pkgs, ... }:

let
  aynOdin2Ucm = pkgs.callPackage ../packages/audio/ayn-odin2-ucm { };
  ucmPath = "${aynOdin2Ucm}/share/alsa/ucm2";
  audioServiceEnvironment = {
    XDG_RUNTIME_DIR = "/run/user/0";
    DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/0/bus";
    PIPEWIRE_RUNTIME_DIR = "/run/user/0";
    ALSA_CONFIG_UCM2 = ucmPath;
    PULSE_SERVER = "unix:/run/user/0/pulse/native";
  };
in
{
  # Keep NixOS PipeWire configuration available, but do not rely on its user
  # units: the Layer 14 kiosk bypasses PAM/logind user sessions. The root-owned
  # rocknix-* services below run the graph in the same /run/user/0 runtime as
  # Sway and launched apps.
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

  systemd.services.rocknix-pipewire = {
    description = "ROCKNIX Layer 14 root PipeWire service";
    wantedBy = [ "multi-user.target" ];
    after = [ "rocknix-session-dbus.service" ];
    serviceConfig = {
      Type = "simple";
      User = "root";
      ExecStartPre = "${pkgs.coreutils}/bin/install -d -m 0700 -o 0 -g 0 /run/user/0";
      ExecStart = "${pkgs.pipewire}/bin/pipewire";
      Restart = "on-failure";
      RestartSec = 3;
    };
    environment = audioServiceEnvironment;
  };

  systemd.services.rocknix-pipewire-pulse = {
    description = "ROCKNIX Layer 14 root PipeWire PulseAudio service";
    wantedBy = [ "multi-user.target" ];
    after = [ "rocknix-pipewire.service" "rocknix-session-dbus.service" ];
    requires = [ "rocknix-pipewire.service" ];
    serviceConfig = {
      Type = "simple";
      User = "root";
      ExecStartPre = "${pkgs.coreutils}/bin/install -d -m 0700 -o 0 -g 0 /run/user/0";
      ExecStart = "${pkgs.pipewire}/bin/pipewire-pulse";
      Restart = "on-failure";
      RestartSec = 3;
    };
    environment = audioServiceEnvironment;
  };

  systemd.services.rocknix-wireplumber = {
    description = "ROCKNIX Layer 14 root WirePlumber service";
    wantedBy = [ "multi-user.target" ];
    after = [ "rocknix-pipewire.service" "rocknix-session-dbus.service" ];
    requires = [ "rocknix-pipewire.service" ];
    serviceConfig = {
      Type = "simple";
      User = "root";
      ExecStartPre = "${pkgs.coreutils}/bin/install -d -m 0700 -o 0 -g 0 /run/user/0";
      ExecStart = "${pkgs.wireplumber}/bin/wireplumber";
      Restart = "on-failure";
      RestartSec = 3;
    };
    environment = audioServiceEnvironment;
  };

  environment.variables = audioServiceEnvironment;

  environment.systemPackages = with pkgs; [
    alsa-utils
    pipewire
    wireplumber
    pulseaudio
    aynOdin2Ucm
    bluez
    bluez-tools
  ];
}
