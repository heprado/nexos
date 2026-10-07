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
}
