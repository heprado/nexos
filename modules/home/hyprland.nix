{ inputs, pkgs, ... }:
{
  imports = [ inputs.noctalia.homeModules.default ];

  programs.foot.enable = true;

  # Not done via programs.foot.settings: that makes home-manager generate
  # foot.ini itself, and its font/etc keys would still need to coexist
  # with the [main] include line the noctalia foot template below wires
  # in via its apply.sh — simpler to just own foot.ini directly here.
  # apply.sh only (re)writes this file when its own `include=...noctalia`
  # line is missing, so pre-populating it ourselves means it's never
  # touched and this font setting is never clobbered by a theme re-apply.
  xdg.configFile."foot/foot.ini".text = ''
    [main]
    include=~/.config/foot/themes/noctalia
    font=monospace:size=13
  '';

  # GTK/Qt theming backends the noctalia gtk3/gtk4/qt/kcolorscheme
  # templates above actually need to take effect app-wide.
  # See <https://docs.noctalia.dev/v5/templates/official/gtk-qt/>.
  home.packages = [
    pkgs.adw-gtk3
    pkgs.nwg-look
    pkgs.qt6Packages.qt6ct
    pkgs.feishin
    pkgs.vlc
    # grimblast is Hyprland's own screenshot helper (wraps grim+slurp+hyprctl)
    # -- SUPER+Print/SHIFT below (see hl.bind in extraConfig).
    pkgs.grimblast
    # wf-recorder is the wlroots-native screen recorder (like grim, made by
    # the same maintainer) -- toggle-recording below wraps it into a single
    # start/stop bind (SUPER + R, see hl.bind in extraConfig).
    pkgs.wf-recorder
    (pkgs.writeShellApplication {
      name = "toggle-recording";
      runtimeInputs = [ pkgs.wf-recorder pkgs.libnotify pkgs.procps pkgs.coreutils ];
      text = ''
        if pidof wf-recorder > /dev/null; then
          pkill -INT wf-recorder
          notify-send "Screen recording" "Stopped"
        else
          mkdir -p "$HOME/Videos"
          file="$HOME/Videos/recording-$(date +%Y-%m-%d_%H-%M-%S).mp4"
          notify-send "Screen recording" "Started -> $file"
          wf-recorder -f "$file" &
          disown
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

  home.sessionVariables.QT_QPA_PLATFORMTHEME = "qt6ct";
  dconf.settings."org/gnome/desktop/interface".gtk-theme = "adw-gtk3";

  # Launched from Hyprland's Lua config itself (hl.on("hyprland.start", ...)
  # below), per <https://docs.noctalia.dev/v5/compositor-settings/hyprland/>
  # — not via systemd.enable, to avoid starting it twice.
  programs.noctalia = {
    enable = true;
    systemd.enable = false;
    settings.wallpaper.default.path = "~/Pictures/Wallpapers/217060-kagura-gintama-1920x1080.png";
    settings.theme = {
      mode = "dark";
      source = "custom";
      custom_palette = "henrique";
      templates = {
        # Off by default (opt-in) — enables Noctalia's built-in templates
        # that sync the active palette into GTK3/GTK4 (via a generated
        # gtk.css), Qt (via kcolorscheme/qt6ct), and foot (via a themes/
        # fragment wired in through foot.ini's `include`), so non-
        # Hyprland-native apps pick up the same henrique palette.
        # See <https://docs.noctalia.dev/v5/templates/official/gtk-qt/>.
        #
        # foot itself has no live-reload, but that's moot here: the
        # fragment is only read when a new foot window starts. Must NOT
        # set programs.foot.settings anywhere — that makes home-manager
        # symlink a read-only foot.ini from the Nix store, which breaks
        # this template's apply.sh (it needs to rewrite foot.ini to add
        # the include line).
        builtin_ids = [ "gtk3" "gtk4" "qt" "kcolorscheme" "foot" ];
      };
    };
    # Written to ~/.config/noctalia/palettes/henrique.json.
    # See <https://docs.noctalia.dev/v5/theming/#custom_palette>.
    customPalettes.henrique = {
      dark = {
        mPrimary = "#51afef";
        mOnPrimary = "#1c1e1e";
        mSecondary = "#f2c481";
        mOnSecondary = "#1c1e1e";
        mTertiary = "#98be65";
        mOnTertiary = "#1c1e1e";
        mError = "#ff6b5a";
        mOnError = "#1c1e1e";
        mSurface = "#1c1e1e";
        mOnSurface = "#fffcf8";
        mHover = "#2d3139";
        mOnHover = "#fffcf8";
        mSurfaceVariant = "#282c34";
        mOnSurfaceVariant = "#bbc2cf";
        mOutline = "#3f444a";
        mShadow = "#111212";
        terminal = {
          background = "#1c1e1e";
          foreground = "#fffcf8";
          cursor = "#bbc2cf";
          cursorText = "#1c1e1e";
          selectionBg = "#fffcf8";
          selectionFg = "#2d3138";
          normal = {
            black = "#1c1e1e";
            red = "#ff6b5a";
            green = "#98be65";
            yellow = "#f2c481";
            blue = "#51afef";
            magenta = "#dc8ef3";
            cyan = "#46d9ff";
            white = "#bbc2cf";
          };
          bright = {
            black = "#2e323a";
            red = "#ff7665";
            green = "#a9cf76";
            yellow = "#f2c481";
            blue = "#47a5e5";
            magenta = "#c678dd";
            cyan = "#4db5bd";
            white = "#f0f6fc";
          };
        };
      };
      light = {
        mPrimary = "#4078f2";
        mOnPrimary = "#fafafa";
        mSecondary = "#ea9558";
        mOnSecondary = "#fafafa";
        mTertiary = "#50a14f";
        mOnTertiary = "#fafafa";
        mError = "#e45649";
        mOnError = "#fafafa";
        mSurface = "#f0f0f0";
        mOnSurface = "#383a42";
        mSurfaceVariant = "#fafafa";
        mOnSurfaceVariant = "#2e2e2e";
        mOutline = "#c6c7c7";
        mShadow = "#f0f0f0";
        mHover = "#51afef";
        mOnHover = "#f0f0f0";
        terminal = {
          foreground = "#383a42";
          background = "#f0f0f0";
          selectionFg = "#fafafa";
          selectionBg = "#4078f2";
          cursorText = "#2e2e2e";
          cursor = "#c6c7c7";
          normal = {
            black = "#383a42";
            red = "#e45649";
            green = "#50a14f";
            yellow = "#986801";
            blue = "#4078f2";
            magenta = "#a626a4";
            cyan = "#0184bc";
            white = "#c6c7c7";
          };
          bright = {
            black = "#2e2e2e";
            red = "#c85a50";
            green = "#4db5bd";
            yellow = "#da8548";
            blue = "#a0bcf8";
            magenta = "#b751b6";
            cyan = "#005478";
            white = "#f0f0f0";
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
      hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

      hl.on("hyprland.start", function()
        hl.exec_cmd("noctalia")
        hl.exec_cmd("hypr-welcome")
      end)

      hl.monitor({ output = "", mode = "highrr", position = "auto", scale = "auto" })

      hl.config({
        general = {
          layout = "scrolling",
        },
        input = {
          kb_layout = "br",
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
      hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("foot"), { description = "Abrir um terminal" })
      hl.bind(mainMod .. " + Q", hl.dsp.window.close(), { description = "Fechar a janela em foco" })
      hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }), { description = "Focar a janela à esquerda" })
      hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }), { description = "Focar a janela à direita" })
      hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }), { description = "Focar a janela acima" })
      hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }), { description = "Focar a janela abaixo" })

      -- Switch to workspace 1-5 with SUPER + [1-5].
      for i = 1, 5 do
        hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }), { description = "Ir para a área de trabalho " .. i })
      end

      -- Scroll wheel moves focus between windows in the scrolling layout
      -- (not bound by the layout itself -- see
      -- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/#layout-messages).
      hl.bind(mainMod .. " + mouse_down", hl.dsp.layout("focus r"), { description = "Focar a próxima janela (scroll)" })
      hl.bind(mainMod .. " + mouse_up", hl.dsp.layout("focus l"), { description = "Focar a janela anterior (scroll)" })

      -- Build/break the 4-window grid: consume stacks the focused window
      -- into the previous column (so it shares that column's space with
      -- what's already there); expel pops it back out into its own column,
      -- which then needs a scroll to reach again.
      hl.bind(mainMod .. " + C", hl.dsp.layout("consume"), { description = "Empilhar a janela em foco na coluna anterior" })
      hl.bind(mainMod .. " + X", hl.dsp.layout("expel"), { description = "Tirar a janela em foco da coluna" })

      -- Screenshots via grimblast (see home.packages): copysave both writes
      -- the file (to ~/Pictures by default) and copies it to the clipboard,
      -- with a notification linking to the saved file.
      hl.bind("Print", hl.dsp.exec_cmd("grimblast --notify copysave area"), { description = "Captura de tela: selecionar uma área" })
      hl.bind("SHIFT + Print", hl.dsp.exec_cmd("grimblast --notify copysave screen"), { description = "Captura de tela: tela inteira" })
      hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd("grimblast --notify copysave active"), { description = "Captura de tela: janela ativa" })

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
    '';
  };
}
