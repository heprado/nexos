{ ... }:
{
  # GUI half of henrique's home config, only on hosts that import
  # modules/nixos/desktop-hyprland.nix. claude-voice is here because it
  # plays through PipeWire, which only the desktop module enables.
  imports = [
    ../../modules/home/chat.nix
    ../../modules/home/design.nix
    ../../modules/home/claude-voice.nix
    ../../modules/home/hyprland.nix
    ../../modules/home/helium.nix
    ../../modules/home/zed.nix
  ];
}
