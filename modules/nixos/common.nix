{ config, lib, pkgs, self, ... }:
{
  # What every host (caixa, marvin) shares -- terminal only. The graphical
  # desktop (desktop-hyprland.nix) and the SSH server (ssh.nix) are
  # imported by the hosts that want them. machines/<name>/configuration.nix
  # only keeps what's specific to that machine.
  imports = [
    ./unfree.nix
    ./docker-rootless.nix
    ./chrony.nix
    ./session-stop-timeout.nix
    ./take-monitor.nix
    ../../users/henrique
  ];

  nix.settings = {
    # So `nix flake ...`/`nix build ...` etc. work without having to pass
    # --extra-experimental-features "nix-command flakes" every time.
    experimental-features = [ "nix-command" "flakes" ];
  };

  # Short alias for this flake itself, so the per-language devShell
  # templates (see flake.nix's `templates` output) can be pulled with
  # `nix flake init -t nexos#rust` instead of the full repo path.
  nix.registry.nexos.flake = self;

  programs.zsh.enable = true;
  
  security.pki.caCertificateBlacklist = [
    "Comodo AAA Services root"
    "emSign ECC Root CA - G3"
  ];

  # `nh clean` runs as a periodic systemd service, and `nh os switch`/etc.
  # (see the `nrs`-style aliases in modules/home/zsh.nix) know which flake
  # to build via NH_OS_FLAKE, set from `flake` below.
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
    flake = "/home/henrique/codigos/nexos";
  };

  i18n.defaultLocale = "pt_BR.UTF-8";
  time.timeZone = "America/Sao_Paulo";

  # ABNT2 keyboard (has ç, /, dead keys, and a numpad) on the text console.
  # The graphical session's layout is set in desktop-hyprland.nix.
  console.keyMap = "br-abnt2";

  # nmcli/nmtui on both hosts, GUI or not (Noctalia's network widget on
  # marvin talks to it too).
  networking.networkmanager.enable = true;

  # Which boot loader gets installed (plain systemd-boot, or lanzaboote's
  # signed one) is up to each host; these apply to both.
  #
  # The default console mode ("keep") reuses whatever the firmware left set
  # up, which can be just one of the connected monitors (on marvin, the
  # laptop panel only). Asking for a mode explicitly is an attempt to get
  # the firmware to set it on every console it knows about.
  boot.loader.systemd-boot.consoleMode = "auto";
  boot.loader.efi.canTouchEfiVariables = true;

  # ZFS must use a kernel supported by its out-of-tree module. Keep the
  # ZFS-root host on 7.2; Btrfs hosts continue following the latest kernel.
  boot.kernelPackages =
    if config.fileSystems."/".fsType == "zfs"
    then pkgs.linuxPackages_7_2
    else pkgs.linuxPackages_latest;

  # Terminal-only home config; desktop-hyprland.nix adds the GUI half.
  home-manager.users.henrique.imports = [ ../../users/henrique/home.nix ];

  # Generate on each host with `age-keygen`, then record the public key in
  # .sops.yaml at the repo root as that host's recipient. See
  # secrets/README.md.
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
}
