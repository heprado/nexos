{ ... }:
{
  imports = [
    ../../modules/home/claude-code.nix
    ../../modules/home/git.nix
    ../../modules/home/zoxide.nix
    ../../modules/home/hyprland.nix
    ../../modules/home/helium.nix
  ];

  home.stateVersion = "24.05";
}
