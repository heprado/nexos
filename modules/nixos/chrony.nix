{ ... }:
{
  # System-wide (not per-user -- there's no such thing as per-user NTP), so
  # every user on the machine gets their clock from NIC.br instead of the
  # default systemd-timesyncd. See <https://ntp.br/guia/linux/#chrony>.
  services.chrony = {
    enable = true;
    servers = [
      "a.st1.ntp.br"
      "b.st1.ntp.br"
      "c.st1.ntp.br"
      "d.st1.ntp.br"
      "e.st1.ntp.br"
      "gps.nu.ntp.br"
      "gps.jd.ntp.br"
      "gps.ce.ntp.br"
    ];
    # Appends "nts" to every server line above and wires up ntsdumpdir --
    # NIC.br's servers support Network Time Security.
    enableNTS = true;
    makestep = {
      threshold = 1;
      limit = 3;
    };
    # enableRTCTrimming defaults to true and is chrony's newer, more precise
    # replacement for the guide's plain `rtcsync` directive -- the NixOS
    # module asserts against combining the two, so this intentionally
    # diverges from the guide's literal config rather than fighting it.
    extraConfig = ''
      leapsectz right/UTC
      maxupdateskew 100.0
    '';
  };
}
