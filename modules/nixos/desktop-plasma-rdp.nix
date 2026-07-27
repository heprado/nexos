{ pkgs, ... }:
{
  # KDE Plasma over RDP: leonardo and martin (remote, via Tailscale) and
  # also henrique (via the LAN, or Tailscale if he ever joins it). Any user
  # with a password can authenticate via xrdp's PAM stack — there's no
  # per-user allowlist here, this just controls network reachability.
  #
  # Note: this always lands in an X11 Plasma session (startplasma-x11), not
  # Hyprland — xrdp doesn't support Wayland compositors. Henrique's Hyprland
  # session stays local-console-only via SDDM.
  services.desktopManager.plasma6.enable = true;

  services.xrdp = {
    enable = true;
    openFirewall = false;
    defaultWindowManager = "${pkgs.kdePackages.plasma-workspace}/bin/startplasma-x11";
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 3389 ];

  # Also reachable from the LAN. Assumes caixa sits behind a home router/NAT
  # and isn't directly WAN-exposed — if that's not true, scope this to the
  # actual LAN interface name instead (check with `ip a` on caixa) via
  # networking.firewall.interfaces.<name>.allowedTCPPorts.
  networking.firewall.allowedTCPPorts = [ 3389 ];
}
