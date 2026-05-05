# NixOS VM test for the Portmaster module.
# Run with: nix build .#checks.x86_64-linux.portmaster -L
{
  self,
  pkgs,
  lib,
}:

let
  portmaster = pkgs.callPackage ./package.nix { };
in
pkgs.testers.runNixOSTest {
  name = "portmaster";

  nodes.machine =
    { ... }:
    {
      imports = [ self.nixosModules.default ];

      services.portmaster = {
        enable = true;
        package = portmaster;
        settings.devmode = true;
      };

      # VM tuning
      virtualisation = {
        graphics = false;
        memorySize = 2048;
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # 1. Service starts and stays running
    machine.wait_for_unit("portmaster.service")
    machine.succeed("systemctl is-active portmaster.service")

    # 2. All artifacts are symlinked into BinDir (broken symlinks crash index generation)
    machine.succeed("test -L /usr/lib/portmaster/portmaster-core")
    machine.succeed("test -L /usr/lib/portmaster/portmaster")
    machine.succeed("test -L /usr/lib/portmaster/portmaster.zip")
    machine.succeed("test -L /usr/lib/portmaster/assets.zip")
    # Verify none are broken (targets exist)
    machine.succeed("test -e /usr/lib/portmaster/portmaster-core")
    machine.succeed("test -e /usr/lib/portmaster/portmaster")

    # 3. Runtime symlinks exist
    machine.succeed("test -L /var/lib/portmaster/runtime/portmaster-core")
    machine.succeed("test -L /var/lib/portmaster/runtime/portmaster.zip")

    # 4. UI symlink exists
    machine.succeed("test -L /var/lib/portmaster/ui")

    # 5. config.json has releaseChannel set (default: stable)
    machine.succeed('cat /var/lib/portmaster/config.json | grep -q "stable"')

    # 6. portmaster-core API responds on devmode port 817
    #    (may take a few seconds to start listening)
    machine.wait_until_succeeds("curl -sf http://127.0.0.1:817/ || curl -sf -o /dev/null -w '%{http_code}' http://127.0.0.1:817/ | grep -q '[23]'", timeout=30)

    # 7. UI assets are served (not "file not found")
    machine.wait_until_succeeds("curl -sf http://127.0.0.1:817/ui/modules/portmaster/ | grep -q 'html'", timeout=30)
  '';
}
