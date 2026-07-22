{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation {
  pname = "apple-color-emoji";
  version = "macos-26-20260722-484daf4e";
  src = fetchurl {
    url = "https://github.com/samuelngs/apple-emoji-ttf/releases/download/macos-26-20260722-484daf4e/AppleColorEmoji-Linux.ttf";
    hash = "sha256-43x69iZaxKCvbVe8ZehhCad22ZZug0MzRVf2PaSCUW8=";
  };
  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    install -D $src $out/share/fonts/truetype/AppleColorEmoji-Linux.ttf
    runHook postInstall
  '';
  passthru.updateScript = ./update.sh;
  meta = {
    description = "Apple Color Emoji repacked as CBDT/CBLC for Linux";
    homepage = "https://github.com/samuelngs/apple-emoji-ttf";
    license = lib.licenses.unfreeRedistributable;
    platforms = lib.platforms.linux;
  };
}
