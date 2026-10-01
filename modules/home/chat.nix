{ pkgs, ... }:
{
  home.packages = [
    pkgs.telegram-desktop
    pkgs.discord
    # ZapZap: WhatsApp Web in Qt6 WebEngine, native on Wayland. There's no
    # official WhatsApp client for Linux.
    pkgs.zapzap
  ];
}
