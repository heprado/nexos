# Apps2Samsung (github.com/Apps2Samsung/Apps2Samsung): sideloads apps onto
# Samsung Tizen TVs (here, Moonlight-Tizen for the living-room TV), with
# the TV in Developer Mode. Not in nixpkgs; the release's AppImage.
{ appimageTools, fetchurl }:
let
  pname = "apps2samsung";
  version = "2.8.1";
  src = fetchurl {
    url = "https://github.com/Apps2Samsung/Apps2Samsung/releases/download/v${version}/Apps2Samsung-v${version}-linux-x64.AppImage";
    hash = "sha256-jQ1DZgiTQVSL8qCSeLR/HVoFQGGrLAeW/zSjOE+oWhw=";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;
  # It's a .NET app, which won't start without ICU.
  extraPkgs = pkgs: [ pkgs.icu ];
  extraInstallCommands = ''
    install -Dm444 ${contents}/apps2samsung.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/apps2samsung.desktop \
      --replace-fail 'Exec=Apps2Samsung' 'Exec=apps2samsung'
    cp -r ${contents}/usr/share/icons $out/share/
  '';
}
