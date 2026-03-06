{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.portmaster;
  settingsFormat = pkgs.formats.json { };
in
{
  options.services.portmaster = {
    enable = lib.mkEnableOption "Portmaster application firewall";

    package = lib.mkPackageOption pkgs "portmaster" { };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = settingsFormat.type;
        options = {
          devmode = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Enable development mode. This makes the Portmaster UI available at 127.0.0.1:817.
            '';
          };
        };
      };
      default = { };
      description = ''
        Configuration for Portmaster. Options set here will be passed to portmaster-core.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extra command-line arguments to pass to portmaster-core.
      '';
    };

    autostart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether portmaster.service starts automatically on boot.
        When false, the service is installed but must be started manually
        with `sudo systemctl start portmaster`.
      '';
    };

    notifier = {
      enable = lib.mkEnableOption "Portmaster system tray notifier (XDG autostart)";
      delay = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = ''
          Seconds to delay notifier startup after login.
          Allows the desktop environment's system tray to initialize before
          the Portmaster tray icon appears.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    boot.kernelModules = [ "netfilter_queue" ];

    systemd.tmpfiles.settings."10-portmaster" = {
      "/var/lib/portmaster".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "/var/lib/portmaster/logs".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "/var/lib/portmaster/download_binaries".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "/var/lib/portmaster/updates".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "/var/lib/portmaster/databases".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "/var/lib/portmaster/databases/icons".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "/var/lib/portmaster/config".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "/var/lib/portmaster/intel".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "/var/lib/portmaster/runtime".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      # Symlink Nix store binaries into the runtime directory
      "/var/lib/portmaster/runtime/portmaster-core"."L+" = {
        argument = "${cfg.package}/lib/portmaster/portmaster-core";
      };
      "/var/lib/portmaster/runtime/portmaster"."L+" = {
        argument = "${cfg.package}/lib/portmaster/portmaster";
      };
      "/var/lib/portmaster/runtime/portmaster.zip"."L+" = {
        argument = "${cfg.package}/lib/portmaster/portmaster.zip";
      };
      "/var/lib/portmaster/runtime/assets.zip"."L+" = {
        argument = "${cfg.package}/lib/portmaster/assets.zip";
      };
      # Portmaster hardcodes /usr/lib/portmaster/ for portmaster.zip lookup
      "/usr/lib/portmaster".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "/usr/lib/portmaster/portmaster.zip"."L+" = {
        argument = "${cfg.package}/lib/portmaster/portmaster.zip";
      };
    };

    systemd.services.portmaster = {
      description = "Portmaster by Safing";
      documentation = [
        "https://safing.io"
        "https://docs.safing.io"
      ];
      before = [
        "nss-lookup.target"
        "network.target"
        "shutdown.target"
      ];
      after = [
        "systemd-networkd.service"
        "systemd-tmpfiles-setup.service"
      ];
      conflicts = [
        "shutdown.target"
        "firewalld.service"
      ];
      wants = [ "nss-lookup.target" ];
      wantedBy = if cfg.autostart then [ "multi-user.target" ] else [ ];
      requires = [ "systemd-tmpfiles-setup.service" ];

      serviceConfig =
        let
          baseArgs = [
            "/var/lib/portmaster/runtime/portmaster-core"
            "--data-dir=/var/lib/portmaster"
            "--log-dir=/var/lib/portmaster/logs"
          ];
          devmodeArgs = lib.optional cfg.settings.devmode "--devmode";
          allArgs = baseArgs ++ devmodeArgs ++ cfg.extraArgs;
        in
        {
          Type = "simple";
          ExecStart = lib.concatStringsSep " " allArgs;
          ExecStopPost = "-/var/lib/portmaster/runtime/portmaster-core recover-iptables";
          Restart = "always";
          RestartSec = "10";
          User = "root";
          Group = "root";
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          MemoryLow = "2G";
          NoNewPrivileges = true;
          PrivateTmp = true;
          PIDFile = "/var/lib/portmaster/core-lock.pid";
          StateDirectory = "portmaster";
          WorkingDirectory = "/var/lib/portmaster";
          ProtectSystem = true;
          ReadWritePaths = [ "/var/lib/portmaster" ];
          ProtectHome = "read-only";
          ProtectKernelTunables = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          PrivateDevices = true;
          RestrictNamespaces = true;
          AmbientCapabilities = [
            "cap_chown"
            "cap_kill"
            "cap_net_admin"
            "cap_net_bind_service"
            "cap_net_broadcast"
            "cap_net_raw"
            "cap_sys_module"
            "cap_sys_ptrace"
            "cap_dac_override"
            "cap_fowner"
            "cap_fsetid"
            "cap_sys_resource"
            "cap_bpf"
            "cap_perfmon"
          ];
          CapabilityBoundingSet = [
            "cap_chown"
            "cap_kill"
            "cap_net_admin"
            "cap_net_bind_service"
            "cap_net_broadcast"
            "cap_net_raw"
            "cap_sys_module"
            "cap_sys_ptrace"
            "cap_dac_override"
            "cap_fowner"
            "cap_fsetid"
            "cap_sys_resource"
            "cap_bpf"
            "cap_perfmon"
          ];
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_NETLINK"
            "AF_INET"
            "AF_INET6"
          ];
          Environment = [
            "LOGLEVEL=info"
            "PORTMASTER_DATA_DIR=/var/lib/portmaster"
            "PORTMASTER_RUNTIME_DIR=/var/lib/portmaster/runtime"
          ];
        };
    };

    # XDG autostart for the Portmaster desktop app (system tray icon).
    # Only launches if portmaster.service is active — prevents "Connection refused"
    # popup when the service is stopped or not yet started.
    environment.etc."xdg/autostart/portmaster-notifier.desktop" = lib.mkIf cfg.notifier.enable {
      text = ''
        [Desktop Entry]
        Name=Portmaster Notifier
        Comment=Portmaster system tray notifier
        Exec=/bin/sh -c 'sleep ${toString cfg.notifier.delay}; systemctl is-active --quiet portmaster.service && exec ${cfg.package}/bin/portmaster --data /var/lib/portmaster'
        Type=Application
        X-KDE-autostart-phase=2
        X-KDE-StartupNotify=false
        NoDisplay=true
      '';
    };
  };
}
