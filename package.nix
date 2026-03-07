{
  lib,
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
  pkg-config,
  makeBinaryWrapper,
  nodejs,
  glib,
  glib-networking,
  gsettings-desktop-schemas,
  gtk3,
  cairo,
  pango,
  gdk-pixbuf,
  atk,
  webkitgtk_4_1,
  libsoup_3,
  openssl,
  curl,
  systemdLibs,
  iptables,
  iproute2,
  libx11,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxrender,
  libxtst,
  libxrandr,
  libxscrnsaver,
  libxcb,
  alsa-lib,
  nss,
  nspr,
  at-spi2-atk,
  cups,
  dbus,
  expat,
  fontconfig,
  freetype,
  zlib,
  libayatana-appindicator,
  zip,
  rustPlatform,
  wrapGAppsHook4,
  librsvg,
  makeDesktopItem,
  copyDesktopItems,
  autoPatchelfHook,
  systemd,
}:

let
  version = "2.1.7";

  src = fetchFromGitHub {
    owner = "safing";
    repo = "portmaster";
    tag = "v${version}";
    hash = "sha256-DUDfeSdIH3e5yx1KKW6h6+HKKQ3WNllsdairjAkTdJs=";
  };

  # Angular web UI — served by the Tauri desktop app and portmaster-core's web server
  portmasterUI = buildNpmPackage {
    pname = "portmaster-ui";
    inherit version src;

    sourceRoot = "${src.name}/desktop/angular";
    npmDepsHash = "sha256-yoEGoeXcJIGjjD+r+dQoAdeY7mX3VWOt3LAAO+B0bhA=";

    buildPhase = ''
      runHook preBuild
      npm run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r dist/* $out/
      runHook postInstall
    '';

    dontFixup = true;
  };

  # Tauri desktop app — native WebKitGTK window embedding the Angular UI
  portmasterDesktop = rustPlatform.buildRustPackage {
    pname = "portmaster-desktop";
    inherit version src;

    sourceRoot = "${src.name}/desktop/tauri/src-tauri";
    cargoHash = "sha256-q3kgXM06yEuEf+VyywpCHmUGt43RRdSFzTaVlU/jfjc=";

    nativeBuildInputs = [
      pkg-config
      wrapGAppsHook4
    ];

    buildInputs = [
      glib
      glib-networking
      gsettings-desktop-schemas
      gtk3
      cairo
      pango
      gdk-pixbuf
      atk
      webkitgtk_4_1
      libsoup_3
      openssl
      librsvg
    ];

    # Prevent wrapGAppsHook4 from wrapping — the outer buildGoModule handles all wrapping
    dontWrapGApps = true;

    preBuild = ''
      mkdir -p angular/dist/tauri-builtin
      ln -s ${portmasterUI}/* angular/dist/tauri-builtin/
      substituteInPlace tauri.conf.json5 \
        --replace-fail '"../../angular/dist/tauri-builtin"' '"../angular/dist/tauri-builtin"'

      # Fix hardcoded FHS paths for NixOS:
      # Upstream checks /sbin/systemctl etc. — none exist on NixOS.
      # Replace each path individually to avoid multiline quoting issues.
      substituteInPlace src/service/systemd.rs \
        --replace-fail '"/sbin/systemctl",'     '"${systemd}/bin/systemctl",' \
        --replace-fail '"/bin/systemctl",'      '/* removed */' \
        --replace-fail '"/usr/sbin/systemctl",' '/* removed */' \
        --replace-fail '"/usr/bin/systemctl",'  '/* removed */' \
        --replace-fail '"/usr/bin/pkexec"'      '"/run/wrappers/bin/pkexec"' \
        --replace-fail '"/usr/bin/gksudo"'      '"/run/wrappers/bin/gksudo"'
    '';

    env = {
      TAURI_KEY_PASSWORD = "";
      TAURI_PRIVATE_KEY = "";
    };

    doCheck = false;
  };

in
buildGoModule {
  pname = "portmaster";
  inherit version src;

  vendorHash = "sha256-uPo1tRUfl4kY1sMlLoc0y6ctygRN5MJPrR5TTgERk6U=";

  nativeBuildInputs = [
    pkg-config
    makeBinaryWrapper
    nodejs
    zip
    copyDesktopItems
    autoPatchelfHook
  ];

  buildInputs = [
    glib
    gtk3
    cairo
    pango
    gdk-pixbuf
    atk
    webkitgtk_4_1
    libsoup_3
    openssl
    curl
    systemdLibs
    libx11
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrender
    libxtst
    libxrandr
    libxscrnsaver
    libxcb
    alsa-lib
    nss
    nspr
    at-spi2-atk
    cups
    dbus
    expat
    fontconfig
    freetype
    zlib
    libayatana-appindicator
  ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/safing/portmaster/base/info.version=${version}"
    "-X github.com/safing/portmaster/base/info.commit=nixpkgs"
  ];

  subPackages = [ "cmds/portmaster-core" ];

  doCheck = false;

  desktopItems = [
    (makeDesktopItem {
      name = "portmaster";
      exec = "portmaster --data /var/lib/portmaster";
      icon = "portmaster";
      desktopName = "Portmaster";
      comment = "Free and open-source application firewall";
      categories = [ "Network" "Security" ];
      startupNotify = false;
      terminal = false;
    })
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/portmaster \
      $out/share/icons/hicolor/96x96/apps

    # Core firewall engine (Go)
    install -m755 $GOPATH/bin/portmaster-core $out/lib/portmaster/

    # Desktop app (Rust/Tauri)
    install -m755 ${portmasterDesktop}/bin/* $out/lib/portmaster/portmaster

    # Web UI assets
    mkdir -p $out/lib/portmaster/ui/modules/portmaster
    cp -r ${portmasterUI}/* $out/lib/portmaster/ui/modules/portmaster/

    # Zipped UI for portmaster-core's built-in web server
    pushd ${portmasterUI}
    zip -r $out/lib/portmaster/portmaster.zip .
    popd

    # Zipped assets — zip from assets/data/ to match upstream structure
    # (upstream zip has img/flags/DE.png, NOT data/img/flags/DE.png)
    pushd assets/data
    zip -r $out/lib/portmaster/assets.zip .
    popd

    # Icon
    install -Dm644 assets/data/favicons/favicon-96x96.png \
      $out/share/icons/hicolor/96x96/apps/portmaster.png

    # Symlinks for PATH
    ln -s $out/lib/portmaster/portmaster-core $out/bin/portmaster-core
    ln -s $out/lib/portmaster/portmaster $out/bin/portmaster

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/lib/portmaster/portmaster-core" \
      --prefix PATH : ${lib.makeBinPath [ iptables iproute2 ]}

    wrapProgram "$out/lib/portmaster/portmaster" \
      --prefix PATH : ${lib.makeBinPath [ iptables iproute2 systemd ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libayatana-appindicator ]} \
      --prefix GIO_EXTRA_MODULES : "${glib-networking}/lib/gio/modules" \
      --prefix XDG_DATA_DIRS : "${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}" \
      --set-default GDK_BACKEND "wayland,x11" \
      --set WEBKIT_DISABLE_COMPOSITING_MODE "1" \
      --set WEBKIT_DISABLE_DMABUF_RENDERER "1"
  '';

  meta = {
    description = "Free and open-source application firewall";
    homepage = "https://safing.io/portmaster/";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "portmaster";
  };
}
