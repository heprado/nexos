{ pkgs, ... }:
{
  languages.c.enable = true;

  packages = with pkgs; [
    clang-tools
    gnumake
    gdb
  ];
}
