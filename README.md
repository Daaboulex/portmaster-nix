# portmaster-nix

NixOS packaging for [Portmaster](https://safing.io/portmaster/) — the free and open-source application firewall by [Safing](https://safing.io).

This flake builds Portmaster **v2.1.7 from source** (Go core + Rust/Tauri desktop + Angular UI) and provides a NixOS module with full systemd integration and security hardening.

> **Note**: This is a community packaging effort. Portmaster is developed by Safing GmbH.
> This flake will be deprecated once Portmaster lands in nixpkgs. A previous v1 packaging PR ([#264454](https://github.com/NixOS/nixpkgs/pull/264454)) exists but is outdated — this flake packages v2 from source.

## Components

| Component | Technology | Description |
|---|---|---|
| `portmaster-core` | Go | Firewall engine — DNS resolver, network filter, threat intelligence |
| `portmaster` (desktop) | Rust / Tauri | Native desktop app with system tray integration |
| `portmaster-ui` | Angular | Web UI served by the core at `127.0.0.1:817` |

## Usage

### 1. Add flake input

```nix
# flake.nix
inputs.portmaster = {
  url = "github:daaboulex/portmaster-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 2. Stack the overlay

```nix
nixpkgs.overlays = [
  inputs.portmaster.overlays.default
];
```

### 3. Import the NixOS module

```nix
imports = [
  inputs.portmaster.nixosModules.default
];
```

### 4. Enable Portmaster

```nix
services.portmaster = {
  enable = true;
  notifier.enable = true;  # System tray icon (autostart on login)
  # autostart = true;      # Start service on boot (default: true)
  # settings.devmode = true;  # Web UI at 127.0.0.1:817 (default: true)
  # extraArgs = [ "--verbose" ];
};
```

## Module Options

| Option | Type | Default | Description |
|---|---|---|---|
| `services.portmaster.enable` | bool | `false` | Enable Portmaster firewall service |
| `services.portmaster.package` | package | `pkgs.portmaster` | Portmaster package to use |
| `services.portmaster.autostart` | bool | `true` | Start service on boot. When `false`, the service is installed but must be started manually with `sudo systemctl start portmaster` |
| `services.portmaster.notifier.enable` | bool | `false` | XDG autostart for the system tray icon. Only launches if the service is active |
| `services.portmaster.notifier.delay` | int | `3` | Seconds to wait before launching the tray icon (lets the desktop system tray initialize) |
| `services.portmaster.settings` | attrs | `{}` | Freeform settings passed to portmaster-core |
| `services.portmaster.settings.devmode` | bool | `true` | Enable web UI at `127.0.0.1:817` |
| `services.portmaster.extraArgs` | list of str | `[]` | Extra CLI arguments for portmaster-core |

## What gets installed

- **System service**: `portmaster.service` — runs `portmaster-core` as root with proper capabilities and systemd hardening
- **Desktop app**: `portmaster` binary with `.desktop` file — launch from your application menu
- **System tray**: Optional XDG autostart entry (via `notifier.enable`) — checks that the service is running before launching
- **Web UI**: Available at `http://127.0.0.1:817` when `devmode` is enabled
- **Data directory**: `/var/lib/portmaster/` — managed via `systemd-tmpfiles`
- **Kernel module**: `netfilter_queue` — loaded automatically for packet filtering

## Manual service control

When `autostart = false`, Portmaster doesn't start on boot but is still fully installed:

```bash
sudo systemctl start portmaster   # Start the firewall
sudo systemctl stop portmaster    # Stop the firewall
sudo systemctl status portmaster  # Check status
```

The notifier tray icon (if enabled) will silently skip launching when the service isn't running — no "Connection refused" popup.

## Migration from v1

If you previously used the v1 packaging (binary fetch + self-update approach):

1. Stop the old service: `sudo systemctl stop portmaster-core`
2. Back up your config: `sudo cp -r /opt/safing/portmaster/config /tmp/portmaster-config-backup`
3. Rebuild with the new flake (this creates `/var/lib/portmaster/`)
4. Optionally restore config: `sudo cp -r /tmp/portmaster-config-backup/* /var/lib/portmaster/config/`
5. Clean up old data: `sudo rm -rf /opt/safing/portmaster`

> **Note**: v2 databases are not backward-compatible with v1. Threat intelligence and DNS cache will be re-downloaded automatically.

## Credits

- [Safing GmbH](https://safing.io) — Portmaster developers
- [NixOS/nixpkgs#264454](https://github.com/NixOS/nixpkgs/pull/264454) by WitteShadovv — earlier v1 packaging effort that informed this from-source build approach

## License

Portmaster is licensed under [GPL-3.0-only](https://www.gnu.org/licenses/gpl-3.0.html) by Safing GmbH.
The Nix packaging expressions in this repository are also licensed under GPL-3.0-only — see [LICENSE](LICENSE).
