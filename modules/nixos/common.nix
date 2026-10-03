{ inputs, pkgs, self, ... }:
{
  # What every host (caixa, marvin) shares. machines/<name>/configuration.nix
  # only keeps what's specific to that machine.
  imports = [
    ./unfree.nix
    ./docker-rootless.nix
    ./ssh.nix
    ./desktop-hyprland.nix
    ./chrony.nix
    ./session-stop-timeout.nix
    ./take-monitor.nix
    ../../users/henrique
  ];

  # Noctalia isn't in the official nixpkgs cache; without this, its
  # Quickshell/Qt dependencies get compiled from source on every rebuild.
  nix.settings = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
    # So `nix flake ...`/`nix build ...` etc. work without having to pass
    # --extra-experimental-features "nix-command flakes" every time.
    experimental-features = [ "nix-command" "flakes" ];
  };

  # Short alias for this flake itself, so the per-language devShell
  # templates (see flake.nix's `templates` output) can be pulled with
  # `nix flake init -t nexos#rust` instead of the full repo path.
  nix.registry.nexos.flake = self;

  programs.zsh.enable = true;

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

  # Backend dconf needs to actually apply GTK theme settings (see
  # modules/home/hyprland.nix's dconf.settings for henrique's GTK theme).
  programs.dconf.enable = true;

  nixpkgs.overlays = [ inputs.helium-flake.overlays.default ];

  # Which boot loader gets installed (plain systemd-boot, or lanzaboote's
  # signed one) is up to each host; these apply to both.
  #
  # The default console mode ("keep") reuses whatever the firmware left set
  # up, which can be just one of the connected monitors (on marvin, the
  # laptop panel only). Asking for a mode explicitly is an attempt to get
  # the firmware to set it on every console it knows about.
  boot.loader.systemd-boot.consoleMode = "auto";
  boot.loader.efi.canTouchEfiVariables = true;

  # Unset, this falls back to nixpkgs' own default kernel package set,
  # which tracks an older/more conservative version (6.18) even on
  # nixpkgs-unstable -- linuxPackages_latest is what actually follows the
  # newest kernel release packaged for this channel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  home-manager.users.henrique.imports = [ ../../users/henrique/home.nix ];

  # Generate on each host with `age-keygen`, then record the public key in
  # .sops.yaml at the repo root as that host's recipient. See
  # secrets/README.md.
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
}
