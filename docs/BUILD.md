# portmaster-nix — Build & Operator Reference

Companion to the top-level [README](../README.md). README §Usage covers
the user-facing flake-input + module-import path. This doc covers the
developer / operator commands beyond that — dev shell, formatters,
hooks, tests, the update contract, and common troubleshooting.

## Dev shell

```bash
git clone https://github.com/Daaboulex/portmaster-nix
cd portmaster-nix
nix develop                       # enter dev shell, installs pre-commit hooks
```

The dev shell provides:

- `nil` — Nix LSP for editor integration
- `nixfmt-rfc-style` — formatter (run via `nix fmt`)
- `pre-commit` — installed git hooks running on every commit

## Build

```bash
nix flake check --no-build        # eval-only check
nix fmt                           # format all .nix
nix build .#portmaster-core       # Go core only
nix build .#portmaster-ui         # Angular static bundle
nix build .#portmaster            # composed Tauri desktop + core + UI
nix build                         # default — equals .#portmaster
```

Each output produces a verifiable artifact:

| Package | Verify |
|---|---|
| `portmaster-core` | `./result/bin/portmaster-core --help` |
| `portmaster-ui` | `ls ./result/share/portmaster-ui` shows Angular bundle |
| `portmaster` | `./result/bin/portmaster --version` |

## Pre-commit hooks

Installed via `nix develop`. Failing hook prints the exact command to
reproduce. Bypassing hooks (`--no-verify`) is not allowed for this
repo — fix and re-commit.

## Tests

`test.nix` holds the eval-level smoke tests. Live VM tests would
require kernel netfilter access and root, so the verification chain
stops at:

```text
eval check   →   build all 3 packages   →   wrapper script + .desktop + tray polkit references
                  →   ldd check on portmaster-core
```

CI wires this in `.github/workflows/ci.yml`.

## Update contract — `scripts/update.sh`

Tracks `safing/portmaster` GitHub releases. Twice-weekly run
(Monday + Thursday, 12:00 UTC) via `update.yml`.

Hashes maintained: `hash`, `vendorHash`, `npmDepsHash`, `cargoHash`
(four because the build pulls from Go modules, npm, and Cargo).

Exit codes:

| Exit | Meaning |
|---|---|
| `0` | No update, or update succeeded — main branch advanced |
| `1` | Update found but verification chain failed → workflow opens GitHub Issue with build log + recovery branch |
| `2` | Network / API error → retry next run |

Verification chain mirrors CI: eval → build → wrapper check → ldd check.
**Never false-positive**: every step must pass before push to `main`.

## Manual service control

When `services.portmaster.autostart = false`, the service is installed
but not enabled at boot:

```bash
sudo systemctl start portmaster   # Start the firewall
sudo systemctl stop portmaster    # Stop the firewall
sudo systemctl status portmaster  # Check status
sudo journalctl -u portmaster -f  # Tail logs
```

The notifier tray icon (when `notifier.enable = true`) silently skips
launching while the service isn't running — no "Connection refused"
popup.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Per-app firewall rules disappear after `nixos-rebuild switch` | `nix_linux.go` tag patch not applied — store path used as profile identity | Confirm you're using this flake's `pkgs.portmaster`, not nixpkgs'. The patch is in `package.nix` `postPatch` |
| Desktop "Start Service" button does nothing | FHS path patch missing (`/sbin/systemctl` not rewritten) | Same as above — use this flake's package, the patch lives in `package.nix` |
| Tray icon never appears | `notifier.enable` false, or system-tray protocol unsupported by your DE | Set `notifier.enable = true`, or check `notifier.delay` — default is 3 s, raise on slow desktops |
| Migration from v1 leaves stale binary in `/opt/safing/` | Old install was binary-fetch (v1), not from-source (v2) | Stop old service, back up `/opt/safing/portmaster/config`, rebuild with this flake (creates `/var/lib/portmaster/`), restore config, then `rm -rf /opt/safing/portmaster` |
| `cargoHash` mismatch on every update | Tauri desktop's Cargo.lock changed | Re-run `update.sh` — it recomputes `cargoHash` automatically |
| Service starts but blocks all traffic on first boot | `devmode` disabled and no rules configured yet | Set `services.portmaster.settings.devmode = true;` to expose web UI, configure rules, then disable devmode if desired |

For other issues, attach the failing build log + `services.portmaster`
config snippet to a GitHub Issue.
