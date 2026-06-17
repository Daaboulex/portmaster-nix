{
  description = "Portmaster application firewall for NixOS — built from source";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    std = {
      url = "github:Daaboulex/nix-packaging-standard?ref=v2.7.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "git-hooks";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      imports = [ inputs.std.flakeModules.base ];

      flake = {
        nixosModules.default = import ./module.nix;

        overlays.default = final: prev: {
          inherit (inputs.self.packages.${final.stdenv.hostPlatform.system})
            portmaster
            portmaster-testing
            ;
        };
      };

      perSystem =
        { pkgs, system, ... }:
        let
          portmaster = pkgs.callPackage ./package.nix { };
          portmaster-testing = pkgs.callPackage ./package.nix {
            portmasterVersion = "2.1.7-dev.2026-03-16";
            portmasterSrc = pkgs.fetchFromGitHub {
              owner = "safing";
              repo = "portmaster";
              rev = "8f9dcd59242afd397c70caf256c384d46dc967ff";
              hash = "sha256-cu+mWQseK3IaAV2cXKZpGy/Btxq3jSYEIwE23rQ39aA=";
            };
            vendorHash = "sha256-EY5EAJP2m9Avdk52HirgaoKYbTsB7a6RfSjXiet7FkA=";
            npmDepsHash = "sha256-OMF8BMxkm+I151JQwooc0PFJM2F9eYe1UUspyLZhG5M=";
            cargoHash = "sha256-qsLdnHPUoP8En+bhI93kbuyhelUoUUZVn7bZX87DoEw=";
          };
        in
        {
          packages = {
            default = portmaster;
            inherit portmaster portmaster-testing;
          };

          checks.module-eval-nixos = inputs.std.lib.nixosModuleCheck {
            inherit (inputs) nixpkgs;
            inherit system;
            overlays = [ inputs.self.overlays.default ];
            module = ./module.nix;
            config.services.portmaster.enable = true;
          };
        };
    };
}
