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
