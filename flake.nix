{
  description = "A prisma test project";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.zig.url = "github:mitchellh/zig-overlay";
  inputs.zls.url = "github:zigtools/zls";

  outputs = { self, nixpkgs, flake-utils, zig, zls }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
      };
    in {
      devShell = pkgs.mkShell {
        buildInputs = with pkgs; [
          glfw
          ocaml-ng.ocamlPackages_5_1.ocaml
          ocaml-ng.ocamlPackages_5_1.utop
          ocaml-ng.ocamlPackages_5_1.ocaml-lsp
          ocaml-ng.ocamlPackages_5_1.ocamlformat
          zls.packages.${system}.default
          zig.packages.${system}.master
          pkg-config
        ];
      };
    });
}

