{ pkgs, ... }:
let
  warmNixpkgsCache = pkgs.writeShellApplication {
    name = "nexos-nixpkgs-cache-warm";
    runtimeInputs = [ pkgs.coreutils pkgs.git pkgs.nix pkgs.util-linux ];
    text = ''
      cd /home/henrique/codigos/nexos

      # Prevent overlapping instances of this scheduled job.
      exec 9>"''${XDG_RUNTIME_DIR:?}/nexos-nixpkgs-cache-warm.lock"
      flock --nonblock 9 || exit 0

      nix flake update nixpkgs
      install -d /home/henrique/.local/state/nix/profiles
      nix build \
        --profile /home/henrique/.local/state/nix/profiles/nexos-master-cache \
        .#nixosConfigurations.marvin.config.system.build.toplevel
    '';
  };
in
{
  # GUI half of henrique's home config, only on hosts that import
  # modules/nixos/desktop-hyprland.nix.
  imports = [
    ../../modules/home/chat.nix
    ../../modules/home/design.nix
    ../../modules/home/reading.nix
    ../../modules/home/hyprland.nix
    ../../modules/home/helium.nix
    ../../modules/home/zed.nix
  ];

  # xdg-open is used by GUI apps and development tools to open URLs/files.
  home.packages = [ pkgs.xdg-utils ];

  systemd.user.services.nexos-nixpkgs-cache-warm = {
    Unit.Description = "Update nixpkgs master and build Marvin's NixOS closure for cache warming";
    Service = {
      Type = "oneshot";
      ExecStart = "${warmNixpkgsCache}/bin/nexos-nixpkgs-cache-warm";
    };
  };

  systemd.user.timers.nexos-nixpkgs-cache-warm = {
    Unit.Description = "Daily nixpkgs master cache warm for Marvin";
    Timer = {
      OnCalendar = "*-*-* 03:00:00";
      AccuracySec = "1s";
      Persistent = true;
      Unit = "nexos-nixpkgs-cache-warm.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
