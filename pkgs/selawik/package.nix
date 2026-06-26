{
  lib,
  stdenvNoCC,
  fetchzip,
}:
# microsoft's open-source, metric-compatible clone of segoe ui. the upstream
# repo ships ufo source only, so pull the prebuilt ttfs from the 1.01 release.
stdenvNoCC.mkDerivation {
  pname = "selawik";
  version = "1.01";
  src = fetchzip {
    url = "https://github.com/microsoft/Selawik/releases/download/1.01/Selawik_Release.zip";
    hash = "sha256-BbjXJ8HFXrRklMOnGXyZIZeQ5Oksda4AqQXHmNqN6AQ=";
    stripRoot = false;
  };
  installPhase = ''
    runHook preInstall
    install -Dm644 *.ttf -t $out/share/fonts/truetype
    runHook postInstall
  '';
  meta = {
    description = "Open-source metric-compatible clone of Segoe UI";
    homepage = "https://github.com/microsoft/Selawik";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
