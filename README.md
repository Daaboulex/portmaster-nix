# Portmaster (Nix Flake)

This flake packages the [Portmaster](https://safing.io/portmaster/) privacy application for NixOS.

## Usage

### In a Flake

Add this to your `flake.nix`:

```nix
inputs.portmaster.url = "path:./pkgs/portmaster"; # Or git URL
```

Then in your overlay:

```nix
nixpkgs.overlays = [
  inputs.portmaster.overlays.default
];
```

## License

AGPL-3.0 (See LICENSE)
