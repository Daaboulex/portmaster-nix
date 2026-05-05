# portmaster-nix — Option Reference

Companion to the top-level [README](../README.md). All options live
under `services.portmaster.*`. This document mirrors the README
"Module Options" section; the README is the canonical home, this page
is the deep-link target.

## Core toggles

| Option | Type | Default | Description |
|---|---|---|---|
| `services.portmaster.enable` | `bool` | `false` | Enable the Portmaster firewall service |
| `services.portmaster.package` | `package` | `pkgs.portmaster` | Portmaster package to use |
| `services.portmaster.autostart` | `bool` | `true` | Start the service on boot. When `false`, the service is installed but must be started manually with `sudo systemctl start portmaster` |

## Notifier (system tray)

| Option | Type | Default | Description |
|---|---|---|---|
| `services.portmaster.notifier.enable` | `bool` | `false` | XDG autostart for the system tray icon. The notifier silently skips launching if the service isn't running, so no "Connection refused" popup appears |
| `services.portmaster.notifier.delay` | `int` | `3` | Seconds to wait before launching the tray icon (lets the desktop system tray initialize first) |

## Settings + extra args

| Option | Type | Default | Description |
|---|---|---|---|
| `services.portmaster.settings` | `attrs` | `{}` | Freeform settings passed to `portmaster-core` |
| `services.portmaster.settings.devmode` | `bool` | `true` | Enable web UI at `http://127.0.0.1:817` |
| `services.portmaster.extraArgs` | `list of str` | `[]` | Extra CLI arguments for `portmaster-core` |

## What the module installs

For reference (these are NOT options but the side-effects of
`enable = true`):

- **System service**: `portmaster.service` runs `portmaster-core` as
  root with proper capabilities and systemd hardening
- **Desktop app**: `portmaster` binary with `.desktop` file — launch
  from the application menu
- **System tray** (optional): XDG autostart via `notifier.enable` —
  starts in background/tray-only mode, checks the service is running
  before launching
- **Web UI**: `http://127.0.0.1:817` when `settings.devmode = true`
- **Data directory**: `/var/lib/portmaster/` managed via
  `systemd-tmpfiles`
- **Kernel module**: `netfilter_queue` loaded automatically for packet
  filtering

## Read-only outputs

This module exposes no read-only attribute outputs (unlike e.g.
`vfio-stealth-nix`'s `_kernelPostPatch`). All consumer-facing surface
goes through `services.portmaster.*` above.

## Future options

The upstream-issue draft at
[`docs/upstream-issue-draft.md`](upstream-issue-draft.md) tracks the
in-flight nixpkgs upstreaming work. Once Portmaster lands in nixpkgs,
the `services.portmaster` namespace will move there and this flake
will be deprecated. The option shape above is informed by what would
be appropriate for that upstreaming, so consumers can switch with
minimal config changes.
