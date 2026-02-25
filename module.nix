{ config, lib, pkgs, ... }:

let
  cfg = config.services.portmaster;

  # Runtime libraries needed by Portmaster's Electron-based UI
  # (portmaster-start downloads and self-updates these binaries)
  commonLibs = lib.makeLibraryPath [
    pkgs.glibc pkgs.openssl pkgs.zlib pkgs.libffi pkgs.glib pkgs.gtk3
    pkgs.nss pkgs.nspr pkgs.dbus pkgs.expat pkgs.cups pkgs.alsa-lib
    pkgs.libdrm pkgs.libgbm pkgs.mesa pkgs.libxkbcommon pkgs.pango pkgs.cairo
    pkgs.atk pkgs.at-spi2-core
    pkgs.libx11 pkgs.libxext pkgs.libxrandr pkgs.libxfixes pkgs.libxcomposite
    pkgs.libxdamage pkgs.libxcb pkgs.systemd pkgs.libxshmfence pkgs.libglvnd
    pkgs.brotli pkgs.libdatrie pkgs.libxml2 pkgs.json-glib pkgs.libjpeg
    pkgs.bzip2 pkgs.graphite2
    pkgs.libxinerama pkgs.libxcursor pkgs.libcap pkgs.gmp pkgs.nettle
    pkgs.libtasn1 pkgs.libunistring pkgs.libidn2 pkgs.p11-kit
    pkgs.libxdmcp pkgs.libxau pkgs.libxrender
    pkgs.freetype pkgs.libpng pkgs.libthai pkgs.libxi pkgs.libepoxy
    pkgs.fribidi pkgs.fontconfig pkgs.harfbuzz pkgs.gnutls pkgs.avahi
    pkgs.libselinux pkgs.pcre2 pkgs.libuv pkgs.tinysparql
    pkgs.stdenv.cc.cc.lib
  ];

  glibcInterp = "${pkgs.glibc}/lib/ld-linux-x86-64.so.2";

  chromiumLibPath = lib.makeLibraryPath [
    pkgs.ungoogled-chromium
  ];

  # Full LD_LIBRARY_PATH for all portmaster processes
  fullLibPath = "${commonLibs}:${chromiumLibPath}:/run/opengl-driver/lib";

  icon = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/safing/portmaster-packaging/master/linux/portmaster_logo.png";
    sha256 = "0mx9j9xchbv84fa9rz04jqmpq8hy7hv64dxmsf3az515jljjdc7c";
  };

  # Wayland flags for Electron-based apps (prevents SIGSEGV on Wayland sessions)
  waylandFlags = "--enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform=wayland";

  # Wrapper creator — wraps Electron binaries so Wayland flags are passed
  # directly to the Electron/Chromium process, not through portmaster-start
  wrapElectron = pkgs.writeShellScript "portmaster-wrap-electron" ''
    DATA_DIR="${cfg.dataDir}"
    if [ -d "$DATA_DIR/updates/linux_amd64/app" ]; then
      find "$DATA_DIR/updates/linux_amd64/app" -name 'portmaster-app_*' -type f -perm -111 ! -name '*.real' ! -name '*.sig' -print0 | while IFS= read -r -d $'\0' bin; do
        # Skip if already wrapped
        [ -f "$bin.real" ] && continue
        # Skip if it's a shell script (already a wrapper)
        head -c 2 "$bin" | grep -q '#!' && continue
        mv "$bin" "$bin.real"
        cat > "$bin" << WRAPPER
#!/bin/sh
WAYLAND_ARGS=""
if [ "\$XDG_SESSION_TYPE" = "wayland" ]; then
  WAYLAND_ARGS="${waylandFlags}"
fi
exec "\$(dirname "\$0")/\$(basename "\$0").real" \$WAYLAND_ARGS "\$@"
WRAPPER
        chmod +x "$bin"
      done
    fi
  '';

  # Binary patcher — Portmaster self-updates its binaries, which need
  # NixOS-specific ELF interpreter and rpath patching to run
  patchBins = pkgs.writeShellScript "portmaster-patch-binaries" ''
    DATA_DIR="${cfg.dataDir}"
    if [ -d "$DATA_DIR/updates" ]; then
      find "$DATA_DIR/updates" -type f -perm -111 ! -name '*.sig' ! -name '*.real' -print0 | while IFS= read -r -d $'\0' bin; do
        # Skip shell script wrappers
        head -c 2 "$bin" | grep -q '#!' && continue
        ${pkgs.patchelf}/bin/patchelf \
          --set-interpreter "${glibcInterp}" \
          --set-rpath "\$ORIGIN:${fullLibPath}" \
          "$bin" 2>/dev/null || true
      done
    fi
    if [ -f "$DATA_DIR/portmaster-start" ]; then
      ${pkgs.patchelf}/bin/patchelf \
        --set-interpreter "${glibcInterp}" \
        --set-rpath "\$ORIGIN:${fullLibPath}" \
        "$DATA_DIR/portmaster-start" 2>/dev/null || true
    fi
    # Wrap Electron app binaries with Wayland flags
    ${wrapElectron}
  '';

  # Ensure libffmpeg.so is available (needed by Electron UI)
  linkFfmpeg = pkgs.writeShellScript "portmaster-link-ffmpeg" ''
    DATA_DIR="${cfg.dataDir}"
    [ -f "$DATA_DIR/libffmpeg.so" ] && exit 0
    for p in \
      "${pkgs.ungoogled-chromium}/lib/libffmpeg.so" \
      "${pkgs.ungoogled-chromium}/lib/chromium/libffmpeg.so" \
      "${pkgs.ungoogled-chromium}/libexec/chromium/libffmpeg.so"; do
      if [ -f "$p" ]; then
        ln -sf "$p" "$DATA_DIR/libffmpeg.so"
        break
      fi
    done
  '';

  # UI wrapper
  appWrapper = pkgs.writeShellScriptBin "portmaster-ui" ''
    export LD_LIBRARY_PATH="${fullLibPath}"
    export ELECTRON_OZONE_PLATFORM_HINT=auto
    mkdir -p "${cfg.dataDir}/logs/start" "${cfg.dataDir}/logs/app" 2>/dev/null || true
    exec "${cfg.dataDir}/portmaster-start" app --data "${cfg.dataDir}" "$@"
  '';

  # Notifier/tray wrapper — sets LD_LIBRARY_PATH so child processes
  # (like "Open App") also inherit the correct library paths
  notifierWrapper = pkgs.writeShellScriptBin "portmaster-notifier" ''
    export LD_LIBRARY_PATH="${fullLibPath}"
    export ELECTRON_OZONE_PLATFORM_HINT=auto
    mkdir -p "${cfg.dataDir}/logs/start" "${cfg.dataDir}/logs/app" 2>/dev/null || true
    exec "${cfg.dataDir}/portmaster-start" notifier --data "${cfg.dataDir}" "$@"
  '';

  desktopItem = pkgs.makeDesktopItem {
    name = "portmaster";
    desktopName = "Portmaster";
    exec = "${appWrapper}/bin/portmaster-ui";
    terminal = false;
    categories = [ "Network" "Security" ];
    icon = icon;
  };

in {
  options.services.portmaster = {
    enable = lib.mkEnableOption "Portmaster privacy firewall";

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/opt/safing/portmaster";
      description = "Directory where Portmaster stores its data and self-updated binaries";
    };

    ui = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the Portmaster UI (Electron app) as a user service";
      };
    };

    notifier = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the Portmaster system tray notifier as a user service";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # ──────────────────────────────────────────────────────────────────────
    # Core firewall service (runs as root)
    # ──────────────────────────────────────────────────────────────────────
    systemd.services.portmaster-core = {
      description = "Portmaster Core Firewall";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.iptables pkgs.nftables pkgs.iproute2 pkgs.coreutils ];

      serviceConfig = {
        Type = "simple";
        User = "root";

        ExecStartPre = [
          # Clean up stale iptables chains from previous runs
          "${pkgs.bash}/bin/bash -c '${pkgs.iptables}/bin/iptables -F C17 2>/dev/null || true; ${pkgs.iptables}/bin/iptables -F C170 2>/dev/null || true; ${pkgs.iptables}/bin/iptables -t nat -F C17 2>/dev/null || true'"
          # Bootstrap: copy start binary, run self-update, patch binaries, link ffmpeg
          (let script = pkgs.writeShellScript "portmaster-bootstrap" ''
            set -e
            mkdir -p "${cfg.dataDir}"
            if [ ! -x "${cfg.dataDir}/portmaster-start" ]; then
              cp "${pkgs.portmaster-start}/bin/portmaster-start" "${cfg.dataDir}/portmaster-start"
              chmod a+x "${cfg.dataDir}/portmaster-start"
            fi
            "${cfg.dataDir}/portmaster-start" --data "${cfg.dataDir}" update
            ${patchBins}
            ${linkFfmpeg}
          ''; in "${script}")
        ];

        ExecStart = ''"${cfg.dataDir}/portmaster-start" core --data "${cfg.dataDir}"'';

        # Clean up iptables rules on stop
        ExecStopPost = "${pkgs.bash}/bin/bash -c '${pkgs.iptables}/bin/iptables -F 2>/dev/null || true; ${pkgs.iptables}/bin/iptables -X 2>/dev/null || true; ${pkgs.iptables}/bin/iptables -t nat -F 2>/dev/null || true; ${pkgs.iptables}/bin/iptables -t nat -X 2>/dev/null || true; ${pkgs.iptables}/bin/iptables -t mangle -F 2>/dev/null || true; ${pkgs.iptables}/bin/iptables -t mangle -X 2>/dev/null || true; rm -f ${cfg.dataDir}/core-lock.pid 2>/dev/null || true'";

        Restart = "on-failure";
        RestartSec = 10;
        TimeoutStartSec = "10m";
        TimeoutStopSec = "30s";
      };
    };

    # ──────────────────────────────────────────────────────────────────────
    # UI app (user service, optional)
    # ──────────────────────────────────────────────────────────────────────
    systemd.user.services.portmaster-app = lib.mkIf cfg.ui.enable {
      description = "Portmaster UI";
      after = [ "graphical-session.target" ];
      environment = {
        LD_LIBRARY_PATH = fullLibPath;
        ELECTRON_OZONE_PLATFORM_HINT = "auto";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${appWrapper}/bin/portmaster-ui";
        Restart = "on-failure";
      };
    };

    # ──────────────────────────────────────────────────────────────────────
    # System tray notifier (user service, optional)
    # The LD_LIBRARY_PATH in Environment ensures child processes (like
    # "Open App") also inherit the correct library paths.
    # ──────────────────────────────────────────────────────────────────────
    systemd.user.services.portmaster-notifier = lib.mkIf cfg.notifier.enable {
      description = "Portmaster Tray Notifier";
      wantedBy = [ "default.target" ];
      after = [ "graphical-session.target" ];
      environment = {
        LD_LIBRARY_PATH = fullLibPath;
        ELECTRON_OZONE_PLATFORM_HINT = "auto";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${notifierWrapper}/bin/portmaster-notifier";
        Restart = "on-failure";
      };
    };

    # ──────────────────────────────────────────────────────────────────────
    # System packages
    # ──────────────────────────────────────────────────────────────────────
    environment.systemPackages =
      [ pkgs.iptables pkgs.nftables pkgs.iproute2 ]
      ++ lib.optionals cfg.ui.enable [
        appWrapper desktopItem
        pkgs.webkitgtk_4_1 pkgs.libayatana-appindicator
      ]
      ++ lib.optionals cfg.notifier.enable [ notifierWrapper ];
  };
}
