{ ... }:
{
  imports = [
    ../../modules/home/claude-code.nix
    ../../modules/home/zoxide.nix
    ../../modules/home/hyprland.nix
  ];

  home.stateVersion = "24.05";
}
