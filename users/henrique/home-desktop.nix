{ pkgs, ... }:
{
  # GUI half of henrique's home config, only on hosts that import
  # modules/nixos/desktop.nix.
  imports = [
    ../../modules/home/chat.nix
    ../../modules/home/design.nix
    ../../modules/home/helium.nix
    ../../modules/home/zed.nix
  ];

  # xdg-open is used by GUI apps and development tools to open URLs/files.
  home.packages = [ pkgs.xdg-utils ];

  # home-manager now owns ~/.config/mimeapps.list (read-only symlink), so
  # apps can no longer write their own associations there -- every default
  # has to be declared next to its app (chat.nix, helium.nix).
  # The attrsets merge across modules.
  xdg.mimeApps.enable = true;
}
