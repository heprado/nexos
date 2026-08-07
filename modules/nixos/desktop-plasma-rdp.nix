{ config, pkgs, ... }:
{
  # KDE Plasma over RDP: leonardo and martin only, reached via the
  # Cloudflare Tunnel (kde.heprado.com.br -- see cloudflared.nix), not a
  # directly-opened port. henrique is explicitly denied (see the PAM rule
  # below) — he uses wayvnc + Hyprland instead (see wayvnc-hyprland.nix).
  #
  # Note: this always lands in an X11 Plasma session (startplasma-x11), not
  # Hyprland — xrdp doesn't support Wayland compositors.
  services.desktopManager.plasma6.enable = true;

  # These GUI apps are optional extras plasma6 installs by default (see
  # nixpkgs' plasma6.nix desktop-manager module) -- system-wide, so they'd
  # otherwise clutter henrique's Hyprland launcher/PATH even though he
  # never runs Plasma. kwin-x11 is deliberately NOT excluded here: xrdp's
  # startplasma-x11 (above) needs it to render leonardo/martin's session.
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    konsole
    kate
    ktexteditor
    khelpcenter
    dolphin
    baloo-widgets
    dolphin-plugins
    gwenview
    okular
    ark
    elisa
    spectacle
    ffmpegthumbs
    krdp
    plasma-keyboard
    qtvirtualkeyboard
    aurorae
    plasma-browser-integration
    plasma-workspace-wallpapers
  ];

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

  # No inbound firewall rule needed for 3389 -- cloudflared (see
  # cloudflared.nix) connects to it over loopback, which bypasses nixos-fw
  # entirely. Not opened on the LAN/WAN interface at all anymore.
}
