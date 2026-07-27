{ pkgs, ... }:
{
  home.packages = [ pkgs.noctalia-shell ];

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "hyprlang";
    # Wires up hyprland-session.target so systemd user services (like
    # wayvnc) can bind their lifecycle to the actual Hyprland session.
    systemd.enable = true;
    settings = {
      monitor = [ ",preferred,auto,auto" ];
      exec-once = [ "noctalia-shell" ];
    };
  };
}
