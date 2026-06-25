{
  description = "suites/php/predis Redis Cluster Lab shell";

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
            pkgs.php83
            pkgs.php83Packages.composer
            pkgs.redis
          ];

          shellHook = ''
            echo "suites/php/predis dev shell"
            php -v | head -n 1
            composer --version
          '';
        };
      });
}
