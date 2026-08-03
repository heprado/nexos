{ inputs, pkgs, ... }:
{
  imports = [ inputs.helium-flake.homeModules.default ];

  programs.helium = {
    enable = true;
    package = pkgs.helium;
  };
}
