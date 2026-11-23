{ ... }:
{
  # Terminal-only half, on every host (caixa has no GUI at all). The GUI
  # half is home-desktop.nix, imported by modules/nixos/desktop.nix.
  imports = [
    ../../modules/home/cli.nix
    ../../modules/home/ai.nix
    ../../modules/home/neovim.nix
    ../../modules/home/bash.nix
  ];

  home.stateVersion = "24.05";
}
