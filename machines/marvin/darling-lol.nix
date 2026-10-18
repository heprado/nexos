# League of Legends' macOS client on Darling, with darling-lol's patches
# (~/codigos/darling-lol-iso): `darling-lol install br`, then `darling-lol
# run`. It runs in the Hyprland session through Xwayland, as on
# darling-lol's author's setup.
{ inputs, ... }:
{
  imports = [ inputs.darling-lol-iso.nixosModules.darling-lol ];

  # Hyprland renders on Intel (AQ_DRM_DEVICES), so Xwayland, Mesa's EGL and
  # Vulkan (the loader's first device) all use it: darling-lol's validated
  # single-GPU Mesa path, with direct presentation.
  programs.darling-lol.enable = true;
}
