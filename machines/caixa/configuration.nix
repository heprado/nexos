{ lib, inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/docker-rootless.nix
    ../../modules/nixos/tailscale.nix
    ../../modules/nixos/ssh.nix
    ../../modules/nixos/desktop-hyprland.nix
    ../../modules/nixos/desktop-plasma-rdp.nix
    ../../modules/nixos/wayvnc-hyprland.nix
    ../../modules/nixos/lan-isolation.nix
    ../../users/henrique
    ../../users/leonardo
    ../../users/martin
  ];

  # Noctalia isn't in the official nixpkgs cache; without this, its
  # Quickshell/Qt dependencies get compiled from source on every rebuild.
  nix.settings = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  };

  networking.hostName = "caixa";
  programs.zsh.enable = true;
  hardware.graphics.enable = true;

  i18n.defaultLocale = "pt_BR.UTF-8";

  # Backend dconf needs to actually apply GTK theme settings (see
  # modules/home/hyprland.nix's dconf.settings for henrique's GTK theme).
  programs.dconf.enable = true;

  nixpkgs.overlays = [ inputs.helium-flake.overlays.default ];

  # Lives here (not hardware-configuration.nix) since that file gets
  # wholesale-replaced by `nixos-generate-config` output during install,
  # which would silently drop bootloader config if it lived there.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # claude-code's license is marked "unfree" in nixpkgs; allow just that
  # package rather than unfree packages in general.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "claude-code" ];

  home-manager.users.henrique = import ../../users/henrique/home.nix;
  home-manager.users.leonardo = import ../../users/leonardo/home.nix;
  home-manager.users.martin = import ../../users/martin/home.nix;

  sops.defaultSopsFile = ../../secrets/caixa.yaml;
  # Generate on caixa with `age-keygen`, then record the public key in
  # .sops.yaml at the repo root as caixa's recipient. See secrets/README.md.
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";

  # Bump to whatever release you actually install; do not change on upgrades.
  system.stateVersion = "24.05";
}
