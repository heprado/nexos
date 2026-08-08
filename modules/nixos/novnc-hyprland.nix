{ pkgs, ... }:
let
  # pkgs.novnc's webroot has no index.html (only vnc.html), so hitting the
  # bare https://remote.heprado.com.br/ falls through to websockify's
  # static-file directory listing instead of the actual client. Serve a
  # copy of the webroot with an index.html -> vnc.html redirect added.
  novncWebRoot = pkgs.runCommand "novnc-web-root" { } ''
    mkdir -p "$out"
    cp -r ${pkgs.novnc}/share/webapps/novnc/. "$out"/
    ln -s vnc.html "$out"/index.html
  '';
in
{
  # Adds browser-based (HTTPS, no native VNC client needed) access to
  # henrique's Hyprland session, on top of the existing wayvnc (see
  # wayvnc-hyprland.nix) -- wayvnc itself stays exactly as-is and keeps
  # working for native VNC clients (TigerVNC etc) on port 5900.
  #
  # KasmVNC was considered instead but ruled out: it's a fork of TigerVNC's
  # Xvnc, fundamentally an X11 server with no Wayland/wlroots capture
  # support, so it can't attach to a real Hyprland session. websockify +
  # noVNC achieves the same practical goal (a plain HTTPS URL, opened in
  # any browser, no client install) by just proxying WebSocket <-> wayvnc's
  # existing raw VNC TCP port -- wayvnc itself is untouched.
  #
  # TLS is NOT terminated here: the Cloudflare Tunnel already does that
  # (see cloudflared.nix) for the `https://remote.heprado.com.br`
  # hostname -- its Public Hostname ingress needs to point at
  # `http://localhost:6080` (not `tcp://localhost:5900` like before) for
  # this to be reachable through the tunnel.
  systemd.services.novnc-hyprland = {
    description = "noVNC/websockify HTTPS front-end for wayvnc";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      DynamicUser = true;
      ExecStart = "${pkgs.python3Packages.websockify}/bin/websockify --web=${novncWebRoot} 0.0.0.0:6080 localhost:5900";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  # Primary remote path is the Cloudflare Tunnel (loopback, no firewall
  # rule needed). LAN-wide opening kept for direct local browser access,
  # mirroring wayvnc-hyprland.nix's 5900 rule.
  networking.firewall.allowedTCPPorts = [ 6080 ];
}
