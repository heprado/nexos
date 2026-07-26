{ ... }:
{
  imports = [
    ../../modules/home/claude-code.nix
    ../../modules/home/zoxide.nix
  ];

  home.stateVersion = "24.05";
}
