{ config, pkgs, ... }:
{
  sops.secrets.henrique_password_hash = {
    neededForUsers = true;
  };

  # Lets prebuilt, non-Nix-patched Linux binaries run unmodified (e.g. the
  # Xtensa Rust toolchain espup downloads for ESP32 dev in ~/codigos/clipesp) --
  # NixOS has no /lib64/ld-linux... for their hardcoded ELF interpreter to find.
  programs.nix-ld.enable = true;

  # With nobody in wheel, polkit's default admin (unix-group:wheel) would be
  # an empty set and every auth_admin prompt (run0, pkexec, nrt/nrs through
  # run0) would fail outright; ask for root's password instead.
  security.polkit.adminIdentities = [ "unix-user:0" ];

  nexos.unfree = [ "claude-code" ];
  users.users.henrique = {
    isNormalUser = true;
    shell = pkgs.bashInteractive;
    # dialout: rw access to /dev/ttyUSB*/ttyACM* serial devices, needed to
    # flash the ESP32 in ~/codigos/clipesp via espflash/probe-rs.
    # Deliberately NOT in wheel: no sudo, so nothing running as henrique
    # (a project's dependencies, an agent) can ride a cached sudo ticket.
    # Root is reached with `su` or run0, both asking root's password.
    extraGroups = [ "dialout" ];
    linger = true;
    # Local SDDM/console login password (separate from SSH, which stays
    # key-only). Hash lives in secrets/caixa.yaml under henrique_password_hash.
    hashedPasswordFile = config.sops.secrets.henrique_password_hash.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINNEELZAtcyd/g3y1gPjgSaxLlN5BZPilFzPTX6UTS2B henrique@caixa"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqRQluhE032/ZGjKl69cxqo07F0jqUb8/OJ969EEygB henrique@marvin"
    ];
  };
}
