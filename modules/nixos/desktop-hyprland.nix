{ ... }:
{
  # Local physical console only (henrique). Session appears in SDDM's
  # session picker alongside Plasma; anyone at the physical console can
  # choose either, but only henrique has this listed as his intended one.
  #
  # Uses nixpkgs-unstable's packaged Hyprland (not the upstream git flake)
  # so builds hit the binary cache instead of compiling from source.
  programs.hyprland.enable = true;

  # ABNT2 keyboard (has ç, /, dead keys, and a numpad) -- without this,
  # SDDM/the console fall back to a US layout where those keys don't map.
  services.xserver.xkb.layout = "br";
  console.keyMap = "br-abnt2";

  # Noctalia Greeter (greetd-backed) replaces SDDM as the physical-console
  # login screen, matching the look of henrique's Noctalia shell. It only
  # lists Wayland sessions (wayland-sessions/*.desktop) -- no X11 support.
  services.displayManager.sddm.enable = false;
  programs.noctalia-greeter = {
    enable = true;
    settings.session.default = "Hyprland";
    # Same wallpaper as the Hyprland session (see modules/home/hyprland.nix),
    # so the login screen matches. "${...}" copies the file into the Nix
    # store (world-readable) and interpolates its absolute store path --
    # the toml settings attrset needs a plain string here, not a Nix path.
    settings.appearance.wallpaper.path = "${../../users/henrique/217060-kagura-gintama-1920x1080.png}";
  };

  # Recommended by Noctalia (the shell/bar running in henrique's Hyprland
  # session, see modules/home/hyprland.nix) for its network/bluetooth/power
  # widgets to actually have something to report.
  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # This machine's Intel Bluetooth controller is tagged for USB autosuspend
  # by systemd's stock hwdb (see 60-autosuspend.rules), and actually
  # honoring it drops the active BLE connection to henrique's MX Vertical
  # every time it's idle for ~2s -- visible in the logs as repeated
  # "logitech-hidpp-device ... hidraw4" re-probes and "ACL packet for
  # unknown connection handle". Force the Bluetooth radio interface class
  # (e0/01/01) back to "on" (no autosuspend) to stop the mouse dropping.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{bInterfaceClass}=="e0", ATTR{bInterfaceSubClass}=="01", ATTR{bInterfaceProtocol}=="01", TEST=="power/control", ATTR{power/control}="on"
  '';
}
