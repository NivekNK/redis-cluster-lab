{
  description = "suites/node/ioredis Redis Cluster Lab shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.nodejs_20
            pkgs.redis
          ];

          shellHook = ''
            echo "suites/node/ioredis dev shell"
            node --version
            npm --version
          '';
        };
      });
}
