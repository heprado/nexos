{ config, pkgs, ... }:
let
  # Store path names (after the hash) that count as PHP: the interpreter
  # and its extensions/packages (php-8.3.x, php83-..., php-redis-...),
  # composer, and the PHP web apps nixpkgs ships as plain source copies.
  phpPattern =
    "^/nix/store/[0-9a-z]{32}-(php[0-9]*(-|$)|composer-|wordpress|mediawiki|roundcube|dokuwiki|nextcloud|freshrss)";

  # Everything installed (system + Home Manager, via the
  # home-manager-<user> unit in /etc) and every service's runtime deps.
  # Taken from system.path and /etc rather than the toplevel, since the
  # toplevel depends on system.checks and would make this circular.
  closure = pkgs.closureInfo {
    rootPaths = [ config.system.path config.system.build.etc ];
  };
in
{
  # No overlay that throws on pkgs.php & co.: nixpkgs' own manual reads
  # pkgs.php.services.default while building the docs, so that would break
  # every build. Checking the closure also catches PHP from flake inputs
  # with their own nixpkgs and from apps not named php*.
  #
  # Fail the system build if any PHP store path made it into
  # the closure anyway, whatever its origin.
  system.checks = [
    (pkgs.runCommand "nexos-no-php-check" { } ''
      if found=$(grep -E '${phpPattern}' ${closure}/store-paths); then
        echo "PHP is blocked by nexos policy, but the closure contains:" >&2
        echo "$found" >&2
        exit 1
      fi
      touch $out
    '')
  ];
}
