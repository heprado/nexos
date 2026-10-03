{ config, osConfig, inputs, pkgs, lib, ... }:
let
  # hyprqt6engine is a Qt platform-theme plugin: it's dlopen()ed into
  # every Qt app, so it has to link against the same libstdc++ they do.
  # The hyprwm flake builds it (and hyprlang/hyprutils under it) with
  # gcc16Stdenv, needing GLIBCXX_3.4.36, which nixpkgs' gcc-15 Qt apps
  # don't have -- the plugin then fails to load everywhere ("version
  # `GLIBCXX_3.4.36' not found", visible with QT_DEBUG_PLUGINS=1) and Qt
  # silently falls back to its default palette. Rebuilt here with the
  # regular stdenv instead; the extended package set is local to this.
  hyprqt6engine =
    (pkgs.extend (lib.composeManyExtensions [
      (_: prev: { gcc16Stdenv = prev.stdenv; })
      inputs.hyprqt6engine.overlays.hyprqt6engine-with-deps
    ])).hyprqt6engine;

  # hyprqt6engine is Qt6-only, and QT_QPA_PLATFORMTHEME takes a single
  # name for both Qt versions (a `a:b` list doesn't help: each Qt only
  # tries the first entry), so Qt5 apps (vlc, ddcui, projectm) got Qt's
  # default palette. Same trick Plasma uses -- one theme name answered by
  # a Qt5 and a Qt6 plugin: qt5ct already answers to "qt6ct" besides its
  # own name, and this makes it answer to "hyprqt6engine" too. Qt5 apps
  # then load qt5ct (configured by qt5ct.conf below) under the same
  # variable that gets Qt6 apps hyprqt6engine. --replace-fail turns a
  # qt5ct update that moves these lines into a build error instead of a
  # silently unthemed Qt5.
  qt5ct = pkgs.libsForQt5.qt5ct.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/qt5ct-qtplugin/qt5ct.json \
        --replace-fail '"qt6ct"' '"qt6ct", "hyprqt6engine"'
      substituteInPlace src/qt5ct-qtplugin/main.cpp \
        --replace-fail 'key.toLower() == "qt6ct"' \
                       'key.toLower() == "qt6ct" || key.toLower() == "hyprqt6engine"'
    '';
  });

  # Each Qt only loads plugins built for its own major version, so both
  # directories can share one QT_PLUGIN_PATH.
  qtPluginPath = lib.concatStringsSep ":" [
    "${hyprqt6engine}/lib/qt-6"
    "${qt5ct}/${pkgs.libsForQt5.qtbase.qtPluginPrefix}"
  ];
in
{
  imports = [
    inputs.noctalia.homeModules.default
    inputs.monitor-settings.homeManagerModules.default
  ];

  # home-manager now ships its own programs.noctalia, declaring the same
  # options as Noctalia's module above. That module disables it itself, but
  # by its old path ("programs/noctalia.nix"); home-manager moved it to a
  # directory, so both got loaded ("option ... is already declared").
  disabledModules = [ "programs/noctalia" ];

  # Display arrangement (drag-and-drop canvas, mode, scale, rotation,
  # adaptive sync) and DDC/CI controls. Positions set there go through
  # wlr-randr, not hl.monitor below, so they'd be lost at every login --
  # the module's oneshot user service reapplies the saved layout once
  # graphical-session.target is up.
  programs.monitor-settings.enable = true;

  programs.foot.enable = true;

  # Renames how these apps show up in Noctalia's launcher (and any other
  # XDG-desktop-file-based launcher/dock/menu -- this isn't a launcher
  # feature, it's a standard XDG override: a user-level .desktop with the
  # same basename as the system one wins, per $XDG_DATA_DIRS search order
  # putting ~/.local/share first). Only Name= actually needs to change;
  # Exec/Icon/etc are copied from each package's real .desktop file so the
  # override still launches/looks the same otherwise.
  xdg.desktopEntries = {
    nvim = {
      name = "Neovim";
      genericName = "Text Editor";
      exec = "nvim %F";
      icon = "nvim";
      terminal = true;
      categories = [ "Utility" "TextEditor" "Development" ];
    };
    nwg-look = {
      name = "Configurações GTK";
      exec = "nwg-look";
      icon = "nwg-look";
      categories = [ "GTK" "Settings" "DesktopSettings" ];
    };
    thunar = {
      name = "Explorador de Arquivos";
      exec = "thunar %U";
      icon = "org.xfce.thunar";
      categories = [ "System" "Core" "GTK" "FileTools" "FileManager" ];
      mimeType = [ "inode/directory" ];
    };
  };

  # Thunar's "Open Terminal Here" (and other exo-open callers) shell out to
  # `exo-open --launch TerminalEmulator`, which normally resolves via Xfce's
  # helpers.rc -- but nothing here ever set that up (this desktop has no
  # xfce4-terminal/xterm providing exo's usual bundled default helper), so
  # it fell through to exo's dynamic Categories=TerminalEmulator .desktop
  # scan and *still* came up empty -- foot.desktop's own Categories does
  # list TerminalEmulator, but that scan depends on XDG_DATA_DIRS reaching
  # the exo-open child process, which (like XCURSOR_THEME/QT_QPA_PLATFORMTHEME
  # below) isn't guaranteed for everything Thunar spawns. Registering an
  # explicit custom helper sidesteps both: helpers.rc points straight at it,
  # and it lives under ~/.local/share, which GLib always checks regardless
  # of XDG_DATA_DIRS.
  xdg.configFile."xfce4/helpers.rc".text = ''
    TerminalEmulator=custom-foot
  '';
  xdg.dataFile."xfce4/helpers/custom-foot.desktop".text = ''
    [Desktop Entry]
    Version=1.0
    Encoding=UTF-8
    Type=X-XFCE-Helper
    X-XFCE-Category=TerminalEmulator
    Name=Foot
    Comment=Foot terminal emulator
    Icon=foot
    Exec=foot
    Terminal=false
    StartupNotify=false
  '';

  # Not done via programs.foot.settings: that makes home-manager generate
  # foot.ini itself, which would fight with us owning the file directly
  # below -- simpler to just own foot.ini directly here.
  #
  # Colors come from noctalia's "foot" template (templates.builtin_ids
  # below), which renders the active palette's terminal.* colors -- for
  # whichever of dark/light mode is active -- into themes/noctalia. Its
  # apply.sh would add the include line below to foot.ini itself, but
  # can't write to this read-only (store-linked) file; with the line
  # already here its check passes and it leaves the file alone. foot only
  # picks up new colors in newly opened windows.
  xdg.configFile."foot/foot.ini".text = ''
    [main]
    include=~/.config/foot/themes/noctalia
    # A Nerd Font specifically (not a fallback list) -- nvim-web-devicons,
    # lualine, and blink.cmp's nerd_font_variant (all in neovim.nix) render
    # icon glyphs that only exist in Nerd Font builds, and those glyphs are
    # sized/baselined to sit in exactly one terminal cell only within the
    # patched font itself. A separate fallback font for just the icons
    # tends to misalign cell width/baseline instead.
    font=JetBrainsMono Nerd Font:size=13
  '';

  # GTK/Qt theming backends the noctalia gtk3/gtk4/qt/kcolorscheme
  # templates above actually need to take effect app-wide.
  # See <https://docs.noctalia.dev/v5/templates/official/gtk-qt/>.
  #
  # hyprqt6engine (below, QT_QPA_PLATFORMTHEME) is the Qt theme engine.
  # qt6ct isn't installed: it's archived upstream, and its GUI only edits
  # its own qt6ct.conf, which hyprqt6engine never reads -- theme changes
  # made there silently did nothing. The Qt colors come from Noctalia's
  # "qt" template instead (see hyprqt6engine.conf below).
  home.packages = [
    pkgs.adw-gtk3
    pkgs.nwg-look
    hyprqt6engine
    # Provides the "JetBrainsMono Nerd Font" family foot.ini (below) uses --
    # nothing in this config previously installed any Nerd Font at all, so
    # icon glyphs (nvim-web-devicons, lualine, etc. in neovim.nix) rendered
    # as tofu boxes.
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.feishin
    pkgs.vlc
    pkgs.btop
    pkgs.hyfetch
    # Qt GUI for ddcutil -- external-monitor brightness/contrast/color (RGB
    # gain, color temperature presets, whatever VCP features this monitor
    # actually reports) over DDC/CI. Needed because Noctalia's own
    # brightness widget only exposes brightness, not color, even with
    # brightness.enableDdcSupport on in its settings.json.
    pkgs.ddcui
    # Generic wlroots output tool (implements wlr-output-management-v1),
    # for inspecting/setting outputs by hand. Monitor Settings (above)
    # carries its own copy on its wrapper's PATH and doesn't need this.
    pkgs.wlr-randr
    # Remote VDI access. The tarball can't be fetched automatically (Citrix's
    # EULA requires a manual, logged-in download); see the comment on
    # nixpkgs.config.allowUnfreePredicate in machines/caixa/configuration.nix
    # and the nix-prefetch-url step described there before this will build.
    # nixpkgs pins 26.04.0.105, which Citrix has since pulled from their
    # downloads page -- overridden here to the newest build actually
    # available there (gcc11 linuxx64 tarball) instead of nixpkgs's version.
/*    (pkgs.citrix-workspace.overrideAttrs (_: {
      version = "26.08.0.153";
      src = pkgs.requireFile {
        name = "linuxx64-26.08.0.153.tar.gz";
        sha256 = "17f0nlg18bz2b6qq86i04igm551b54nym41zi13m81906fzgi4h7";
        message = ''
          In order to use Citrix Workspace, you need to comply with the Citrix EULA and download
          the 64-bit binaries, .tar.gz from:

          https://www.citrix.com/downloads/workspace-app/

          Once you have downloaded the file, please use the following command and re-run the
          installation:

          nix-prefetch-url file://$PWD/linuxx64-26.08.0.153.tar.gz
        '';
      };
    }))*/
    # grimblast is Hyprland's own screenshot helper (wraps grim+slurp+hyprctl)
    # -- SUPER+Print/SHIFT below (see hl.bind in extraConfig, via the
    # "screenshot" wrapper right below, not grimblast's own --notify).
    pkgs.grimblast
    # wl-copy/wl-paste on PATH. grimblast only bundles its own copy, so
    # programs that read the clipboard by shelling out to wl-paste --
    # Claude Code's Ctrl+V for images, notably -- couldn't paste a
    # screenshot even though it was on the clipboard.
    pkgs.wl-clipboard
    # Wayland-native, lightweight image viewer (GIF playback included) for
    # the "screenshot" notification's click action below.
    pkgs.imv
    (pkgs.writeShellApplication {
      name = "screenshot";
      runtimeInputs = [ pkgs.grimblast pkgs.imv pkgs.libnotify pkgs.coreutils ];
      text = ''
        # grimblast copysave both writes the file and copies it to the
        # clipboard, echoing the saved path on success -- captured here
        # instead of using grimblast's own --notify/--openparentdir so the
        # notification's click action opens imv (an image viewer) rather
        # than grimblast's built-in "show in file manager" action.
        file="$(grimblast copysave "$1")"

        (
          action="$(notify-send --wait --action="default=Abrir visualizador" "Captura de tela" "Salva em $file" -i "$file")"
          if [ "$action" = "default" ]; then
            imv "$file" &
            disown
          fi
        ) &
        disown
      '';
    })
    # wf-recorder is the wlroots-native screen recorder (like grim, made by
    # the same maintainer) -- toggle-recording below wraps it into a single
    # start/stop bind (SUPER + R, see hl.bind in extraConfig).
    pkgs.wf-recorder
    (pkgs.writeShellApplication {
      name = "toggle-recording";
      runtimeInputs = [ pkgs.wf-recorder pkgs.libnotify pkgs.procps pkgs.coreutils pkgs.hyprland pkgs.jq ];
      text = ''
        state_file="''${XDG_RUNTIME_DIR:-/tmp}/toggle-recording-file"

        if pidof wf-recorder > /dev/null; then
          pkill -INT wf-recorder
          file="$(cat "$state_file")"
          # --wait blocks until the notification is dismissed or its action
          # clicked, printing which action fired -- "default" is the
          # freedesktop convention for clicking the notification body
          # itself, not a separate button. Backgrounded so the keybind
          # doesn't hang waiting on it.
          (
            action="$(notify-send --wait --action="default=Abrir no Thunar" "Screen recording" "Stopped -> $file")"
            if [ "$action" = "default" ]; then
              thunar --select "$file" &
              disown
            fi
          ) &
          disown
        else
          mkdir -p "$HOME/Videos"
          file="$HOME/Videos/recording-$(date +%Y-%m-%d_%H-%M-%S).mp4"
          echo "$file" > "$state_file"
          # With more than one monitor connected (marvin: laptop panel +
          # HDMI) wf-recorder asks on stdin which output to record; with no
          # terminal to answer it just exits, so nothing was ever recorded
          # and the next press "started" again instead of stopping. Record
          # the focused monitor instead.
          output="$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')"
          wf-recorder -o "$output" -f "$file" &
          disown
          sleep 0.5
          if pidof wf-recorder > /dev/null; then
            notify-send "Screen recording" "Started ($output) -> $file"
          else
            notify-send -u critical "Screen recording" "wf-recorder failed to start on $output"
          fi
        fi
      '';
    })
    # SUPER + / (see the hl.bind below) opens this in a floating foot window.
    # Reads live off `hyprctl binds -j`'s `description` field instead of
    # keeping a separate hardcoded list, so it can't drift out of sync with
    # the actual binds declared in extraConfig below.
    # Login banner pointing at the cheatsheet bind, shown once per session
    # start (hl.on("hyprland.start", ...) below) with a "don't show again"
    # button that persists via a marker file in ~/.local/state.
    (pkgs.writeShellApplication {
      name = "hypr-welcome";
      runtimeInputs = [ pkgs.zenity pkgs.coreutils ];
      text = ''
        state_file="$HOME/.local/state/hypr-welcome-dismissed"
        [ -f "$state_file" ] && exit 0
        mkdir -p "$(dirname "$state_file")"

        choice=""
        choice=$(zenity --question \
          --title="Hyprland" \
          --text="Aperte SUPER + / para ajuda" \
          --ok-label="OK" \
          --extra-button="Não mostrar novamente" \
          2>/dev/null) || true

        if [ "$choice" = "Não mostrar novamente" ]; then
          touch "$state_file"
        fi
      '';
    })
    (pkgs.writeShellApplication {
      name = "hypr-cheatsheet";
      runtimeInputs = [ pkgs.jq pkgs.util-linux pkgs.less ];
      text = ''
        hyprctl binds -j | jq -r '
          def bit_set($m; $b): (($m / $b) | floor) % 2 == 1;
          def mods($m):
            [ if bit_set($m; 64) then "Super" else empty end,
              if bit_set($m; 4) then "Ctrl" else empty end,
              if bit_set($m; 8) then "Alt" else empty end,
              if bit_set($m; 1) then "Shift" else empty end
            ] | join(" + ");
          def keyname:
            if .key == "mouse:272" then "Botão esquerdo do mouse"
            elif .key == "mouse:273" then "Botão direito do mouse"
            elif .key == "mouse_down" then "Scroll para baixo"
            elif .key == "mouse_up" then "Scroll para cima"
            else .key end;
          [ .[] | select(.description != "") ]
          | .[]
          | (mods(.modmask) + " + " + keyname) + "\t" + .description
        ' | column -t -s $'\t' | less
      '';
    })
  ];
  # Wallpaper source file lives in the repo (users/henrique/); copied into
  # ~/Pictures/Wallpapers, which is noctalia's default `wallpaper.directory`,
  # and set as the startup wallpaper below.
  home.file."Pictures/Wallpapers/217060-kagura-gintama-1920x1080.png".source =
    ../../users/henrique/217060-kagura-gintama-1920x1080.png;

  # QT_QPA_PLATFORMTHEME alone isn't enough: most Qt apps here (ddcui,
  # feishin, etc.) aren't built with hyprqt6engine as a buildInput, so
  # nixpkgs' wrapQtAppsHook never adds its plugin dir to their own
  # per-binary QT_PLUGIN_PATH wrapper -- some (e.g. ddcui) aren't even
  # wrapped at all. Without this, Qt falls back to its compiled-in
  # default plugin path (baked from qtbase's own store path at build
  # time), which can never see a separately-built package like
  # hyprqt6engine, so "hyprqt6engine" would silently fail to load as
  # the platform theme everywhere except its own process. The same goes
  # for the patched qt5ct and Qt5 apps (see qtPluginPath above).
  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "hyprqt6engine";
    QT_PLUGIN_PATH = qtPluginPath;
  };
  dconf.settings."org/gnome/desktop/interface".gtk-theme = "adw-gtk3";

  # Points color_scheme at the file Noctalia's "qt" builtin template
  # renders. The template writes it under ~/.config/qt6ct/ in qt6ct's
  # color-scheme format even with qt6ct itself not installed, and
  # hyprqt6engine accepts that format directly -- no changes needed to the
  # programs.noctalia.settings.theme.templates.builtin_ids list above.
  # The *color scheme* file is qt6ct's INI format, but this config file
  # itself is hyprlang (`theme:color_scheme`): an INI `[theme]` header is
  # an "Invalid config line" and the whole entry gets dropped.
  xdg.configFile."hypr/hyprqt6engine.conf".text = ''
    theme {
        color_scheme = /home/henrique/.config/qt6ct/colors/noctalia.conf
    }
  '';

  # The Qt5 side of the same theme: the patched qt5ct (see the let block)
  # reads this, pointed at the qt5ct copy of the color scheme Noctalia's
  # "qt" template renders alongside the qt6ct one. Fusion matches the
  # style Qt6 apps get from hyprqt6engine.
  xdg.configFile."qt5ct/qt5ct.conf".text = ''
    [Appearance]
    color_scheme_path=/home/henrique/.config/qt5ct/colors/noctalia.conf
    custom_palette=true
    style=Fusion
  '';

  # Without this, the cursor theme only ever exists as a live dconf/nwg-look
  # setting -- nothing propagates it to Hyprland's own (wlroots) cursor
  # renderer, so any compositor restart (e.g. after nixos-rebuild switch)
  # reverts to Hyprland's built-in default arrow. hyprcursor.enable adds
  # HYPRCURSOR_THEME/HYPRCURSOR_SIZE alongside XCURSOR_THEME/XCURSOR_SIZE,
  # since Hyprland prefers the hyprcursor format when available.
  home.pointerCursor = {
    enable = true;
    package = pkgs.kdePackages.breeze;
    name = "breeze_cursors";
    size = 24;
    hyprcursor.enable = true;
  };

  # Noctalia's control center saves its changes to
  # ~/.local/state/noctalia/settings.toml, layered over the config.toml that
  # programs.noctalia below generates. That file isn't managed by Nix, so on
  # every activation (each `nrs`) it's synced with a copy in this repo, to
  # be committed (one copy per host, since e.g. lockscreen widget positions
  # depend on its monitors): the newer of the two overwrites the other, so
  # control-center changes land in the repo and hand edits to the repo copy
  # (or a git pull) land in ~/.local/state; a missing side (e.g. after a
  # reinstall, before Noctalia first starts) is filled from the other. The
  # repo copy is read at activation time from the checkout nh builds
  # (programs.nh.flake), not from the store, so it can change without a
  # rebuild.
  home.activation.noctaliaSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    state="${config.xdg.stateHome}/noctalia/settings.toml"
    repo="${osConfig.programs.nh.flake}/dotfiles/noctalia/${osConfig.networking.hostName}/settings.toml"
    # Whichever side was modified last wins; -p keeps that mtime on the
    # copy, so the next activation sees both equal and does nothing.
    if [ -f "$state" ] && [ -f "$repo" ]; then
      if [ "$repo" -nt "$state" ]; then
        run cp -p "$repo" "$state"
      elif [ "$state" -nt "$repo" ]; then
        run cp -p "$state" "$repo"
      fi
    elif [ -f "$state" ]; then
      run mkdir -p "$(dirname "$repo")"
      run cp -p "$state" "$repo"
    elif [ -f "$repo" ]; then
      run mkdir -p "$(dirname "$state")"
      run cp -p "$repo" "$state"
    fi
  '';

  # henrique's profile picture, read by Noctalia (settings.shell.avatar_path
  # below).
  home.file.".face".source = ../../users/henrique/user-profile.jpg;

  # Launched from Hyprland's Lua config itself (hl.on("hyprland.start", ...)
  # below), per <https://docs.noctalia.dev/v5/compositor-settings/hyprland/>
  # — not via systemd.enable, to avoid starting it twice.
  programs.noctalia = {
    enable = true;
    systemd.enable = false;
    settings.wallpaper.default.path = "~/Pictures/Wallpapers/217060-kagura-gintama-1920x1080.png";
    # Profile picture (control center, lock screen): ~/.face, the usual
    # avatar location, linked by home.file below -- so the setting shows a
    # readable path rather than the image's /nix/store one.
    settings.shell.avatar_path = "~/.face";
    settings.theme = {
      mode = "dark";
      source = "custom";
      custom_palette = "henrique";
      templates = {
        # Off by default (opt-in) — enables Noctalia's built-in templates
        # that sync the active palette into GTK3/GTK4 (via a generated
        # gtk.css) and Qt (via kcolorscheme/qt6ct), so non-Hyprland-native
        # apps pick up the same henrique palette.
        # See <https://docs.noctalia.dev/v5/templates/official/gtk-qt/>.
        #
        # "foot" renders ~/.config/foot/themes/noctalia, included from
        # foot.ini (see xdg.configFile."foot/foot.ini" above). Its
        # ".default" variant is the active dark/light mode: noctalia
        # applies templates with the resolved mode (application_services.cpp).
        #
        # "hyprland" renders ~/.config/hypr/noctalia.lua (border/groupbar
        # colors and groupbar text, driven by the active palette, plus a
        # `colors` table the config below reads mSurface from). Its
        # apply.sh can't append the require("noctalia") line into our
        # hyprland.lua (home-manager symlinks it read-only from the store)
        # -- so that line is added by hand in extraConfig below instead of
        # relying on apply.sh for it.
        #
        # So every color comes from customPalettes.henrique below; nothing
        # here hardcodes one.
        builtin_ids = [ "gtk3" "gtk4" "qt" "kcolorscheme" "hyprland" "foot" ];

        # Fetched from api.noctalia.dev/templates. Neither applies itself:
        # - "telegram" renders
        #   ~/.config/telegram-desktop/themes/noctalia.tdesktop-theme, which
        #   has to be opened from Telegram (Settings > Chat Settings >
        #   Choose from file) -- again after palette changes.
        # - "ungoogled-chromium" renders a theme extension into
        #   ~/.cache/noctalia/ungoogled-chromium/theme, loaded once in
        #   Helium (chrome://extensions > Developer mode > Load unpacked);
        #   it then follows the palette, after a browser restart.
        # - "discord" renders themes for Vesktop (modules/home/chat.nix)
        #   into ~/.config/vesktop/themes -- enabled once in Vesktop
        #   (Settings > Themes). It also writes the same files for other
        #   Discord client mods (Vencord, BetterDiscord, ...), unused here.
        enable_community_templates = true;
        community_ids = [ "telegram" "ungoogled-chromium" "discord" ];
      };
    };
    # Written to ~/.config/noctalia/palettes/henrique.json.
    # See <https://docs.noctalia.dev/v5/theming/#custom_palette>.
    customPalettes.henrique = {
      # Tama's colors (Gintama): hair #5A9E72, eyes #8B2C45, yukata #4261A1,
      # apron #EAEAEA, obi #D9A752, the screw in her hair #7D848C. The
      # backgrounds are the yukata blue darkened (dark) or the apron
      # (light). On the dark background the eyes and yukata colors are too
      # dark to read (2.0:1 and 2.8:1), so lightened versions are used
      # there; magenta/cyan, which the six colors don't have, mix eyes +
      # yukata and hair + yukata. Every text/terminal color clears 4.5:1
      # against its background.
      dark = {
        mPrimary = "#5A9E72";
        mOnPrimary = "#171A21";
        mSecondary = "#D9A752";
        mOnSecondary = "#171A21";
        mTertiary = "#6E8CC8";
        mOnTertiary = "#171A21";
        mError = "#D0607A";
        mOnError = "#171A21";
        mSurface = "#171A21";
        mOnSurface = "#EAEAEA";
        mHover = "#2B3240";
        mOnHover = "#EAEAEA";
        mSurfaceVariant = "#20252F";
        mOnSurfaceVariant = "#B9BEC6";
        mOutline = "#7D848C";
        mShadow = "#0C0E12";
        terminal = {
          background = "#171A21";
          foreground = "#EAEAEA";
          cursor = "#5A9E72";
          cursorText = "#171A21";
          selectionBg = "#4261A1";
          selectionFg = "#EAEAEA";
          normal = {
            black = "#20252F";
            red = "#D0607A";
            green = "#5A9E72";
            yellow = "#D9A752";
            blue = "#6E8CC8";
            magenta = "#B36DA0";
            cyan = "#4FA6A0";
            white = "#B9BEC6";
          };
          bright = {
            black = "#7D848C";
            red = "#E07D93";
            green = "#7DBE93";
            yellow = "#EBC27A";
            blue = "#93AEE0";
            magenta = "#CB8DBB";
            cyan = "#74C4BE";
            white = "#EAEAEA";
          };
        };
      };
      light = {
        mPrimary = "#3A7550";
        mOnPrimary = "#F5F5F5";
        mSecondary = "#86601A";
        mOnSecondary = "#F5F5F5";
        mTertiary = "#4261A1";
        mOnTertiary = "#F5F5F5";
        mError = "#8B2C45";
        mOnError = "#F5F5F5";
        mSurface = "#EAEAEA";
        mOnSurface = "#1E2533";
        mSurfaceVariant = "#F5F5F5";
        mOnSurfaceVariant = "#3E4654";
        mOutline = "#7D848C";
        mShadow = "#C9CDD3";
        mHover = "#D9DDE3";
        mOnHover = "#1E2533";
        terminal = {
          foreground = "#1E2533";
          background = "#EAEAEA";
          selectionFg = "#F5F5F5";
          selectionBg = "#4261A1";
          cursorText = "#EAEAEA";
          cursor = "#3A7550";
          normal = {
            black = "#1E2533";
            red = "#8B2C45";
            green = "#3A7550";
            yellow = "#86601A";
            blue = "#4261A1";
            magenta = "#7E3F72";
            cyan = "#2B726D";
            white = "#7D848C";
          };
          bright = {
            black = "#4A5260";
            red = "#A3364F";
            green = "#3C7150";
            yellow = "#83601E";
            blue = "#4965A3";
            magenta = "#8F4C83";
            cyan = "#2C706B";
            white = "#B9BEC6";
          };
        };
      };
    };
  };

  wayland.windowManager.hyprland = {
    enable = true;
    # Hyprland 0.55+ deprecated hyprlang in favor of Lua config; hyprlang
    # is only kept around for 1-2 releases past 0.55 before removal, and
    # nixpkgs is already on 0.56.0 (one release past the cutoff).
    configType = "lua";
    # Wires up hyprland-session.target so systemd user services (like
    # wayvnc and noctalia) can bind their lifecycle to the actual
    # Hyprland session.
    systemd.enable = true;
    # "scrolling" is a native layout in Hyprland core as of 0.56.0 (no
    # plugin needed — the old third-party hyprscroller plugin this used to
    # depend on is deprecated/disabled upstream now that core absorbed it).
    #
    # Written directly in Lua (rather than the `settings` attrset, whose
    # Nix->Lua auto-conversion has open upstream bugs, e.g.
    # nix-community/home-manager#9468 and #9341) for reliability. Verified
    # against the real hl.meta.lua stub and bundled example config shipped
    # in the actual hyprland-0.56.0 nixpkgs derivation (share/hypr/), not
    # just docs.
    extraConfig = ''
      -- home.sessionVariables (below) only reaches login shells; apps
      -- launched via hyprctl dispatch exec or D-Bus activation (most GUI
      -- launchers, xdg autostart) don't see it. hl.env propagates into the
      -- systemd user session and D-Bus activation environment instead --
      -- see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/.
      -- This is what actually fixes apps complaining
      -- "QT_QPA_PLATFORMTHEME environment variable is not set".
      hl.env("QT_QPA_PLATFORMTHEME", "hyprqt6engine")
      -- Same reasoning: without this reaching the systemd/D-Bus session
      -- too, GUI-launched Qt apps (the vast majority under Hyprland)
      -- never see QT_PLUGIN_PATH either, so hyprqt6engine's platform
      -- theme plugin silently fails to load for them even though the
      -- QT_QPA_PLATFORMTHEME name above is set correctly.
      hl.env("QT_PLUGIN_PATH", "${qtPluginPath}")

      -- Same reasoning as QT_QPA_PLATFORMTHEME above -- home.pointerCursor
      -- only writes plain home.sessionVariables, which don't reach the
      -- systemd-activated Hyprland session, so the cursor theme has to be
      -- re-propagated here too.
      hl.env("XCURSOR_THEME", "breeze_cursors")
      hl.env("XCURSOR_SIZE", "24")
      hl.env("HYPRCURSOR_THEME", "breeze_cursors")
      hl.env("HYPRCURSOR_SIZE", "24")

      hl.on("hyprland.start", function()
        hl.exec_cmd("noctalia")
        hl.exec_cmd("hypr-welcome")
      end)

      hl.monitor({ output = "", mode = "highrr", position = "auto", scale = "auto" })

      -- Pins workspace 1 to the external HDMI monitor and makes it that
      -- output's default, so it's what shows up there on login. On a
      -- machine without HDMI-A-1 the rule just never matches.
      hl.workspace_rule({ workspace = "1", monitor = "HDMI-A-1", default = true })

      -- Applies the henrique palette (customPalettes above) to
      -- general.col.active_border/inactive_border and
      -- group.col.border_*/groupbar.col.* -- see the "hyprland" builtin_ids
      -- entry above for why this is a manual require() instead of the
      -- usual apply.sh-appended one. Guarded: on a brand new machine this
      -- runs before noctalia has ever rendered ~/.config/hypr/noctalia.lua,
      -- and a failed top-level require would otherwise take down the whole
      -- Hyprland config.
      local ok, noctaliaTheme = pcall(require, "noctalia")
      if ok then
        noctaliaTheme.apply_theme()
      end

      hl.config({
        general = {
          layout = "scrolling",
        },
        input = {
          kb_layout = "br",
        },
        misc = {
          -- What Hyprland paints behind everything (gaps, the sliver
          -- between groupbar tabs, etc.) before any window content -- the
          -- default (0xff111111) still lets an unstable/changing wallpaper
          -- show through those gaps. Pinned to mSurface instead of relying
          -- on the wallpaper for it, read from the noctalia template's
          -- `colors` table so it follows the palette (and dark/light mode);
          -- left at Hyprland's default if the template isn't rendered yet.
          background_color = ok and noctaliaTheme.colors.surface or nil,
        },
        group = {
          groupbar = {
            -- Hide the bar entirely once expel/consume_or_expel (SUPER+C/X
            -- and SUPER+SHIFT/ALT+2/4/6 above) whittles a group down to its
            -- last window -- a one-tab bar is just clutter at that point.
            disable_when_only = true,
            -- col.active/col.inactive and text_color/text_color_inactive
            -- come from the noctalia "hyprland" template applied above
            -- (mSecondary/mSurface, mOnSecondary/mOnSurface), not
            -- hardcoded here.
            -- col.active/col.inactive above only paint a thin 3px
            -- indicator strip (indicator_height) at the bottom of each
            -- tab -- NOT the area behind the title text (per
            -- CHyprGroupBarDecoration.cpp, undocumented on the wiki).
            -- That area is only filled if `gradients` is on, which
            -- reuses those same col.active/inactive values to paint a
            -- (here effectively solid, since they're single colors, not
            -- multi-stop) texture behind the title -- otherwise it's
            -- fully transparent and the wallpaper shows through it.
            gradients = true,
            -- The indicator strip itself (the thin bar below the filled
            -- gradient/title area, colored via col.active/inactive from the
            -- noctalia template -- mSurface reads as near-black) is
            -- redundant now that gradients fill each tab solid, and looks
            -- like a stray black bar under a rounded pill. Hyprland's own
            -- min for this is 1px (indicator_height), it can't go to 0.
            indicator_height = 1,
            -- gaps_out/gaps_in put a real gap around/between tabs --
            -- deliberate now that the template's col.active/inactive +
            -- gradients (above) actually fill each tab solid, so the
            -- wallpaper showing in those gaps reads as intentional spacing,
            -- not a rendering bug.
            gaps_out = 4,
            gaps_in = 1,
            -- With tabs no longer touching (gaps_in above), rounding only
            -- the bar's outer edges (round_only_edges' default) would leave
            -- the middle tabs square-cornered -- round every tab instead.
            -- "rounding" is the indicator strip, "gradient_rounding" is the
            -- title-area fill enabled above. They need to match: the
            -- indicator is the SAME col.active/inactive color as the
            -- gradient fill above it (same source values, per
            -- CHyprGroupBarDecoration.cpp), so a mismatched radius is what
            -- makes it read as a separate black box glued to the bottom of
            -- the tab instead of part of the same pill. Hyprland has no
            -- per-corner (top-only) rounding here, this is the closest.
            rounding = 0,
            round_only_edges = false,
            gradient_rounding = 0,
            gradient_round_only_edges = false,
            -- Default font_size is 8px, barely legible; height (default 14)
            -- bumped along with it so the bigger text isn't clipped.
            font_size = 12,
            height = 20,
          },
        },
        scrolling = {
          -- Fraction of screen width per column, [0.1-1.0] -- 0.5 means
          -- exactly 2 columns fit on screen at once. Combined with stacking
          -- 2 windows per column (SUPER+C below), that's up to 4 windows
          -- visible at a time; a 5th+ window lands in its own column
          -- offscreen, reachable only by scrolling (SUPER+mouse wheel or
          -- SUPER+left/right) -- this is the layout's default behavior
          -- already, nothing else needed for that part.
          column_width = 0.5,
        },
      })

      local mainMod = "SUPER"
      hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("foot"), { description = "Abrir um terminal" })
      hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("noctalia msg panel-toggle launcher"), { description = "Abrir/fechar o launcher de aplicativos" })
      hl.bind(mainMod .. " + Q", hl.dsp.window.close(), { description = "Fechar a janela em foco" })
      -- fullscreen(0) is the classic Hyprland dispatcher's "real" fullscreen
      -- mode (fills the whole output, hides bars/gaps) -- 1 would be
      -- "maximize" (fills the layout area only, bars/gaps stay visible).
      hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen(0), { description = "Tela cheia na janela em foco" })
      hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }), { description = "Focar a janela à esquerda" })
      hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }), { description = "Focar a janela à direita" })
      hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }), { description = "Focar a janela acima" })
      hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }), { description = "Focar a janela abaixo" })

      -- Switch to workspace 1-5 with SUPER + [1-5].
      for i = 1, 5 do
        hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }), { description = "Ir para a área de trabalho " .. i })
      end

      -- Grid: pull the next N-1 columns (starting after the focused window,
      -- moving rightward) into the current column, so all N windows share
      -- the column's space and are visible at once -- same mechanism as
      -- the SUPER+C single-step consume above, just repeated. Dispatcher
      -- objects can't be called directly, only via hl.dispatch().
      for _, n in ipairs({ 2, 4, 6 }) do
        hl.bind(mainMod .. " + SHIFT + " .. n, function()
          for _ = 1, n - 1 do
            hl.dispatch(hl.dsp.layout("consume"))
          end
        end, { description = "Empilhar as próximas " .. n .. " janelas num grid" })
      end

      -- Tabs: group the next N windows (starting at the focused one, moving
      -- rightward through columns) into a single tabbed view instead: only
      -- one is visible at a time. "into_or_create_group r" wraps the
      -- moveintoorcreategroup dispatcher, which merges the active window
      -- into its right-hand neighbor's group (creating one if it doesn't
      -- exist yet) -- calling it repeatedly grows the group one column at
      -- a time. Undocumented on the wiki, only in
      -- LuaBindingsDispatcherUtils.cpp/ConfigActions.cpp in Hyprland's
      -- source.
      for _, n in ipairs({ 2, 4, 6 }) do
        hl.bind(mainMod .. " + ALT + " .. n, function()
          for _ = 1, n - 1 do
            hl.dispatch(hl.dsp.window.move({ into_or_create_group = "r" }))
          end
        end, { description = "Agrupar as próximas " .. n .. " janelas em abas" })
      end

      -- Scroll wheel moves focus between windows in the scrolling layout
      -- (not bound by the layout itself -- see
      -- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/#layout-messages).
      hl.bind(mainMod .. " + mouse_down", hl.dsp.layout("focus r"), { description = "Focar a próxima janela (scroll)" })
      hl.bind(mainMod .. " + mouse_up", hl.dsp.layout("focus l"), { description = "Focar a janela anterior (scroll)" })

      -- Build/break the 4-window grid, acting on the FOCUSED window itself
      -- (no need to pre-select the neighboring column first). This is
      -- "consume_or_expel", not the plain "consume"/"expel" messages --
      -- it's undocumented on the wiki, only in ScrollingAlgorithm.cpp: it
      -- toggles based on the focused window's current state. If it's
      -- standalone, it merges into the adjacent column (stacks below
      -- what's already there); if it's already stacked, it pops back out
      -- into its own column instead (which then needs a scroll to reach
      -- again).
      hl.bind(mainMod .. " + C", hl.dsp.layout("consume_or_expel prev"), { description = "Empilhar/desempilhar a janela em foco com a coluna anterior" })
      hl.bind(mainMod .. " + X", hl.dsp.layout("consume_or_expel next"), { description = "Empilhar/desempilhar a janela em foco com a próxima coluna" })

      -- Print now goes through noctalia's own screenshot-annotate IPC command
      -- (freezes the screen, opens the v5.1 region editor with drawing
      -- annotations; Copy/Save deliver the result and close the editor by
      -- default) instead of grimblast, to get the annotation toolbar. The
      -- other two binds stay on grimblast (see home.packages) since noctalia
      -- doesn't have an "active window" capture equivalent.
      hl.bind("Print", hl.dsp.exec_cmd("noctalia msg screenshot-annotate"), { description = "Captura de tela: selecionar uma área com anotações" })
      hl.bind("SHIFT + Print", hl.dsp.exec_cmd("screenshot screen"), { description = "Captura de tela: tela inteira" })
      hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd("screenshot active"), { description = "Captura de tela: janela ativa" })

      -- Screen recording via wf-recorder, wrapped in toggle-recording (see
      -- home.packages) so a single bind both starts and stops it.
      hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("toggle-recording"), { description = "Iniciar/parar gravação de tela" })

      -- Hold SUPER + drag with LMB/RMB to move/resize the focused window
      -- (mouse:272/273 are the classic hyprlang bindm equivalents in Lua).
      hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Mover a janela em foco" })
      hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Redimensionar a janela em foco" })

      -- Keybind cheatsheet: hypr-cheatsheet (see home.packages) reads
      -- descriptions straight off `hyprctl binds -j`, so it can never drift
      -- out of sync with the binds actually declared above.
      hl.bind(mainMod .. " + slash", hl.dsp.exec_cmd("foot --app-id hypr-cheatsheet -e hypr-cheatsheet"), { description = "Mostrar esta folha de atalhos" })

      hl.window_rule({
        name = "float-hypr-cheatsheet",
        match = { class = "hypr-cheatsheet" },
        float = true,
      })

      -- Without this, projectMSDL (noctalia-song-visualizer's MilkDrop
      -- window -- migrated off the older projectM-pulseaudio) tiles like
      -- any other window instead of opening at its own declared size,
      -- which is what made it look huge.
      hl.window_rule({
        name = "float-projectmsdl",
        match = { class = "projectMSDL" },
        float = true,
      })
    '';
  };
}
