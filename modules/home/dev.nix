{ pkgs, ... }:
{
  # Per-project environments: each project's own devenv.nix (packages,
  # services like postgres/minio) is activated by direnv on cd -- see
  # templates/*.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };

  # Global devenv CLI.
  home.packages = [ pkgs.devenv ];
}
