{
  description = "PHP 8.3 with PhpRedis, Composer, and HAProxy Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        myPhp = pkgs.php83.buildEnv {
          extensions = ({ all, ... }: with all; [
            bcmath
            calendar
            curl
            ctype
            dom
            filter
            gd
            iconv
            intl
            mbstring
            mysqli
            mysqlnd
            openssl
            pdo
            pdo_mysql
            pdo_sqlite
            redis # <--- Extensión PhpRedis añadida aquí
            session
            tokenizer
            xml
            zip
          ]);
          extraConfig = ''
            memory_limit = 512M
          '';
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            myPhp
            pkgs.php83Packages.composer
            pkgs.nodejs_20
            pkgs.redis
            pkgs.haproxy
          ];

          shellHook = ''
            echo "🐘 PHP 8.3 Environment Loaded with PhpRedis"
            php -v
            echo "📦 Extensiones cargadas:"
            php -m | grep redis
            composer --version
            echo "🍦 Redis CLI disponible: $(redis-cli --version)"
            echo "🛡️ HAProxy disponible: $(haproxy -v | head -n 1)"
          '';
        };
      });
}
