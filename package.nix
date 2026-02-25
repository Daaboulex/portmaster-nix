{ lib
, stdenv
, fetchurl
}:

stdenv.mkDerivation rec {
  pname = "portmaster-start";
  version = "1.6.20";

  src = fetchurl {
    url = "https://updates.safing.io/latest/linux_amd64/start/portmaster-start";
    hash = "sha256-xneMV5+tao0l+QTqmGPRj7aQWFr8T5LEWhortDYmL1g=";
  };

  dontUnpack = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/portmaster-start
    runHook postInstall
  '';

  meta = with lib; {
    description = "Portmaster Privacy Application — bootstrap binary";
    homepage = "https://safing.io/portmaster";
    license = licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "portmaster-start";
  };
}
