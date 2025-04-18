{
  description = "A Nix flake for ComfyUI with Python 3.12";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # Allow unfree packages
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            allowUnsupportedSystem = true;
          };
        };
        
        # ComfyUI source
        comfyui-src = pkgs.fetchFromGitHub {
          owner = "comfyanonymous";
          repo = "ComfyUI";
          rev = "a14c2fc3565277dfe8ab0ecb22a86c1d0a1f72cf"; # v0.3.28
          hash = "sha256-d+RxxBmkwuZwRvPfdHGjZ7pllvbIcoITn9Z/1k3m4KE=";
        };
        
        # ComfyUI frontend package
        comfyui-frontend-package = pkgs.python312Packages.buildPythonPackage {
          pname = "comfyui-frontend-package";
          version = "1.17.0";
          format = "wheel";
          
          src = pkgs.fetchurl {
            url = "https://files.pythonhosted.org/packages/py3/c/comfyui_frontend_package/comfyui_frontend_package-1.17.0-py3-none-any.whl";
            hash = "sha256-g6P84Vkh81SYHkxgsHHSHAgrxV4tIdzcZ1q/PX7rEZE=";
          };
          
          doCheck = false;
        };
        
        # Model downloader custom node
        modelDownloaderDir = ./src/custom_nodes/model_downloader;
        
        # Python environment with minimal dependencies
        # Most dependencies will be installed via pip in the virtual environment
        pythonEnv = pkgs.python312.buildEnv.override {
          extraLibs = with pkgs.python312Packages; [
            setuptools wheel pip virtualenv
            requests rich
            comfyui-frontend-package
          ];
          ignoreCollisions = true;
        };
        
        # Copy our persistence scripts to the nix store
        persistenceScript = ./src/persistence/persistence.py;
        persistenceMainScript = ./src/persistence/main.py;
        
        # Process each script file individually
        configScript = pkgs.substituteAll {
          src = ./scripts/config.sh;
          pythonEnv = pythonEnv;
          comfyuiSrc = comfyui-src;
          modelDownloaderDir = modelDownloaderDir;
          persistenceScript = persistenceScript;
          persistenceMainScript = persistenceMainScript;
        };
        
        loggerScript = pkgs.substituteAll {
          src = ./scripts/logger.sh;
          pythonEnv = pythonEnv;
        };
        
        installScript = pkgs.substituteAll {
          src = ./scripts/install.sh;
          pythonEnv = pythonEnv;
        };
        
        persistenceShScript = pkgs.substituteAll {
          src = ./scripts/persistence.sh;
          pythonEnv = pythonEnv;
        };
        
        runtimeScript = pkgs.substituteAll {
          src = ./scripts/runtime.sh;
          pythonEnv = pythonEnv;
        };
        
        # Main launcher script with substitutions
        launcherScript = pkgs.substituteAll {
          src = ./scripts/launcher.sh;
          pythonEnv = pythonEnv;
          comfyuiSrc = comfyui-src;
          modelDownloaderDir = modelDownloaderDir;
          persistenceScript = persistenceScript;
          persistenceMainScript = persistenceMainScript;
        };
        
        # Create a directory with all scripts
        scriptDir = pkgs.runCommand "comfy-ui-scripts" {} ''
          mkdir -p $out
          cp ${configScript} $out/config.sh
          cp ${loggerScript} $out/logger.sh
          cp ${installScript} $out/install.sh
          cp ${persistenceShScript} $out/persistence.sh
          cp ${runtimeScript} $out/runtime.sh
          cp ${launcherScript} $out/launcher.sh
          chmod +x $out/*.sh
        '';
        
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "comfy-ui";
          version = "0.1.0";
          
          src = comfyui-src;
          
          nativeBuildInputs = [ pkgs.makeWrapper pythonEnv ];
          buildInputs = [ pkgs.libGL pkgs.libGLU ];
          
          # Skip build and configure phases
          dontBuild = true;
          dontConfigure = true;
          
          installPhase = ''
            # Create directories
            mkdir -p "$out/bin"
            mkdir -p "$out/share/comfy-ui"
            
            # Copy ComfyUI files
            cp -r ${comfyui-src}/* "$out/share/comfy-ui/"
            
            # Create scripts directory
            mkdir -p "$out/share/comfy-ui/scripts"
            
            # Copy all script files
            cp -r ${scriptDir}/* "$out/share/comfy-ui/scripts/"
            
            # Install the launcher script
            ln -s "$out/share/comfy-ui/scripts/launcher.sh" "$out/bin/comfy-ui-launcher"
            chmod +x "$out/bin/comfy-ui-launcher"
            
            # Create a symlink to the launcher
            ln -s "$out/bin/comfy-ui-launcher" "$out/bin/comfy-ui"
          '';
              
          meta = with pkgs.lib; {
            description = "ComfyUI with Python 3.12";
            homepage = "https://github.com/comfyanonymous/ComfyUI";
            license = licenses.gpl3;
            platforms = platforms.all;
            mainProgram = "comfy-ui";
          };
        };
        
        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.default;
          name = "comfy-ui";
        };
        
        devShells.default = pkgs.mkShell {
          packages = [ pythonEnv ];
          
          shellHook = ''
            echo "ComfyUI development environment activated"
            export COMFY_USER_DIR="$HOME/.config/comfy-ui"
            mkdir -p "$COMFY_USER_DIR"
            echo "User data will be stored in $COMFY_USER_DIR"
            export PYTHONPATH="$PWD:$PYTHONPATH"
          '';
        };
      in {
        # Reference the package defined in the let block
        inherit packages;
        
        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.default;
          name = "comfy-ui";
        };
        
        devShells.default = pkgs.mkShell {
          packages = [ pythonEnv ];
          
          shellHook = ''
            echo "ComfyUI development environment activated"
            export COMFY_USER_DIR="$HOME/.config/comfy-ui"
            mkdir -p "$COMFY_USER_DIR"
            echo "User data will be stored in $COMFY_USER_DIR"
            export PYTHONPATH="$PWD:$PYTHONPATH"
          '';
        };
      }
    );
}
