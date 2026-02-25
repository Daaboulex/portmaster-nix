{
  description = "Portmaster Privacy Firewall for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages = {
          portmaster-start = pkgs.callPackage ./package.nix { };
          default = self.packages.${system}.portmaster-start;
        };
      }
    ) // {
      nixosModules.default = ./module.nix;

      overlays.default = final: prev: {
        portmaster-start = self.packages.${prev.stdenv.hostPlatform.system}.portmaster-start;
      };
    };
}
