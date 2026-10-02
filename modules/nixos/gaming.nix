{ pkgs, ... }:
{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    gamescopeSession.enable = true;
    # winetricks for Proton prefixes, e.g. to install a game's missing
    # runtime DLLs: `protontricks <appid> ...`.
    protontricks.enable = true;
  };
  programs.gamemode.enable = true;

  # Games are often shipped as AppImages (e.g. the N64/GBA recomps), whose
  # binaries expect a regular distro's /usr/lib (e.g. libglib-2.0.so.0).
  # binfmt has the kernel run every AppImage through appimage-run's FHS
  # environment, so they work when launched directly too, not just via
  # `appimage-run`.
  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  # Steam (see modules/nixos/unfree.nix).
  nexos.unfree = [ "steam" "steam-unwrapped" "steam-original" "steam-run" ];

  environment.systemPackages = with pkgs; [
    # Non-Steam stores/runners: GOG, Battle.net, emulators, wine in general.
    lutris
    # Installs/updates custom Proton builds (e.g. GE-Proton) into Steam's
    # and Lutris' compatibility-tool dirs.
    protonup-qt
    # FPS/frametime overlay: `mangohud %command%` in Steam launch options.
    mangohud
    # Standalone PS2 emulator. Run with `nvidia-offload pcsx2-qt` to use
    # the GTX 1650.
    pcsx2
    eden
  ];
}
