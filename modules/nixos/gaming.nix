{ config, pkgs, ... }:
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

  # Best-effort launcher entries for every installed Steam game and non-Steam
  # shortcut (e.g. Battle.net), regenerated at login and whenever a game is
  # installed/removed. Skips games Steam already made a .desktop for. Not
  # declarative on purpose: it follows whatever is installed on the machine.
  systemd.user.services.steam-desktop-entries = {
    wantedBy = [ "default.target" ];
    serviceConfig.Type = "oneshot";
    path = with pkgs; [ coreutils gnugrep gnused python3 ];
    script = ''
      apps="$HOME/.local/share/applications"
      mkdir -p "$apps"
      rm -f "$apps"/steam-auto-*.desktop

      for f in "$HOME"/.local/share/Steam/steamapps/appmanifest_*.acf; do
        [ -e "$f" ] || continue
        id=$(sed -n 's/.*"appid"[[:space:]]*"\([0-9]*\)".*/\1/p' "$f" | head -1)
        name=$(sed -n 's/.*"name"[[:space:]]*"\(.*\)".*/\1/p' "$f" | head -1)
        case "$name" in Proton*|"Steam Linux Runtime"*|"Steamworks Common"*) continue ;; esac
        grep -qs "rungameid/$id" "$apps"/*.desktop && continue

        cat > "$apps/steam-auto-$id.desktop" <<EOF
      [Desktop Entry]
      Type=Application
      Name=$name
      Exec=steam -silent steam://rungameid/$id
      Icon=steam_icon_$id
      Categories=Game;
      EOF
      done

      python3 - <<'PY'
      import glob, os, re, struct
      apps = os.path.expanduser("~/.local/share/applications")
      base = os.path.expanduser("~/.local/share/Steam/userdata")
      for vdf in glob.glob(base + "/*/config/shortcuts.vdf"):
          data = open(vdf, "rb").read()
          for m in re.finditer(rb"\x02appid\x00(.{4})\x01AppName\x00([^\x00]*)\x00", data, re.S):
              appid = struct.unpack("<I", m.group(1))[0]
              name = m.group(2).decode("utf-8", "replace")
              rid = (appid << 32) | 0x02000000
              icons = glob.glob(os.path.dirname(vdf) + "/grid/%d_icon.*" % appid)
              icon = icons[0] if icons else "steam"
              with open("%s/steam-auto-nonsteam-%d.desktop" % (apps, appid), "w") as f:
                  f.write("[Desktop Entry]\nType=Application\nName=%s\n"
                          "Exec=steam -silent steam://rungameid/%d\nIcon=%s\nCategories=Game;\n"
                          % (name, rid, icon))
      PY
    '';
  };

  # Reruns the generator when a game is installed/removed (steamapps) or a
  # non-Steam shortcut changes (userdata/<any userid>/config/shortcuts.vdf).
  # A .path unit can't glob the userid, so watch with inotify instead; it
  # exits (and restarts) if Steam's dirs don't exist yet.
  systemd.user.services.steam-desktop-entries-watch = {
    wantedBy = [ "default.target" ];
    path = with pkgs; [ inotify-tools systemd ];
    serviceConfig = {
      Restart = "always";
      RestartSec = 30;
    };
    script = ''
      while inotifywait -qq -e create,delete,moved_to,close_write \
          "$HOME"/.local/share/Steam/steamapps \
          "$HOME"/.local/share/Steam/userdata/*/config; do
        sleep 2
        systemctl --user start steam-desktop-entries.service
      done
    '';
  };

  environment.systemPackages = with pkgs; [
    # Installs/updates custom Proton builds (e.g. GE-Proton) into Steam's
    # compatibility-tool dir.
    protonup-qt
    # FPS/frametime overlay: `mangohud %command%` in Steam launch options.
    mangohud
  ];

  # MangoHud: a small HUD (FPS, frametime, CPU/GPU load, temps, clocks,
  # power, VRAM) plus CSV logging, so every game launched with `mangohud
  # %command%` can be measured the same way. Shift_L+F2 starts and stops a
  # log, written to ~/mangohud-logs as <process>_<start time>.csv (the
  # folder is made by the user tmpfiles rule below; MangoHud won't). Press
  # it once you're in the game, not at the launcher.
  home-manager.users.henrique =
    let
      logs = "${config.users.users.henrique.home}/mangohud-logs";
    in
    {
      xdg.configFile."MangoHud/MangoHud.conf".text = ''
        position=top-left
        font_size=18
        background_alpha=0.3
        fps
        frametime
        frame_timing
        cpu_stats
        cpu_temp
        cpu_mhz
        cpu_power
        gpu_stats
        gpu_temp
        gpu_core_clock
        gpu_mem_clock
        gpu_power
        vram
        ram

        # The GPU lines above make MangoHud start an NVML polling thread in
        # every process of the Steam -> Battle.net -> WoW chain (~20% of a
        # core apiece, ~0.6 core together). `blacklist` did not stop it in
        # 0.8.4, so it is only a best effort.
        blacklist=Agent,Agent.exe,agent,agent.exe,xalia,xalia.exe,Battle.net,Battle.net.exe,steam,steam.exe,explorer,explorer.exe,tabtip,tabtip.exe

        output_folder=${logs}
        # 0 = log until the key is pressed again.
        log_duration=0
        # Milliseconds between samples.
        log_interval=500
        autostart_log=0
        toggle_logging=Shift_L+F2
      '';
      systemd.user.tmpfiles.rules = [ "d ${logs} 0755 - - -" ];
    };
}
