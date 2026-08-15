{ pkgs, ... }:
{
  # Zed, wrapped so the launch command is `IDE` instead of `zeditor`.
  home.packages = [
    (pkgs.symlinkJoin {
      name = "zed-editor-ide";
      paths = [ pkgs.zed-editor ];
      postBuild = ''
        ln -s ${pkgs.zed-editor}/bin/zeditor $out/bin/IDE
      '';
    })
  ];
}
