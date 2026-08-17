{ pkgs, ... }:
{
  # Global devenv CLI. Per-project environments (packages, services like
  # postgres/minio) live in each project's own devenv.nix, activated by
  # direnv -- see modules/home/direnv.nix and templates/*.
  home.packages = [
    pkgs.devenv
  ];
}
