{ config, inputs, lib, pkgs, ... }:
let
  # henrique's half of the desktop, on top of the terminal home config
  # common.nix imports: the Umbriel session, the Noctalia shell and its palette,
  # foot, GTK/Qt theming. A home-manager module, so its config, lib and pkgs are
  # home-manager's own.
  desktopHome = { config, osConfig, lib, pkgs, ... }:
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

      # Same place Noctalia writes the rendered "umbriel" template (see below). The
      # config is a read-only store link, so Noctalia can't add this include itself.
      noctaliaTheme = "${config.xdg.configHome}/umbriel/noctalia.toml";

      # Resolution, refresh rate, scale, position and workspace count per output, in
      # a writable file of its own instead of the read-only config.toml, where
      # [output.*] sections would override it. Optional, so a missing file can't stop
      # the session from starting. Monitor Settings reapplies its own saved layout
      # over this at login.
      umbrielOutputs = "${config.xdg.configHome}/umbriel/outputs.toml";

      squareGtkCss = {
        force = true;
        text = ''
          @import url("noctalia.css");

          * {
            border-radius: 0;
          }
        '';
      };

      # Whichever side was modified last wins; -p keeps that mtime on the copy, so
      # the next activation sees both equal and does nothing. A missing side is
      # filled from the other. The repo copy is read at activation time from the
      # checkout nh builds (programs.nh.flake), not from the store, so it can change
      # without a rebuild.
      syncNewest = state: repo: ''
        state="${state}"
        repo="${repo}"
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

      msg = action: "umbriel msg ${action}";

      # Pulls the next n-1 strip neighbours into the focused one's place. Umbriel
      # has no count argument for this, and a spawn runs through the shell.
      consumeNext = n:
        lib.concatStringsSep "; " (lib.replicate (n - 1) (msg "window-consume-from-right"));

      once = action: { inherit action; repeat = false; };

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
      # wlr-randr, not the compositor config, so they'd be lost at every login
      # without the reapply below.
      programs.monitor-settings = {
        enable = true;
        # The bar widget with the refresh rate. The plugin's service reapplies the
        # saved layout when the shell starts, so the module's own login service
        # would only repeat it.
        plugin = true;
        reapplyAtLogin = false;
      };

      programs.foot.enable = true;

      # Nix snowflake rendered via sixel in Brazil's colours, with room
      # between the image and the terminal edge.
      # A config file without "modules" shows no modules at all (only the
      # logo), so the list below is fastfetch's own default, copied from what
      # `fastfetch -c none --gen-config` writes.
      programs.fastfetch = {
        enable = true;
        settings = {
          logo = {
            type = "sixel";
            source = "${pkgs.runCommand "nix-snowflake-br.png" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
              sed -e 's/#415e9a/#009739/g; s/#4a6baf/#009739/g; s/#5277c3/#009739/g' \
                  -e 's/#699ad7/#FEDD00/g; s/#7eb1dd/#FEDD00/g; s/#7ebae4/#FEDD00/g' \
                ${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg > br.svg
              rsvg-convert -w 256 -h 256 br.svg -o $out
            ''}";
            width = 30;
            height = 15;
            padding = {
              left = 2;
              right = 4;
            };
          };
          modules = [
            "title" "separator" "os" "host" "kernel" "uptime" "packages"
            "shell" "display" "de" "wm" "wmtheme" "theme" "icons" "font"
            "cursor" "terminal" "terminalfont" "cpu" "gpu" "memory" "swap"
            "disk" "localip" "battery" "poweradapter" "locale" "break" "colors"
          ];
        };
      };

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
        # wl-copy/wl-paste on PATH, for programs that read the clipboard by shelling out to wl-paste --
        # Claude Code's Ctrl+V for images, notably -- couldn't paste a
        # screenshot even though it was on the clipboard.
        pkgs.wl-clipboard
        # Wayland-native, lightweight image viewer (GIF playback included).
        pkgs.imv
        # wf-recorder is the wlroots-native screen recorder (like grim, made by
        # the same maintainer) -- toggle-recording below wraps it into a single
        # start/stop bind (SUPER + R, see the keybinds below).
        pkgs.wf-recorder
        (pkgs.writeShellApplication {
          name = "toggle-recording";
          runtimeInputs = [ pkgs.wf-recorder pkgs.libnotify pkgs.procps pkgs.coreutils pkgs.umbriel pkgs.jq ];
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
              output="$(umbriel outputs --json | jq -r '.[] | select(.focused) | .name')"
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
        # Login banner pointing at the cheatsheet bind, shown once per session
        # start (general.autostart below) with a "don't show again"
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
              --title="Atalhos" \
              --text="Aperte SUPER + / para ajuda" \
              --ok-label="OK" \
              --extra-button="Não mostrar novamente" \
              2>/dev/null) || true

            if [ "$choice" = "Não mostrar novamente" ]; then
              touch "$state_file"
            fi
          '';
        })
      ];
      # Wallpaper source file lives in the repo (users/henrique/); copied into
      # ~/Pictures/Wallpapers, which is noctalia's default `wallpaper.directory`,
      # and set as the startup wallpaper below.
      home.file."Pictures/Wallpapers/217060-kagura-gintama-1920x1080.png".source =
        ../../users/henrique/217060-kagura-gintama-1920x1080.png;

      # QT_QPA_PLATFORMTHEME alone isn't enough: most Qt apps here (ddcui,
      # etc.) aren't built with hyprqt6engine as a buildInput, so
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
      # Square corners in GTK apps. Noctalia's GTK template only adds its
      # noctalia.css import when gtk.css lacks one, so this read-only file stays.
      # force: Noctalia had already written a gtk.css holding just that import.
      xdg.configFile."gtk-3.0/gtk.css" = squareGtkCss;
      xdg.configFile."gtk-4.0/gtk.css" = squareGtkCss;

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

      # Vanilla-DMZ is a small standalone XCursor theme, avoiding the KDE Breeze
      # package closure.
      home.pointerCursor = {
        enable = true;
        package = pkgs.vanilla-dmz;
        name = "Vanilla-DMZ";
        size = 24;
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
      home.activation.noctaliaSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] (syncNewest
        "${config.xdg.stateHome}/noctalia/settings.toml"
        "${osConfig.programs.nh.flake}/dotfiles/noctalia/${osConfig.networking.hostName}/settings.toml");

      # The same for the per-output settings, so hand edits land in the repo too.
      home.activation.umbrielOutputs = lib.hm.dag.entryAfter [ "writeBoundary" ] (syncNewest
        umbrielOutputs
        "${osConfig.programs.nh.flake}/dotfiles/umbriel/${osConfig.networking.hostName}/outputs.toml");

      # henrique's profile picture, read by Noctalia (settings.shell.avatar_path
      # below).
      home.file.".face".source = ../../users/henrique/user-profile.jpg;

      # Launched by Umbriel (general.autostart below), not via
      # systemd.enable, to avoid starting it twice.
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
            # gtk.css) and Qt (via kcolorscheme/qt6ct), so those
            # apps pick up the same henrique palette.
            # See <https://docs.noctalia.dev/v5/templates/official/gtk-qt/>.
            #
            # "foot" renders ~/.config/foot/themes/noctalia, included from
            # foot.ini (see xdg.configFile."foot/foot.ini" above). Its
            # ".default" variant is the active dark/light mode: noctalia
            # applies templates with the resolved mode (application_services.cpp).
            #
            # So every color comes from customPalettes.henrique below; nothing
            # here hardcodes one.
            builtin_ids = [ "gtk3" "gtk4" "qt" "kcolorscheme" "foot" "umbriel" ];

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
            mSurface = "#232937";
            mOnSurface = "#EAEAEA";
            mHover = "#3A4356";
            mOnHover = "#EAEAEA";
            mSurfaceVariant = "#2E3545";
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

      xdg.configFile."umbriel/config.toml".source = (pkgs.formats.toml { }).generate "umbriel-config.toml" {
        include.optional.files = [ noctaliaTheme umbrielOutputs ];

        general.autostart = [ "noctalia" "hypr-welcome" ];

        # Published to the systemd user manager as well, for session services.
        environment = {
          inherit (config.home.sessionVariables) QT_QPA_PLATFORMTHEME QT_PLUGIN_PATH;
        };

        input = {
          keyboard.layout = "br";
          cursor = {
            theme = config.home.pointerCursor.name;
            size = config.home.pointerCursor.size;
          };
        };

        layout = {
          mode = "scrolling";
          # Every window opens at the output's full width, the next one to its
          # right; Mod+Shift+F narrows the focused one.
          scrolling.default_extent_fraction = 1.0;
          # The widths Mod+Shift+F cycles through. Umbriel steps through them by
          # size, so from full it wraps around: 1 -> 1/3 -> 1/2 -> 2/3 -> 1.
          extent_presets = [ 0.333 0.5 0.667 1.0 ];
        };

        appearance.corner_radius = 0;

        appearance.tab_bar = {
          # A one-tab bar is just clutter.
          hide_when_single = true;
          height = 20;
          font = "sans 12";
          tab_gap = 1;
          corner_radius = 0;
        };

        # Replaces Umbriel's whole built-in set, so only what's here is bound.
        # Mod+left/right drag move and resize windows without a bind.
        keybinds = {
          "Mod+Space" = once "spawn foot";
          "Mod+D" = once "spawn noctalia msg panel-toggle launcher";
          "Mod+Q" = once "window-close";
          "Mod+F" = once "window-toggle-fullscreen";
          "Mod+Shift+F" = once "window-cycle-primary-extent";

          "Mod+Left" = "window-focus-left";
          "Mod+Right" = "window-focus-right";
          # Like Mod+Wheel: up goes left, down goes right.
          "Mod+Up" = "window-focus-left";
          "Mod+Down" = "window-focus-right";
          "Mod+Shift+Left" = "column-move-left";
          "Mod+Shift+Right" = "column-move-right";
          "Mod+Shift+Up" = "window-move-up";
          "Mod+Shift+Down" = "window-move-down";

          "Mod+1" = "workspace-switch 1";
          "Mod+2" = "workspace-switch 2";
          "Mod+3" = "workspace-switch 3";
          "Mod+Ctrl+Up" = once "window-move-to-workspace-previous";
          "Mod+Ctrl+Down" = once "window-move-to-workspace-next";

          # Windows horizontally, workspaces vertically. The cooldown keeps one
          # wheel notch from skipping past a target.
          "Mod+WheelUp" = { action = "window-focus-left"; cooldown_ms = 150; };
          "Mod+WheelDown" = { action = "window-focus-right"; cooldown_ms = 150; };
          "Mod+Shift+WheelUp" = { action = "workspace-previous"; cooldown_ms = 150; };
          "Mod+Shift+WheelDown" = { action = "workspace-next"; cooldown_ms = 150; };

          # Build or break a stack from the focused window.
          "Mod+C" = "window-consume-or-expel-left";
          "Mod+X" = "window-consume-or-expel-right";

          "Print" = once "spawn noctalia msg screenshot-annotate";
          "Shift+Print" = once "spawn noctalia msg screenshot-fullscreen all";
          "Mod+Print" = once "spawn noctalia msg screenshot-window";

          "Mod+R" = once "spawn toggle-recording";
          "Mod+slash" = once "cheatsheet-toggle";
        }
        // lib.listToAttrs (map
          (n: lib.nameValuePair "Mod+Alt+${toString n}"
            (once "spawn ${consumeNext n}; ${msg "column-set-display tabbed"}"))
          [ 2 4 6 ]);

        window_rule = [
          {
            # Otherwise it tiles instead of opening at its own declared size.
            match.app_id = "^projectMSDL$";
            default_floating = true;
          }
          {
            match.app_id = "^dev.noctalia.Noctalia$";
            default_floating = true;
            default_floating_size_px = { width = 1020; height = 900; };
          }
          {
            match.app_id = "^dev.noctalia.UmbrielSharePicker$";
            default_floating = true;
            default_floating_size_px = { width = 800; height = 600; };
          }
        ];
      };
    };
in
{
  # Everything graphical, for the hosts that have a desktop at all (marvin;
  # caixa is terminal-only). Local physical console only (henrique).
  #
  # Uses nixpkgs' packaged Umbriel, so builds hit the binary cache instead of
  # compiling from source. It starts its own bundled Xwayland on demand.
  programs.umbriel.enable = true;

  # henrique's GUI home config (Umbriel/Noctalia, browser, chat apps, ...),
  # on top of the terminal one common.nix imports.
  home-manager.users.henrique.imports = [ ../../users/henrique/home-desktop.nix desktopHome ];

  # pkgs.helium, for modules/home/helium.nix.
  nixpkgs.overlays = [ inputs.helium-flake.overlays.default ];

  # Backend dconf needs to actually apply GTK theme settings (see
  # desktopHome above's dconf.settings for henrique's GTK theme).
  programs.dconf.enable = true;

  # ABNT2 keyboard in the greeter and the graphical session -- without
  # this they fall back to a US layout. The text console's is in common.nix.
  services.xserver.xkb.layout = "br";

  # Noctalia Greeter (greetd-backed) replaces SDDM as the physical-console
  # login screen, matching the look of henrique's Noctalia shell. It only
  # lists Wayland sessions (wayland-sessions/*.desktop) -- no X11 support.
  services.displayManager.sddm.enable = false;
  services.displayManager.noctalia-greeter = {
    enable = true;
    settings.session.default = "Umbriel";
    # Same wallpaper as the desktop session (see desktopHome above),
    # so the login screen matches. "${...}" copies the file into the Nix
    # store (world-readable) and interpolates its absolute store path --
    # the toml settings attrset needs a plain string here, not a Nix path.
    settings.appearance.wallpaper.path = "${../../users/henrique/217060-kagura-gintama-1920x1080.png}";
    # Same colors as henrique's Noctalia shell: the greeter runs as its own
    # user before login, so it can't read his palette, but it takes the
    # same keys in snake_case without the "m" (mOnSurfaceVariant ->
    # on_surface_variant) -- converted here from customPalettes.henrique in
    # desktopHome above, so that stays the only place colors are
    # set. "Synced" is the scheme that uses [appearance.palette].
    settings.appearance = {
      scheme = "Synced";
      theme_mode = "dark";
      # The Noctalia brand logo on the login screen.
      hide_logo = true;
      palette =
        let
          dark = config.home-manager.users.henrique.programs.noctalia.customPalettes.henrique.dark;
          # "mOnSurfaceVariant" -> "on_surface_variant"
          snake = name:
            lib.removePrefix "_" (lib.concatMapStrings
              (c: if c != lib.toLower c then "_" + lib.toLower c else c)
              (lib.stringToCharacters (lib.removePrefix "m" name)));
        in
        lib.mapAttrs' (name: lib.nameValuePair (snake name))
          (removeAttrs dark [ "terminal" ]);
    };
  };

  # A Secret Service provider (org.freedesktop.secrets on D-Bus): ZapFast
  # keeps its WhatsApp session in the OS keyring and refuses to start
  # without one ("Unlock your OS keyring ... ServiceUnknown"). This also
  # adds pam_gnome_keyring to the "login" PAM stack, which greetd includes,
  # so logging in unlocks the "login" keyring with the login password
  # (creating it on first login) and nothing prompts for it afterwards.
  services.gnome.gnome-keyring.enable = true;

  # Recommended by Noctalia (the shell/bar running in henrique's
  # session, see desktopHome above) for its network/bluetooth/power
  # widgets to actually have something to report (NetworkManager itself is
  # enabled in common.nix).
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # PipeWire provides desktop audio, including Pulse/ALSA compatibility.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # Noctalia's brightness widget had nothing to actually control: this
  # desktop's monitor is external, so there's no /sys/class/backlight
  # device at all (that sysfs interface only exists for laptop panels) --
  # external monitor brightness goes over DDC/CI via the display cable
  # instead, which needs ddcutil talking to /dev/i2c-*. hardware.i2c also
  # grants access to any user with a seat (logind uaccess), not just a
  # udev group, so henrique doesn't need to be added to a group by hand.
  # brightnessctl is included too, in case a laptop panel/backlight ever
  # does show up here (e.g. an eGPU/dock scenario).
  hardware.i2c.enable = true;

  # Thunar file manager (back from Dolphin -- see git log, Dolphin's KDE
  # Frameworks stack felt sluggish), plus plugins for auto-mounting
  # removable media (volman), archive extract/create, VCS status overlays,
  # network share browsing, and audio/image metadata columns.
  # programs.thunar.enable pulls in programs.xfconf.enable itself (needed
  # for Thunar to persist its own settings).
  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-volman
      thunar-vcs-plugin
      thunar-shares-plugin
      thunar-media-tags-plugin
      thunar-archive-plugin
    ];
  };
  # thunar-volman (above) needs gvfs to actually auto-mount/eject media and
  # to give Thunar trash/network-share (sftp, etc.) support.
  services.gvfs.enable = true;

  # Without an actual icon theme installed, GTK falls back to hicolor's
  # single generic "text-x-generic" icon for everything (upscaled -- hence
  # the blurry/pixelated icons for everything, Thunar included). Adwaita
  # is GTK's own default icon-theme name, so just having the package
  # present is enough to pick it up.
  #
  # projectm_3 ships projectM-pulseaudio, the native MilkDrop-compatible
  # visualizer the noctalia-song-visualizer plugin shells out to -- it
  # opens its own OpenGL window and reads system audio via PulseAudio
  # (over pipewire-pulse) on its own, so no other package is needed for it.
  environment.systemPackages = [ pkgs.adwaita-icon-theme pkgs.ddcutil pkgs.brightnessctl pkgs.projectm_3 ];

  # tumbler is the D-Bus thumbnailer service Thunar calls out to for image
  # (and video/font/etc.) preview thumbnails -- without it, files just
  # show their mimetype icon instead of an actual preview.
  services.tumbler.enable = true;

  # This machine's Intel Bluetooth controller is tagged for USB autosuspend
  # by systemd's stock hwdb (see 60-autosuspend.rules), and actually
  # honoring it drops the active BLE connection to henrique's MX Vertical
  # every time it's idle for ~2s -- visible in the logs as repeated
  # "logitech-hidpp-device ... hidraw4" re-probes and "ACL packet for
  # unknown connection handle". Force the Bluetooth radio interface class
  # (e0/01/01) back to "on" (no autosuspend) to stop the mouse dropping.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{bInterfaceClass}=="e0", ATTR{bInterfaceSubClass}=="01", ATTR{bInterfaceProtocol}=="01", TEST=="power/control", ATTR{power/control}="on"
  '';

  # projectMSDL (github.com/projectM-visualizer/frontend-sdl-cpp release
  # tarball, used by noctalia-song-visualizer) is a prebuilt binary run
  # through nix-ld (users/henrique/default.nix) -- `ldd` on it reports these
  # three missing alongside libstdc++, which the module already provides by
  # default.
  programs.nix-ld.libraries = with pkgs; [ SDL2 freetype libglvnd ];

  # Profile picture for the login screen: noctalia-greeter shows each
  # user's AccountsService IconFile, read as the "greeter" user. With none
  # set, AccountsService reports ~/.face, which the greeter can't read
  # (home is 0700), so it fell back to a generic icon. Same picture as
  # Noctalia's own avatar (~/.face, desktopHome above).
  systemd.tmpfiles.rules = [
    "L+ /var/lib/AccountsService/icons/henrique - - - - ${../../users/henrique/user-profile.jpg}"
    "f+ /var/lib/AccountsService/users/henrique 0600 root root - [User]\\nIcon=/var/lib/AccountsService/icons/henrique\\nSystemAccount=false\\n"
  ];
}
