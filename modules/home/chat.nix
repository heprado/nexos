{ pkgs, ... }:
{
  home.packages = [
    pkgs.telegram-desktop
    # Vesktop instead of the official Discord client: it loads CSS themes,
    # so it follows the Noctalia palette (the "discord" community template
    # in modules/home/hyprland.nix). Same account and servers.
    pkgs.vesktop
    # ZapFast: native WhatsApp client in Rust (no WebEngine), Wayland-native.
    # There's no official WhatsApp client for Linux.
    pkgs.zapfast
  ];

  # Noctalia's "telegram" template (modules/home/hyprland.nix) renders into
  # ~/.config/telegram-desktop/themes, but only once ~/.config/telegram-desktop
  # exists -- it takes that as "Telegram is installed". Telegram itself
  # keeps its data in ~/.local/share/TelegramDesktop and never creates it,
  # so without this the theme was always skipped.
  xdg.configFile."telegram-desktop/themes/.keep".text = "";

  # ZapFast's packaged desktop entry omits the URL field and its protocol
  # MIME types. Shadow it so desktop handlers pass whatsapp:/wa: links to it.
  xdg.desktopEntries.zapfast = {
    name = "ZapFast";
    genericName = "WhatsApp Client";
    comment = "A native WhatsApp client";
    exec = "zapfast %u";
    icon = "zapfast";
    terminal = false;
    categories = [ "Network" "InstantMessaging" "Chat" ];
    mimeType = [ "x-scheme-handler/whatsapp" "x-scheme-handler/wa" ];
  };

  # Link handlers (mimeapps.list is managed, see modules/home/reading.nix).
  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
    "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";
    "x-scheme-handler/discord" = "vesktop.desktop";
    "x-scheme-handler/whatsapp" = "zapfast.desktop";
    "x-scheme-handler/wa" = "zapfast.desktop";
  };
}
