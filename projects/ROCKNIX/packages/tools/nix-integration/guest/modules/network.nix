# Layer 14 network module: NetworkManager owns wlan0 from guest namespace.
#
# Tier C confirmed:
#   - guest and host already share root netns (Layer 14 wants this)
#   - veth+NAT pattern is reserved for side-by-side experimental guests,
#     not main-space
#   - kernel lacks ip_tables.ko; firewall MUST be nftables
#
# Tier E1/E5 surfaced repeated DNS clobber under load when host
# resolvconf wrote to a host-bound /etc/resolv.conf. Layer 14 unit
# does not bind /etc/resolv.conf; this module also disables resolvconf
# inside the guest and lets NetworkManager manage DNS directly so
# nothing else can clobber it.
#
# Tailscale lives at the *host* layer per ROCKNIX's existing
# 099-networkservices autostart contract (and U1's tailscale.up=1
# default). The host owns the WireGuard interface; guest sees it via
# the shared netns. No tailscaled in guest.
{ pkgs, ... }:

{
  networking.networkmanager = {
    enable = true;
    wifi.backend = "wpa_supplicant";
    dns = "default";
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 2222 ];
  };
  networking.nftables.enable = true;

  networking.resolvconf.enable = false;

  services.resolved.enable = false;

  environment.systemPackages = with pkgs; [
    iw
    nftables
    iproute2
    networkmanager
    wpa_supplicant
  ];
}
