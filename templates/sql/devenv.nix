{ pkgs, ... }:
{
  packages = with pkgs; [
    sqls
  ];

  services.postgres = {
    enable = true;
    initialDatabases = [ { name = "app"; } ];
  };
}
