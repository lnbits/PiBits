{
  description = "LNbits + Spark sidecar for Raspberry Pi 4";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs = { self, nixpkgs, flake-utils, nixos-hardware }:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      nixosConfigurations.lnbits-pi = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit self; };
        modules = [
          nixos-hardware.nixosModules.raspberry-pi-4
          ./hosts/lnbits-pi/configuration.nix
        ];
      };
    };
}
