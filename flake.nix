{
  description = "Portmaster application firewall for NixOS — built from source";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      git-hooks,
    }:
    let
      inherit (nixpkgs) lib;
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forEachSystem = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs { localSystem.system = system; };
    in
    {
      packages = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
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
          default = self.packages.${system}.portmaster;
        }
      );

      overlays.default = final: prev: {
        portmaster = self.packages.${prev.stdenv.hostPlatform.system}.portmaster;
        portmaster-testing = self.packages.${prev.stdenv.hostPlatform.system}.portmaster-testing;
      };

      nixosModules.default = import ./module.nix;

      formatter = forEachSystem (system: (pkgsFor system).nixfmt-rfc-style);

      checks = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          portmaster = import ./test.nix { inherit self pkgs lib; };
          pre-commit-check = git-hooks.lib.${system}.run {
            src = self;
            hooks.nixfmt-rfc-style.enable = true;
            hooks.typos.enable = true;
            hooks.rumdl.enable = true;
            hooks.check-readme-sections = {
              enable = true;
              name = "check-readme-sections";
              entry = "bash scripts/check-readme-sections.sh";
              files = "README\.md$";
              language = "system";
            };
          };
        }
      );

      devShells = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            inherit (self.checks.${system}.pre-commit-check) shellHook;
            buildInputs = self.checks.${system}.pre-commit-check.enabledPackages;
            packages = with pkgs; [ nil ];
          };
        }
      );
    };
}
