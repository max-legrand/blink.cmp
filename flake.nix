{
  description = "Set of simple, performant neovim plugins";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    fenix.url = "github:nix-community/fenix";
    fenix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems =
        [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      perSystem = { self, config, self', inputs', pkgs, system, lib, ... }: {
        # use fenix overlay
        _module.args.pkgs = import nixpkgs {
          inherit system;
          overlays = [ inputs.fenix.overlays.default ];
        };

        # define the packages provided by this flake
        packages = let
          src = ./.;
          version = "0.7.3";
        in rec {
          blink-fuzzy-lib = let
            inherit (inputs.fenix.packages.${system}.minimal) toolchain;
            rustPlatform = pkgs.makeRustPlatform {
              cargo = toolchain;
              rustc = toolchain;
            };
          in rustPlatform.buildRustPackage {
            pname = "blink-fuzzy-lib";
            inherit src version;
            useFetchCargoVendor = true;
            cargoHash = "sha256-XXI2jEoD6XbFNk3O8B6+aLzl1ZcJq1VinQXb+AOw8Rw=";
            
            buildInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin [
              pkgs.libiconv
              pkgs.darwin.apple_sdk.frameworks.Security
              pkgs.lua5_1
            ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.lua5_1
            ];

            RUSTFLAGS = pkgs.lib.optionalString pkgs.stdenv.isDarwin ''
              -L ${pkgs.libiconv}/lib -liconv 
              -L ${pkgs.lua5_1}/lib -llua
            '' + pkgs.lib.optionalString pkgs.stdenv.isLinux ''
              -L ${pkgs.lua5_1}/lib -llua
            '';

            BINDGEN_EXTRA_CLANG_ARGS = pkgs.lib.optionals pkgs.stdenv.isDarwin [
              "-I${pkgs.lua5_1}/include"
            ];

            passthru.updateScript = pkgs.nix-update-script;
          };

          blink-cmp = let
            inherit (pkgs.stdenv) hostPlatform;
            libExt = if hostPlatform.isDarwin then
              "dylib"
            else if hostPlatform.isWindows then
              "dll"
            else
              "so";
          in pkgs.vimUtils.buildVimPlugin {
            pname = "blink-cmp";
            inherit src version;
            preInstall = ''
              mkdir -p target/release
              ln -s ${blink-fuzzy-lib}/lib/libblink_cmp_fuzzy.${libExt} target/release/libblink_cmp_fuzzy.${libExt}
            '';

            passthru.updateScript = pkgs.nix-update-script;

            meta = {
              description =
                "Performant, batteries-included completion plugin for Neovim ";
              homepage = "https://github.com/saghen/blink.cmp";
              license = lib.licenses.mit;
              maintainers = with lib.maintainers; [ redxtech ];
            };
          };

          default = self'.packages.blink-cmp;
        };

        # builds the native module of the plugin
        apps.build-plugin = {
          type = "app";
          program = let
            buildScript = pkgs.writeShellApplication {
              name = "build-plugin";
              runtimeInputs = with pkgs; [
                fenix.minimal.toolchain
                gcc
                lua5_1
              ] ++ lib.optionals stdenv.isDarwin [
                libiconv
              ];
              text = ''
                export RUSTFLAGS="${if pkgs.stdenv.isDarwin then "-L ${pkgs.libiconv}/lib -liconv" else ""} -L ${pkgs.lua5_1}/lib -llua"
                export BINDGEN_EXTRA_CLANG_ARGS="-I${pkgs.lua5_1}/include"
                cargo build --release
              '';
            };
          in (lib.getExe buildScript);
        };

        # define the default dev environment
        devShells.default = pkgs.mkShell {
          name = "blink";
          packages = with pkgs; [
            gcc
            fenix.complete.toolchain
            rust-analyzer-nightly
            nix-update
            lua5_1
          ] ++ lib.optionals stdenv.isDarwin [
            libiconv
          ];
          
          RUSTFLAGS = pkgs.lib.optionalString pkgs.stdenv.isDarwin ''
            -L ${pkgs.libiconv}/lib -liconv
            -L ${pkgs.lua5_1}/lib -llua
          '' + pkgs.lib.optionalString pkgs.stdenv.isLinux ''
            -L ${pkgs.lua5_1}/lib -llua
          '';
          
          BINDGEN_EXTRA_CLANG_ARGS = pkgs.lib.optionals pkgs.stdenv.isDarwin [
            "-I${pkgs.lua5_1}/include"
          ];
        };
      };
    };
}
