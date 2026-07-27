{ inputs, ... }:
{
  imports = [ inputs.noctalia.homeModules.default ];

  # Launched as a systemd user service (tied to hyprland-session.target
  # below) rather than a plain Hyprland exec-once line — that's the
  # officially supported wiring and includes auto-restart plus a watcher
  # that reloads on config/palette changes.
  programs.noctalia = {
    enable = true;
    systemd.enable = true;
  };

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "hyprlang";
    # Wires up hyprland-session.target so systemd user services (like
    # wayvnc and noctalia) can bind their lifecycle to the actual
    # Hyprland session.
    systemd.enable = true;
    settings = {
      monitor = [ ",preferred,auto,auto" ];
    };
  };
}
