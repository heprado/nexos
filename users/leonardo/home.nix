{ ... }:
{
  imports = [
    ../../modules/home/claude-code.nix
    ../../modules/home/zoxide.nix
    ../../modules/home/telegram.nix
    ../../modules/home/discord.nix
  ];

  home.stateVersion = "24.05";
}
