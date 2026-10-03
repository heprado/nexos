{ pkgs, ... }:
{
  home.packages = [
    # Vector graphics, e.g. rEFInd's background (modules/nixos/refind.nix).
    pkgs.inkscape
  ];
}
