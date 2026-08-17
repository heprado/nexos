{ pkgs, ... }:
{
  languages.python.enable = true;

  packages = with pkgs; [
    basedpyright
    ruff
  ];

  # Uncomment if this project needs a local Postgres:
  # services.postgres.enable = true;
  # services.postgres.initialDatabases = [ { name = "app"; } ];
}
