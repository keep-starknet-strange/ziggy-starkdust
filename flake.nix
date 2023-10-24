{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, zig, ... }:
    let
      overlays = [ zig.overlays.default ];
      # Support only systems supported by the zig overlay.
      systems = builtins.attrNames zig.packages;
    in
    flake-utils.lib.eachSystem systems (system:
      let
        pkgs = import nixpkgs {
          inherit system overlays;
        };
      in
      {
        # format with `nix fmt`
        formatter = pkgs.nixpkgs-fmt;

        devShell = pkgs.mkShell {
          # Add native packages needed to build the cairo vm here.
          # You can find packages at https://search.nixos.org/packages
          nativeBuildInputs = with pkgs; [
            zigpkgs.master
          ];
        };
      }
    );
}
