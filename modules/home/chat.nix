{ pkgs, ... }:
{
  home.packages = [
    pkgs.telegram-desktop
    # Vesktop instead of the official Discord client: it loads CSS themes,
    # so it follows the Noctalia palette (the "discord" community template
    # in modules/nixos/desktop.nix). Same account and servers.
    pkgs.vesktop
  ];

  # Noctalia's "telegram" template (modules/nixos/desktop.nix) renders into
  # ~/.config/telegram-desktop/themes, but only once ~/.config/telegram-desktop
  # exists -- it takes that as "Telegram is installed". Telegram itself
  # keeps its data in ~/.local/share/TelegramDesktop and never creates it,
  # so without this the theme was always skipped.
  xdg.configFile."telegram-desktop/themes/.keep".text = "";

  # Link handlers (mimeapps.list is managed, see users/henrique/home-desktop.nix).
  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
    "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";
    "x-scheme-handler/discord" = "vesktop.desktop";
  };
}
