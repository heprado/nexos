{ pkgs, ... }:
{
  # ZapZap: WhatsApp Web in Qt6 WebEngine, native on Wayland. There's no
  # official WhatsApp client for Linux.
  home.packages = [ pkgs.zapzap ];
}
