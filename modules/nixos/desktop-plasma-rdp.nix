{ config, pkgs, ... }:
{
  # KDE Plasma over RDP: leonardo and martin only, reached via Tailscale.
  # henrique is explicitly denied (see the PAM rule below) — he uses
  # wayvnc + Hyprland instead (see wayvnc-hyprland.nix).
  #
  # Note: this always lands in an X11 Plasma session (startplasma-x11), not
  # Hyprland — xrdp doesn't support Wayland compositors.
  services.desktopManager.plasma6.enable = true;

  services.xrdp = {
    enable = true;
    openFirewall = false;
    defaultWindowManager = "${pkgs.kdePackages.plasma-workspace}/bin/startplasma-x11";
  };

  # Deny henrique specifically at the PAM layer, before password checking
  # even happens. leonardo and martin fall through to normal pam_unix auth.
  security.pam.services.xrdp-sesman.rules.auth.deny-henrique = {
    order = config.security.pam.services.xrdp-sesman.rules.auth.unix.order - 10;
    control = "requisite";
    modulePath = "${config.security.pam.package}/lib/security/pam_succeed_if.so";
    args = [ "user" "!=" "henrique" ];
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 3389 ];
}
