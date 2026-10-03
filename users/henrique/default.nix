{ config, pkgs, ... }:
{
  sops.secrets.henrique_password_hash = {
    neededForUsers = true;
  };

  # Lets prebuilt, non-Nix-patched Linux binaries run unmodified (e.g. the
  # Xtensa Rust toolchain espup downloads for ESP32 dev in ~/codigos/clipesp) --
  # NixOS has no /lib64/ld-linux... for their hardcoded ELF interpreter to find.
  programs.nix-ld.enable = true;
  # projectMSDL (github.com/projectM-visualizer/frontend-sdl-cpp release
  # tarball, used by noctalia-song-visualizer) is one such prebuilt binary --
  # `ldd` on it reports these three missing alongside libstdc++, which the
  # module already provides by default.
  programs.nix-ld.libraries = with pkgs; [ SDL2 freetype libglvnd ];

  # Unfree packages in henrique's home (modules/home/ai.nix's claude-code).
  # home-manager uses the system's pkgs, so it's allowed here (see
  # modules/nixos/unfree.nix).
  nexos.unfree = [ "claude-code" ];

  # Profile picture for the login screen: noctalia-greeter shows each
  # user's AccountsService IconFile, read as the "greeter" user. With none
  # set, AccountsService reports ~/.face, which the greeter can't read
  # (home is 0700), so it fell back to a generic icon. Same picture as
  # Noctalia's own avatar (~/.face, modules/home/hyprland.nix).
  systemd.tmpfiles.rules = [
    "L+ /var/lib/AccountsService/icons/henrique - - - - ${./user-profile.jpg}"
    "f+ /var/lib/AccountsService/users/henrique 0600 root root - [User]\\nIcon=/var/lib/AccountsService/icons/henrique\\nSystemAccount=false\\n"
  ];

  users.users.henrique = {
    isNormalUser = true;
    shell = pkgs.zsh;
    # dialout: rw access to /dev/ttyUSB*/ttyACM* serial devices, needed to
    # flash the ESP32 in ~/codigos/clipesp via espflash/probe-rs.
    extraGroups = [ "wheel" "dialout" ];
    linger = true;
    # Local SDDM/console login password (separate from SSH, which stays
    # key-only). Hash lives in secrets/caixa.yaml under henrique_password_hash.
    hashedPasswordFile = config.sops.secrets.henrique_password_hash.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINNEELZAtcyd/g3y1gPjgSaxLlN5BZPilFzPTX6UTS2B henrique@caixa"
      # PLACEHOLDER -- replace with the real public key once it's
      # generated for/on marvin.
      "ssh-ed25519 PLACEHOLDER_REPLACE_WITH_REAL_KEY henrique@marvin"
    ];
  };
}
