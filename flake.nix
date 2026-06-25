{
  description = "Redis Cluster Lab with per-library development shells";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        infraInputs = [
          pkgs.redis
          pkgs.haproxy
        ];

        predisInputs = infraInputs ++ [
          pkgs.php83
          pkgs.php83Packages.composer
        ];

        ioredisInputs = infraInputs ++ [
          pkgs.nodejs_20
        ];
      in
      {
        devShells = rec {
          base = pkgs.mkShell {
            buildInputs = infraInputs;
            shellHook = ''
              echo "Redis Cluster Lab base shell"
              echo "Use make up to run Docker infrastructure and lab runners."
            '';
          };

          default = base;

          predis = pkgs.mkShell {
            buildInputs = predisInputs;
            shellHook = ''
              echo "suites/php/predis dev shell"
              php -v | head -n 1
              composer --version
            '';
          };

          ioredis = pkgs.mkShell {
            buildInputs = ioredisInputs;
            shellHook = ''
              echo "suites/node/ioredis dev shell"
              node --version
              npm --version
            '';
          };

          all = pkgs.mkShell {
            buildInputs = predisInputs ++ [
              pkgs.nodejs_20
            ];
            shellHook = ''
              echo "Redis Cluster Lab all-suite dev shell"
              php -v | head -n 1
              node --version
            '';
          };
        };
      });
}
