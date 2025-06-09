{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs =
    { self, nixpkgs }:
    {
      packages.aarch64-darwin =
        let
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        in
        {
          vz-nixos = pkgs.callPackage ./nix/pkgs/vz-nixos.nix { };
          socket-vmnet = pkgs.callPackage ./nix/pkgs/socket-vmnet.nix { };

          test-vmnet-socket-fd = pkgs.callPackage ./nix/pkgs/test-vmnet-socket-fd.nix {
            inherit (self.packages.aarch64-darwin) vz-nixos socket-vmnet;
            nixosToplevel = self.nixosConfigurations.minimal.config.system.build.toplevel;
          };
          test-vmnet-socket-path = pkgs.callPackage ./nix/pkgs/test-vmnet-socket-path.nix {
            inherit (self.packages.aarch64-darwin) vz-nixos socket-vmnet;
            nixosToplevel = self.nixosConfigurations.minimal.config.system.build.toplevel;
          };
        };

      nixosModules.minimal = import ./nix/modules/minimal.nix;

      nixosConfigurations.minimal = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [ self.nixosModules.minimal ];
      };

      checks.aarch64-darwin =
        let
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        in
        {
          inherit (self.packages.aarch64-darwin) vz-nixos;

          minimal-boot = pkgs.callPackage ./nix/pkgs/minimal-boot-check.nix {
            inherit (self.packages.aarch64-darwin) vz-nixos;
            nixosToplevel = self.nixosConfigurations.minimal.config.system.build.toplevel;
          };
        };

      checks.aarch64-linux = {
        minimal-toplevel = self.nixosConfigurations.minimal.config.system.build.toplevel;
      };
    };
}
