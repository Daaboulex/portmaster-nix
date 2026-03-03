{
  description = "Portmaster application firewall for NixOS — built from source";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forEachSystem = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in {
      packages = forEachSystem (system:
        let pkgs = pkgsFor system;
        in {
          portmaster = pkgs.callPackage ./package.nix { };
          default = self.packages.${system}.portmaster;
        }
      );

      overlays.default = final: prev: {
        portmaster = self.packages.${prev.stdenv.hostPlatform.system}.portmaster;
      };

      nixosModules.default = import ./module.nix;
    };
}
