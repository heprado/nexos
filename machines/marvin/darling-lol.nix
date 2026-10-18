# League of Legends' macOS client on Darling, with darling-lol's patches
# (~/codigos/darling-lol-iso): `darling-lol install br`, then `darling-lol
# run`. It runs in the Hyprland session through Xwayland, as on
# darling-lol's author's setup.
{ config, inputs, lib, pkgs, ... }:
{
  imports = [ inputs.darling-lol-iso.nixosModules.darling-lol ];

  programs.darling-lol.enable = true;

  # darling-lol needs Xwayland on the GPU Mesa renders on: inside Darling,
  # NVIDIA's EGL fails to create contexts (the Riot Client aborts when a
  # popup opens), and Xwayland on NVIDIA rejects Intel's buffers. The
  # compositor's renderer is fixed when it starts (AQ_DRM_DEVICES), so the
  # greeter offers a second session with Intel first, for playing; the
  # usual one keeps NVIDIA first for smooth HDMI.
  services.displayManager.sessionPackages = [
    ((pkgs.writeTextDir "share/wayland-sessions/hyprland-intel.desktop" ''
      [Desktop Entry]
      Name=Hyprland (Intel)
      Comment=Hyprland rendering on the Intel GPU, for darling-lol
      Exec=${pkgs.writeShellScript "start-hyprland-intel" ''
        export AQ_DRM_DEVICES=/dev/dri/intel-igpu:/dev/dri/nvidia-dgpu
        exec ${lib.getExe' config.programs.hyprland.package "start-hyprland"}
      ''}
      Type=Application
      DesktopNames=Hyprland
    ''
    ).overrideAttrs { passthru.providedSessions = [ "hyprland-intel" ]; })
  ];
}
