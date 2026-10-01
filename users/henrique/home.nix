{ ... }:
{
  imports = [
    ../../modules/home/cli.nix
    ../../modules/home/dev.nix
    ../../modules/home/chat.nix
    ../../modules/home/ai.nix
    ../../modules/home/claude-voice.nix
    ../../modules/home/hyprland.nix
    ../../modules/home/helium.nix
    ../../modules/home/neovim.nix
    ../../modules/home/zed.nix
    ../../modules/home/zsh.nix
  ];

  home.stateVersion = "24.05";
}
