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

  # Steam itself, plus the libretro cores retroarch-full pulls in that have
  # non-commercial licenses (see modules/nixos/unfree.nix).
  nexos.unfree = [
    "steam" "steam-unwrapped" "steam-original" "steam-run"
    "libretro-fbalpha2012" "libretro-fbneo" "libretro-fmsx"
    "libretro-genesis-plus-gx" "libretro-mame2000" "libretro-mame2003"
    "libretro-mame2003-plus" "libretro-mame2010" "libretro-mame2015"
    "libretro-opera" "libretro-picodrive" "libretro-snes9x"
    "libretro-snes9x2002" "libretro-snes9x2005" "libretro-snes9x2005-plus"
    "libretro-snes9x2010"
  ];

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
