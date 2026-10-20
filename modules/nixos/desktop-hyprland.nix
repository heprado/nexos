{ config, inputs, lib, pkgs, ... }:
{
  # Everything graphical, for the hosts that have a desktop at all (marvin;
  # caixa is terminal-only). Local physical console only (henrique).
  #
  # Uses nixpkgs-unstable's packaged Hyprland (not the upstream git flake)
  # so builds hit the binary cache instead of compiling from source.
  programs.hyprland.enable = true;

  # henrique's GUI home config (Hyprland/Noctalia, browser, chat apps, ...),
  # on top of the terminal one common.nix imports.
  home-manager.users.henrique.imports = [ ../../users/henrique/home-desktop.nix ];

  # Additional binary caches for packages built by their respective projects.
  nix.settings = {
    extra-substituters = [
      "https://noctalia.cachix.org"
      "https://nix-community.cachix.org"
      "https://nixpkgs-wayland.cachix.org"
    ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
    ];
  };

  # pkgs.helium, for modules/home/helium.nix.
  nixpkgs.overlays = [ inputs.helium-flake.overlays.default ];

  # Backend dconf needs to actually apply GTK theme settings (see
  # modules/home/hyprland.nix's dconf.settings for henrique's GTK theme).
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
    settings.session.default = "Hyprland";
    # Same wallpaper as the Hyprland session (see modules/home/hyprland.nix),
    # so the login screen matches. "${...}" copies the file into the Nix
    # store (world-readable) and interpolates its absolute store path --
    # the toml settings attrset needs a plain string here, not a Nix path.
    settings.appearance.wallpaper.path = "${../../users/henrique/217060-kagura-gintama-1920x1080.png}";
    # Same colors as henrique's Noctalia shell: the greeter runs as its own
    # user before login, so it can't read his palette, but it takes the
    # same keys in snake_case without the "m" (mOnSurfaceVariant ->
    # on_surface_variant) -- converted here from customPalettes.henrique in
    # modules/home/hyprland.nix, so that stays the only place colors are
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

  # Recommended by Noctalia (the shell/bar running in henrique's Hyprland
  # session, see modules/home/hyprland.nix) for its network/bluetooth/power
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

  # GUI for pairing/managing devices (agent included, so no more manual
  # `agent on` / `default-agent` dance in bluetoothctl).
  services.blueman.enable = true;

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
  # Noctalia's own avatar (~/.face, modules/home/hyprland.nix).
  systemd.tmpfiles.rules = [
    "L+ /var/lib/AccountsService/icons/henrique - - - - ${../../users/henrique/user-profile.jpg}"
    "f+ /var/lib/AccountsService/users/henrique 0600 root root - [User]\\nIcon=/var/lib/AccountsService/icons/henrique\\nSystemAccount=false\\n"
  ];
}
