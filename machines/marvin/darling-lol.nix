# League of Legends' macOS client on Darling, with darling-lol's patches
# (~/codigos/darling-lol-iso): `darling-lol install br`, then `darling-lol
# run`. It runs in the Hyprland session through Xwayland, as on
# darling-lol's author's setup.
{ inputs, ... }:
{
  imports = [ inputs.darling-lol-iso.nixosModules.darling-lol ];

  programs.darling-lol = {
    enable = true;
    # Hyprland renders on the GTX 1650 (AQ_DRM_DEVICES), so Xwayland and
    # Darling do too, and darling-lol's direct presentation draws black on
    # NVIDIA: copy frames through the CPU instead.
    directPresent = false;
  };
}
