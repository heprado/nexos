{ lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/docker-rootless.nix
    ../../modules/nixos/tailscale.nix
    ../../modules/nixos/ssh.nix
    ../../modules/nixos/desktop-hyprland.nix
    ../../modules/nixos/desktop-plasma-rdp.nix
    ../../modules/nixos/wayvnc-hyprland.nix
    ../../users/henrique
    ../../users/leonardo
    ../../users/martin
  ];

  networking.hostName = "caixa";
  programs.zsh.enable = true;
  hardware.graphics.enable = true;

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
