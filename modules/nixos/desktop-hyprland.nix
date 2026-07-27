{ ... }:
{
  # Local physical console only (henrique). Session appears in SDDM's
  # session picker alongside Plasma; anyone at the physical console can
  # choose either, but only henrique has this listed as his intended one.
  programs.hyprland.enable = true;

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
}
