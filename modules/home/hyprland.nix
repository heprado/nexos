{ inputs, pkgs, ... }:
{
  imports = [ inputs.noctalia.homeModules.default ];

  programs.foot.enable = true;

  # GTK/Qt theming backends the noctalia gtk3/gtk4/qt/kcolorscheme
  # templates above actually need to take effect app-wide.
  # See <https://docs.noctalia.dev/v5/templates/official/gtk-qt/>.
  home.packages = [ pkgs.adw-gtk3 pkgs.nwg-look pkgs.qt6Packages.qt6ct ];
  home.sessionVariables.QT_QPA_PLATFORMTHEME = "qt6ct";
  dconf.settings."org/gnome/desktop/interface".gtk-theme = "adw-gtk3";

  # Launched from Hyprland's Lua config itself (hl.on("hyprland.start", ...)
  # below), per <https://docs.noctalia.dev/v5/compositor-settings/hyprland/>
  # — not via systemd.enable, to avoid starting it twice.
  programs.noctalia = {
    enable = true;
    systemd.enable = false;
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
        builtin_ids = [ "gtk3" "gtk4" "qt" "kcolorscheme" ];
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
      hl.on("hyprland.start", function()
        hl.exec_cmd("noctalia")
      end)

      hl.monitor({ output = "", mode = "highrr", position = "auto", scale = "auto" })

      hl.config({
        general = {
          layout = "scrolling",
        },
        input = {
          kb_layout = "br",
        },
      })

      local mainMod = "SUPER"
      hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("foot"))
      hl.bind(mainMod .. " + Q", hl.dsp.window.close())
      hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
      hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
      hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
      hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

      -- Scroll wheel moves focus between windows in the scrolling layout
      -- (not bound by the layout itself -- see
      -- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/#layout-messages).
      hl.bind(mainMod .. " + mouse_down", hl.dsp.layout("focus r"))
      hl.bind(mainMod .. " + mouse_up", hl.dsp.layout("focus l"))
    '';
  };
}
