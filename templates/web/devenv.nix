{ pkgs, ... }:
{
  languages.javascript.enable = true;
  languages.typescript.enable = true;

  packages = with pkgs; [
    eslint
    prettier
  ];

  # Uncomment if this project needs a local Postgres:
  # services.postgres.enable = true;
}
