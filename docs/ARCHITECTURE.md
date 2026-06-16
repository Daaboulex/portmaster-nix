# portmaster-nix — Architecture

Companion to the top-level [README](../README.md). Covers directory
layout, the three-language component boundary (Go / Rust / Angular),
and the NixOS-specific patches that this flake applies on top of
upstream.

## Directory layout

```
portmaster-nix/
├── flake.nix                    # packages, overlay, nixosModules.default
├── package.nix                  # builds portmaster-core, portmaster-ui,
│                                # portmaster (Tauri desktop), composes them
├── module.nix                   # services.portmaster.* options + systemd
│                                # service + tmpfiles + autostart wiring
├── test.nix                     # eval-level / build-level smoke tests
├── nix-profile-tags.patch       # adds nix_linux.go tag handler so per-app
│                                # firewall rules survive store-path churn
├── scripts/
│   └── update.sh                # safing/portmaster release tracker
├── docs/
│   ├── ARCHITECTURE.md          # this file
│   ├── BUILD.md
│   ├── OPTIONS.md
│   └── upstream-issue-draft.md  # nixpkgs upstreaming draft
├── .github/
│   ├── workflows/{ci,update,maintenance}.yml
│   ├── update.json
│   └── dependabot.yml
├── README.md
├── LICENSE
└── SECURITY.md
```

## Component boundary

Three upstream languages, three packages, one composed output:

| Component | Language | Output binary | Owner of |
|---|---|---|---|
| `portmaster-core` | Go | `portmaster-core` | Firewall engine: DNS resolver, network filter, threat intelligence, REST API at `127.0.0.1:817` |
| `portmaster-ui` | Angular | static asset bundle | Web UI served by `portmaster-core` (in-binary, no separate web server) |
| `portmaster` (desktop) | Rust / Tauri | `portmaster` | Native desktop app — wraps `portmaster-ui` in a Tauri window, system tray, splash screen |

`package.nix` builds each, then composes the final `portmaster` package
with `.desktop` file, icons, and a wrapper that launches the desktop
binary or core directly depending on flags.

## Module → option group ownership

| Option group | Owner file | What it controls |
|---|---|---|
| `services.portmaster.{enable, package, autostart}` | `module.nix` | Service installation + boot behavior |
| `services.portmaster.notifier.{enable, delay}` | `module.nix` | XDG autostart for the system tray notifier |
| `services.portmaster.{settings, extraArgs}` | `module.nix` | Freeform pass-through to `portmaster-core` (devmode toggle, custom CLI args) |

The systemd unit lives in `module.nix`. `tmpfiles` rules create
`/var/lib/portmaster/`. The `netfilter_queue` kernel module is loaded
via `boot.kernelModules` so packet filtering works after first boot.

## NixOS-specific patches

The two patches below close the gap between upstream's FHS assumptions
and Nix's per-rebuild store path churn. Without them, Portmaster either
loses per-app rules every rebuild or cannot detect/manage its own
service.

### Profile persistence — `nix_linux.go` tag handler

Upstream Portmaster ships tag handlers for Flatpak and Snap so that
applications keep stable identity across updates. NixOS has the same
problem at a sharper edge: every rebuild generates a new derivation
hash → new binary path → Portmaster sees a "new" application and
creates a fresh profile. Per-app firewall rules vanish.

This package adds a `nix_linux.go` tag handler (same pattern as
upstream's `flatpak_linux.go`) that derives a `nix-pkg` tag from
the derivation name + binary name. Profiles match on this tag instead
of the volatile store path, so per-app rules persist across rebuilds.

The patch is applied in `package.nix` via `postPatch`.

### FHS path fixes — Tauri desktop app

The Tauri desktop hardcodes FHS paths that don't exist on NixOS:

| Upstream path | NixOS path | Purpose |
|---|---|---|
| `/sbin/systemctl` et al. | `${systemd}/bin/systemctl` | Service status detection (the desktop polls "is portmaster.service running?") |
| `/usr/bin/pkexec` | `/run/wrappers/bin/pkexec` | Polkit privilege elevation (SUID wrapper) |
| `/usr/bin/gksudo` | `/run/wrappers/bin/gksudo` | Fallback privilege elevation |

Without these patches, the desktop app cannot detect whether
`portmaster.service` is running, and the "Start Service" button in
the splash screen does nothing.

Patched via `substituteInPlace` in `package.nix` `postPatch`.

## Why no nixpkgs module yet

A v1 packaging PR exists at
[NixOS/nixpkgs#264454](https://github.com/NixOS/nixpkgs/pull/264454)
(WitteShadovv) but is outdated. This flake packages v2 from source.
Once the upstreaming work in `docs/upstream-issue-draft.md` lands in
nixpkgs, this flake will be deprecated and downstream users should
switch to the in-tree `services.portmaster` module.

## Architecture support

`x86_64-linux` and `aarch64-linux`. Upstream Go + Rust code is
architecture-independent; both architectures are supported.
