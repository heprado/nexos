{ lib, ... }:
{
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };

  # The rootless module's user service is wanted by every user's
  # default.target, including the greeter's (greetd runs a systemd --user
  # for it), where it fails 3x per boot on "No subuid ranges found for user
  # 999 (greeter)". Only start it for regular (non-system) users; this
  # replaces the module's own "!root", which @system already covers.
  systemd.user.services.docker.unitConfig.ConditionUser = lib.mkForce "!@system";
}
