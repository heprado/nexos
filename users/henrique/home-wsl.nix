{ ... }:
{
  # Terminal/dev subset of users/henrique/home.nix -- deliberately excludes
  # anything GUI (hyprland.nix, helium.nix, telegram.nix, discord.nix,
  # zed.nix, claude-voice.nix's TTS playback) since marvin is WSL with no
  # Wayland session to run any of that in.
  imports = [
    ../../modules/home/claude-code.nix
    ../../modules/home/git.nix
    ../../modules/home/glow.nix
    ../../modules/home/zoxide.nix
    ../../modules/home/direnv.nix
    ../../modules/home/devenv.nix
    ../../modules/home/neovim.nix
    ../../modules/home/zsh.nix
    ../../modules/home/ai.nix
  ];

  home.stateVersion = "24.05";
}
