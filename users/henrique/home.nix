{ ... }:
{
  imports = [
    ../../modules/home/claude-code.nix
    ../../modules/home/git.nix
    ../../modules/home/glow.nix
    ../../modules/home/zoxide.nix
    ../../modules/home/hyprland.nix
    ../../modules/home/helium.nix
    ../../modules/home/telegram.nix
    ../../modules/home/discord.nix
    ../../modules/home/whatsapp.nix
    ../../modules/home/direnv.nix
    ../../modules/home/devenv.nix
    ../../modules/home/neovim.nix
    ../../modules/home/zsh.nix
    ../../modules/home/ai.nix
    ../../modules/home/claude-voice.nix
    ../../modules/home/zed.nix
  ];

  home.stateVersion = "24.05";
}
