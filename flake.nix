{
  description = "Native development environment for the Mopidy workspace";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          gstPackages = with pkgs.gst_all_1; [
            gstreamer
            gst-plugins-base
            gst-plugins-good
          ];
          gstLibraries = map pkgs.lib.getLib gstPackages;
          giTypelibPath = pkgs.lib.makeSearchPath "lib/girepository-1.0" gstLibraries;
          gstPluginPath = pkgs.lib.makeSearchPath "lib/gstreamer-1.0" gstLibraries;
          python = pkgs.python313.withPackages (ps: [ ps.pygobject3 ]);
        in
        {
          gstreamer-smoke =
            pkgs.runCommand "mopidy-gstreamer-smoke"
              {
                nativeBuildInputs = [ python ];
              }
              ''
                export GI_TYPELIB_PATH=${giTypelibPath}
                export GST_PLUGIN_SYSTEM_PATH_1_0=${gstPluginPath}
                python -c 'import gi; gi.require_version("Gst", "1.0"); from gi.repository import Gst; Gst.init(None); assert Gst.ElementFactory.find("audiotestsrc"); assert Gst.ElementFactory.find("playbin"); assert Gst.ElementFactory.find("souphttpsrc")'
                touch "$out"
              '';
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          nativeLibraries = [
            pkgs.cairo
            pkgs.glib
            pkgs.glib-networking
            pkgs.gobject-introspection
            pkgs.libffi
            pkgs.libx11
            pkgs.libxcb
            pkgs.xorgproto
          ];
          gstPackages = with pkgs.gst_all_1; [
            gstreamer
            gst-plugins-base
            gst-plugins-good
          ];
          gstLibraries = map pkgs.lib.getLib gstPackages;
          includePath = pkgs.lib.makeSearchPathOutput "dev" "include" nativeLibraries;
          giTypelibPath = pkgs.lib.makeSearchPath "lib/girepository-1.0" (
            map pkgs.lib.getLib nativeLibraries ++ gstLibraries
          );
          gstPluginPath = pkgs.lib.makeSearchPath "lib/gstreamer-1.0" gstLibraries;

          # Mopidy's unmodified tox configuration relies on tox-uv settings such
          # as uv_resolution. Pin this small tooling layer because this nixpkgs
          # revision does not provide a recent compatible tox/tox-uv pair.
          # Project dependencies remain owned and installed by uv and tox.
          toxPackage = pkgs.python313Packages.buildPythonPackage {
            pname = "tox";
            version = "4.52.1";
            format = "wheel";
            src = pkgs.fetchurl {
              url = "https://files.pythonhosted.org/packages/3a/70/0d4fb1eefa05a24ca2f58272b4c4718090dd5ed7e38b54b9a7e757bfafc8/tox-4.52.1-py3-none-any.whl";
              hash = "sha256-PE7vCmTzGd8LZ9rNt+3P7ah8jMciWBr12Y3VTz/92O8=";
            };
            dependencies = with pkgs.python313Packages; [
              cachetools
              colorama
              filelock
              packaging
              platformdirs
              pluggy
              pyproject-api
              python-discovery
              tomli-w
              virtualenv
            ];
            doCheck = false;
          };
          toxUv = pkgs.python313Packages.buildPythonPackage {
            pname = "tox-uv-bare";
            version = "1.36.0";
            format = "wheel";
            src = pkgs.fetchurl {
              url = "https://files.pythonhosted.org/packages/f7/0a/6dc462e4fb543305283a6157c80f43e3d12ca4702da6ae6521d541c6b55c/tox_uv_bare-1.36.0-py3-none-any.whl";
              hash = "sha256-ujl90Dlt+Vp1dE1OQqUO4nIHwP/PJ3ti/7qcPeRVqTk=";
            };
            dependencies = [
              pkgs.python313Packages.packaging
              toxPackage
            ];
            doCheck = false;
          };
          toxEnv = pkgs.python313.withPackages (ps: [
            toxPackage
            toxUv
          ]);

          # Tox installs upstream manylinux executables such as Ruff, Rumdl, and
          # Ty. Their conventional ELF interpreter is absent on NixOS. Running
          # only tox in an FHS environment keeps project tox files unchanged and
          # avoids requiring host-wide nix-ld or replacing project dependencies
          # with Nix packages. The rest of the development shell remains native.
          toxFhs = pkgs.buildFHSEnv {
            name = "tox";
            targetPkgs =
              _:
              [
                pkgs.nodejs
                pkgs.python314
                pkgs.python315
                pkgs.stdenv.cc
                pkgs.uv
                toxEnv
              ]
              ++ nativeLibraries
              ++ gstPackages;
            runScript = "${toxEnv}/bin/tox";
          };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.meson
              pkgs.ninja
              pkgs.pkg-config
              pkgs.python313
              pkgs.python314
              pkgs.python315
              pkgs.stdenv.cc
              pkgs.uv
              toxFhs
            ];

            buildInputs = nativeLibraries ++ gstPackages;

            UV_PYTHON_DOWNLOADS = "never";
            TOX_UV_PATH = "${pkgs.uv}/bin/uv";
            # Keep Pyright from downloading another non-Nix Node executable.
            PYRIGHT_PYTHON_GLOBAL_NODE = "1";

            shellHook = ''
              export CPATH="${includePath}''${CPATH:+:$CPATH}"
              export GI_TYPELIB_PATH="${giTypelibPath}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
              export GST_PLUGIN_SYSTEM_PATH_1_0="${gstPluginPath}''${GST_PLUGIN_SYSTEM_PATH_1_0:+:$GST_PLUGIN_SYSTEM_PATH_1_0}"
              export TOX_OVERRIDE="''${TOX_OVERRIDE:+$TOX_OVERRIDE;}tool.tox.env_run_base.pass_env+=NIX_*,PKG_CONFIG_PATH,CPATH,GI_TYPELIB_PATH,GST_PLUGIN_SYSTEM_PATH_1_0,PYRIGHT_PYTHON_GLOBAL_NODE"
            '';
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
