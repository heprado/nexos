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

  environment.systemPackages = with pkgs; [
    # Non-Steam stores/runners: GOG, Battle.net, emulators, wine in general.
    lutris
    # Installs/updates custom Proton builds (e.g. GE-Proton) into Steam's
    # and Lutris' compatibility-tool dirs.
    protonup-qt
    # FPS/frametime overlay: `mangohud %command%` in Steam launch options.
    mangohud
    # Emulator frontend, bundled with every libretro core packaged in nixpkgs.
    retroarch-full
    # Standalone PS2 emulator; more complete and up to date than the
    # libretro port. Run with `nvidia-offload pcsx2-qt` to use the GTX 1650.
    pcsx2
    eden
  ];
}
