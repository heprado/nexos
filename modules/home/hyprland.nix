{ inputs, pkgs, ... }:
{
  imports = [ inputs.noctalia.homeModules.default ];

  programs.foot.enable = true;

  # Thunar's "Open Terminal Here" (and other exo-open callers) shell out to
  # `exo-open --launch TerminalEmulator`, which normally resolves via Xfce's
  # helpers.rc -- but nothing here ever set that up (this desktop has no
  # xfce4-terminal/xterm providing exo's usual bundled default helper), so
  # it fell through to exo's dynamic Categories=TerminalEmulator .desktop
  # scan and *still* came up empty -- foot.desktop's own Categories does
  # list TerminalEmulator, but that scan depends on XDG_DATA_DIRS reaching
  # the exo-open child process, which (like XCURSOR_THEME/QT_QPA_PLATFORMTHEME
  # above) isn't guaranteed for everything Thunar spawns. Registering an
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
  # Colors are the henrique customPalette's dark.terminal.* values
  # (below), inlined by hand instead of noctalia's "foot" builtin_id
  # template (deliberately NOT in templates.builtin_ids below): that
  # template always renders the ".default" palette variant, not the
  # active dark/light mode, which is why switching noctalia to light
  # theme changed nothing in foot either way -- an upstream bug. Means
  # this won't live-update on theme changes (foot has no live-reload for
  # color config anyway, so that's moot until the next foot window) or
  # automatically track dark/light mode -- if noctalia ever fixes the
  # template upstream, switch back.
  xdg.configFile."foot/foot.ini".text = ''
    [main]
    # A Nerd Font specifically (not a fallback list) -- nvim-web-devicons,
    # lualine, and blink.cmp's nerd_font_variant (all in neovim.nix) render
    # icon glyphs that only exist in Nerd Font builds, and those glyphs are
    # sized/baselined to sit in exactly one terminal cell only within the
    # patched font itself. A separate fallback font for just the icons
    # tends to misalign cell width/baseline instead.
    font=JetBrainsMono Nerd Font:size=13

    [colors-dark]
    foreground=fffcf8
    background=1c1e1e
    regular0=1c1e1e
    regular1=ff6b5a
    regular2=98be65
    regular3=f2c481
    regular4=51afef
    regular5=dc8ef3
    regular6=46d9ff
    regular7=bbc2cf
    bright0=2e323a
    bright1=ff7665
    bright2=a9cf76
    bright3=f2c481
    bright4=47a5e5
    bright5=c678dd
    bright6=4db5bd
    bright7=f0f6fc
    selection-foreground=2d3138
    selection-background=fffcf8
    cursor=1c1e1e bbc2cf
  '';

  # GTK/Qt theming backends the noctalia gtk3/gtk4/qt/kcolorscheme
  # templates above actually need to take effect app-wide.
  # See <https://docs.noctalia.dev/v5/templates/official/gtk-qt/>.
  home.packages = [
    pkgs.adw-gtk3
    pkgs.nwg-look
    pkgs.qt6Packages.qt6ct
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
    # Remote VDI access. The tarball can't be fetched automatically (Citrix's
    # EULA requires a manual, logged-in download); see the comment on
    # nixpkgs.config.allowUnfreePredicate in machines/caixa/configuration.nix
    # and the nix-prefetch-url step described there before this will build.
    pkgs.citrix-workspace
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
        # gtk.css) and Qt (via kcolorscheme/qt6ct), so non-Hyprland-native
        # apps pick up the same henrique palette.
        # See <https://docs.noctalia.dev/v5/templates/official/gtk-qt/>.
        #
        # Deliberately NOT "foot": that builtin template always renders the
        # ".default" palette variant, ignoring dark/light mode -- see the
        # comment on xdg.configFile."foot/foot.ini" above, which inlines
        # the same colors by hand instead.
        #
        # "hyprland" renders ~/.config/hypr/noctalia.lua (border/groupbar
        # colors driven by the active palette). Its apply.sh can't append
        # the require("noctalia") line into our hyprland.lua (home-manager
        # symlinks it read-only from the store) -- so that line is added by
        # hand in extraConfig below instead of relying on apply.sh for it.
        builtin_ids = [ "gtk3" "gtk4" "qt" "kcolorscheme" "hyprland" ];
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
          -- on the wallpaper for it.
          background_color = "0xff1c1e1e", -- mSurface
        },
        group = {
          groupbar = {
            -- Hide the bar entirely once expel/consume_or_expel (SUPER+C/X
            -- and SUPER+SHIFT/ALT+2/4/6 above) whittles a group down to its
            -- last window -- a one-tab bar is just clutter at that point.
            disable_when_only = true,
            -- col.active/col.inactive come from the noctalia "hyprland"
            -- template applied above (mSecondary/mSurface), not hardcoded
            -- here.
            -- mOnPrimary/mOnSurfaceVariant, not mOnSecondary/mOnSurface
            -- (the "correct" pair for the template's col.active/inactive
            -- above) -- both still read fine against those, and the
            -- palette doesn't expose text_color as a templated field
            -- anyway.
            text_color = "0xff1c1e1e",          -- mOnPrimary
            text_color_inactive = "0xffbbc2cf", -- mOnSurfaceVariant
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
