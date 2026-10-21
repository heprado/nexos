{ ... }:
{
  # Refuse PHP packages at evaluation time, including packages pulled in
  # transitively through Nixpkgs. This applies to both system and
  # Home Manager packages because home-manager.useGlobalPkgs is enabled.
  nixpkgs.overlays = [
    (final: prev:
      let
        blocked = name:
          builtins.match "php.*" name != null || name == "composer";
        blockedNames = builtins.filter blocked (builtins.attrNames prev);
      in
      builtins.listToAttrs (map (name: {
        inherit name;
        value = throw "PHP package '${name}' is blocked by nexos policy";
      }) blockedNames))
  ];
}
