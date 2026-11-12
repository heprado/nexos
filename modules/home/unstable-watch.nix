{ pkgs, ... }:
let
  # ntfy.sh topic the phone's ntfy app subscribes to. Anyone who knows the
  # name can read or post to it, hence the random suffix; it only ever
  # carries "the channel moved", nothing private.
  topic = "nexos-unstable-f251b797bba9845e";

  # Tells the desktop (notify-send) and the phone (ntfy) each time Hydra
  # advances nixos-unstable, i.e. a new channel release whose packages are
  # in the binary cache -- the moment `nfu` is worth running. The channel
  # URL redirects to its release, named like nixos-26.11pre1113206.f4a03c008967;
  # a different name than last time means it moved. The first run only
  # records the current release.
  unstable-watch = pkgs.writeShellApplication {
    name = "unstable-watch";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.gnugrep pkgs.gnused pkgs.libnotify ];
    text = ''
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/nexos/unstable-release"

      # Offline or channels.nixos.org down: try again on the next tick.
      release=$(curl -fsSI --max-time 30 https://channels.nixos.org/nixos-unstable \
        | grep -i '^location:' | sed -E 's|.*/||; s/\r$//') || exit 0
      [ -n "$release" ] || exit 0

      last=$(cat "$state" 2> /dev/null || true)
      [ "$release" = "$last" ] && exit 0

      mkdir -p "$(dirname "$state")"
      if [ -z "$last" ]; then
        printf '%s\n' "$release" > "$state"
        exit 0
      fi

      version=''${release#nixos-}
      title="nixos-unstable avançou"
      body="''${version%.*} (''${version##*.}). Hora de rodar o nfu."
      click="https://github.com/NixOS/nixpkgs/compare/''${last##*.}...''${version##*.}"

      # Phone first: if ntfy fails the release isn't recorded, so the next
      # tick retries (the desktop may then see it twice).
      curl -fsS --max-time 30 -o /dev/null \
        -H "Title: $title" -H "Click: $click" -H "Tags: snowflake" \
        -d "$body" "https://ntfy.sh/${topic}"
      notify-send --app-name=nexos "$title" "$body" || true

      printf '%s\n' "$release" > "$state"
    '';
  };
in
{
  home.packages = [ unstable-watch ];

  systemd.user.services.unstable-watch = {
    Unit.Description = "Notify when Hydra advances nixos-unstable";
    Service = {
      Type = "oneshot";
      ExecStart = "${unstable-watch}/bin/unstable-watch";
    };
  };

  # Hourly is plenty: the channel moves every day or few. Persistent runs a
  # missed check right after the laptop wakes or boots.
  systemd.user.timers.unstable-watch = {
    Unit.Description = "Check nixos-unstable hourly";
    Timer = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
