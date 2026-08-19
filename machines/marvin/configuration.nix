{ lib, pkgs, self, ... }:
{
  # WSL, not a physical machine -- see flake.nix for the NixOS-WSL module
  # wiring. wsl.defaultUser (below) makes that module create
  # users.users.henrique itself (isNormalUser, wheel, passwordless sudo by
  # default) -- no separate users/henrique/default.nix wiring needed here,
  # unlike caixa's SDDM/console login which does need a real password.
  wsl = {
    enable = true;
    defaultUser = "henrique";
  };
  # NixOS-WSL's auto-created user (see above) doesn't set a shell.
  users.users.henrique.shell = pkgs.zsh;

  # Short alias for this flake itself, so the per-language devShell
  # templates (see flake.nix's `templates` output) can be pulled with
  # `nix flake init -t nexos#rust` instead of the full repo path.
  nix.registry.nexos.flake = self;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking.hostName = "marvin";
  programs.zsh.enable = true;

  i18n.defaultLocale = "pt_BR.UTF-8";
  time.timeZone = "America/Sao_Paulo";

  # claude-code's license is marked "unfree" in nixpkgs; allow just that
  # package rather than unfree packages in general (see the fuller
  # allowlist in machines/caixa/configuration.nix for GUI-app exceptions
  # that don't apply here).
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "claude-code" ];

  home-manager.users.henrique = import ../../users/henrique/home-wsl.nix;

  # Bump to whatever release is current when you actually install; do not
  # change on upgrades.
  system.stateVersion = "24.05";
}
