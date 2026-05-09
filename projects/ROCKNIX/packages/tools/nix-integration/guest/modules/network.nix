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

  # Firewall + nftables disabled inside the nspawn guest. systemd-nspawn
  # without --capability=CAP_NET_ADMIN/CAP_NET_RAW (and without the host
  # exposing nf_tables.ko caps cleanly) makes nftables.service abort with
  # "netlink: Error: cache initialization failed: Operation not permitted"
  # on every activation, leaving a permanently-failed unit.
  #
  # The trust boundary lives at the host (rocknix-graphical.target wires
  # the guest, the host enforces network policy). The guest doesn't need
  # its own firewall ruleset under the shared-netns Layer-14 model.
  #
  # Validated on Thor 2026-05-08: nftables.service failed every guest
  # boot under enable=true; with enable=false, no failed units (apart
  # from independently-known sshd.socket port-conflict).
  networking.firewall.enable = false;
  networking.nftables.enable = false;

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
