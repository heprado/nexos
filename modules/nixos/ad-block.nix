{ ... }:
{
  # System-wide blocking through /etc/hosts: StevenBlack's unified list
  # (adware + malware, ~85k domains) pointed at 0.0.0.0. No daemon, so
  # nothing to keep running, and every program goes through it -- mostly
  # useful outside the browser, cutting the telemetry/tracking apps and
  # games send in the background and known malware domains. In Helium,
  # its built-in uBlock Origin already does this and more (it can't touch
  # YouTube's ads either: they come from the video's own servers).
  #
  # A site or app that breaks because of it: add the domain to `whitelist`.
  networking.stevenblack = {
    enable = true;
    # Fake-news sites and gambling on top of the base list. `social` (it
    # takes the social networks down whole, not just their ads) and `porn`
    # stay off.
    block = [ "fakenews" "gambling" ];
    whitelist = [ ];
  };
}
