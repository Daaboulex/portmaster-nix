{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.portmaster;
  settingsFormat = pkgs.formats.json { };

  # Portmaster's config.json is hierarchical JSON; keys are flattened on load
  # with `/` separator (see base/config/persistence.go:Flatten). Users declare
  # flat slash-keys (e.g. `"dns/nameservers"`) matching Portmaster's internal
  # naming, then we expand them to nested attrs so the resulting JSON deep-
  # merges cleanly with user edits from the UI.
  #
  # Two tiers of declarative config:
  #   - `settings`       — soft seeds. Applied on first boot; UI edits win
  #                        on subsequent starts. Use for preferences the user
  #                        should be free to tweak live.
  #   - `forceSettings`  — hard overrides. Re-applied on every start, UI
  #                        edits are reverted. Use for settings that MUST
  #                        stay a certain way for the system to function
  #                        (Mullvad-compatibility DNS settings, kill switch,
  #                        etc.).
  #
  # `devmode` is a CLI flag, not a config.json key — strip before expanding.
  expandFlat =
    flat:
    lib.foldl' (
      acc: key: lib.recursiveUpdate acc (lib.setAttrByPath (lib.splitString "/" key) flat.${key})
    ) { } (lib.attrNames flat);
  seedFlat = {
    "core/releaseChannel" = cfg.releaseChannel;
  }
  // (removeAttrs cfg.settings [ "devmode" ]);
  seedJSON = pkgs.writeText "portmaster-seed.json" (builtins.toJSON (expandFlat seedFlat));
  forceJSON = pkgs.writeText "portmaster-force.json" (builtins.toJSON (expandFlat cfg.forceSettings));
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
        Soft declarative settings — seeded into config.json on first boot,
        then UI edits win on subsequent starts. Use for preferences the
        user may want to change live (filter list selections, expertise
        level, notification behaviour, ...).
      '';
    };

    forceSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Hard declarative overrides — applied on every start, UI edits are
        reverted. Use for settings that MUST stay a certain way for the
        system to keep working (e.g. VPN-compatibility DNS settings where
        the wrong value causes a boot-time deadlock).
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

    releaseChannel = lib.mkOption {
      type = lib.types.enum [
        "stable"
        "beta"
        "staging"
        "support"
      ];
      default = "stable";
      description = ''
        Portmaster update release channel. Controls which update index URL the service uses.
        Upstream channels: stable, beta (new features that may break), staging (dev releases),
        support (troubleshooting). Source: service/core/update_config.go.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    warnings =
      lib.optional
        (cfg.releaseChannel != "stable" && (pkgs ? portmaster && cfg.package == pkgs.portmaster))
        "services.portmaster: using non-stable releaseChannel '${cfg.releaseChannel}' with the stable package build. Consider using pkgs.portmaster-testing.";

    environment.systemPackages = [ cfg.package ];

    boot.kernelModules = [ "xt_NFQUEUE" ];

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
      # Modular UI assets — Portmaster core looks for /ui/modules/portmaster/...
      "/var/lib/portmaster/ui"."L+" = {
        argument = "${cfg.package}/lib/portmaster/ui";
      };
      "/var/lib/portmaster/runtime/ui"."L+" = {
        argument = "${cfg.package}/lib/portmaster/ui";
      };
      # Portmaster hardcodes /usr/lib/portmaster/ as BinDir on Linux.
      # The updates module scans this directory via GenerateIndexFromDir() and
      # hashes every file to build an artifact index. ANY broken symlink here
      # crashes the entire index generation, leaving a null index — which makes
      # both GetFile("portmaster") (process module) and GetFile("portmaster.zip")
      # (UI serve module) return "file not found", completely breaking the UI.
      # All artifacts must be symlinked here with valid targets.
      "/usr/lib/portmaster".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "/usr/lib/portmaster/portmaster-core"."L+" = {
        argument = "${cfg.package}/lib/portmaster/portmaster-core";
      };
      "/usr/lib/portmaster/portmaster"."L+" = {
        argument = "${cfg.package}/lib/portmaster/portmaster";
      };
      "/usr/lib/portmaster/portmaster.zip"."L+" = {
        argument = "${cfg.package}/lib/portmaster/portmaster.zip";
      };
      "/usr/lib/portmaster/assets.zip"."L+" = {
        argument = "${cfg.package}/lib/portmaster/assets.zip";
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

      # Two-pass merge:
      #   1) seed * existing  → user's UI edits win over soft defaults
      #   2) result * force   → force overrides stomp on whatever was there
      #
      # jq's `*` is right-biased: `A * B` keeps B's values when both set.
      # Portmaster re-normalizes on save (flatten → expand), so either
      # flat slash-keys or nested JSON parse the same way — we emit nested
      # at eval time to keep the file human-readable.
      preStart = ''
        configFile=/var/lib/portmaster/config.json
        existing=$(cat "$configFile" 2>/dev/null || echo '{}')
        [ -z "$existing" ] && existing='{}'
        echo "$existing" \
          | ${pkgs.jq}/bin/jq \
              --slurpfile seed  ${seedJSON} \
              --slurpfile force ${forceJSON} \
              '($seed[0] * .) * $force[0]' \
          > "$configFile.tmp"
        # Validate merged JSON before replacing live config — an interrupted
        # write (power fault, OOM) produces truncated JSON that would revert
        # forceSettings to Portmaster defaults on next start.
        if ! ${pkgs.jq}/bin/jq '.' "$configFile.tmp" > /dev/null 2>&1; then
          echo "portmaster preStart: config.json.tmp is not valid JSON — refusing to replace" >&2
          rm -f "$configFile.tmp"
          exit 1
        fi
        mv "$configFile.tmp" "$configFile"
        chmod 0600 "$configFile"
      '';

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
        Exec=/bin/sh -c 'sleep ${toString cfg.notifier.delay}; systemctl is-active --quiet portmaster.service && exec ${cfg.package}/bin/portmaster --background --data /var/lib/portmaster'
        Type=Application
        X-KDE-autostart-phase=2
        X-KDE-StartupNotify=false
        NoDisplay=true
      '';
    };
  };
}
