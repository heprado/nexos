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

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  # Recommended by Noctalia (the shell/bar running in henrique's Hyprland
  # session, see modules/home/hyprland.nix) for its network/bluetooth/power
  # widgets to actually have something to report.
  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
}
