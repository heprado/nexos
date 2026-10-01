{ config, lib, ... }:
{
  # Unfree packages are allowed one by one rather than all at once. Each
  # module adds the names it needs next to where it uses them (e.g.
  # gaming.nix adds steam), so the list follows whatever a host imports.
  options.nexos.unfree = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "steam" "steam-unwrapped" ];
    description = ''
      Unfree packages to allow, by `lib.getName` (the name without its
      version). home-manager uses the system's pkgs (useGlobalPkgs), so
      this covers henrique's home packages too.
    '';
  };

  config.nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) config.nexos.unfree;
}
