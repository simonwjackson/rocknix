{ alsa-ucm-conf, stdenvNoCC }:

stdenvNoCC.mkDerivation {
  pname = "ayn-odin2-ucm";
  version = "2026-05-11";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/alsa/ucm2
    cp -a ${alsa-ucm-conf}/share/alsa/ucm2/. $out/share/alsa/ucm2/
    chmod -R u+w $out/share/alsa/ucm2
    cp -a ${./ucm2}/. $out/share/alsa/ucm2/

    runHook postInstall
  '';

  meta.description = "AYN Odin2 ALSA UCM2 policy layered onto alsa-ucm-conf";
}
