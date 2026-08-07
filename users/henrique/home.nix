{ ... }:
{
  imports = [
    ../../modules/home/claude-code.nix
    ../../modules/home/git.nix
    ../../modules/home/zoxide.nix
    ../../modules/home/hyprland.nix
    ../../modules/home/helium.nix
    ../../modules/home/telegram.nix
    ../../modules/home/discord.nix
    ../../modules/home/direnv.nix
    ../../modules/home/neovim.nix
  ];

  home.stateVersion = "24.05";
}
