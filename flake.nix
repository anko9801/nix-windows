{
  description = "Declarative Windows configuration manager (runs from WSL)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      treefmt-nix,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      mkNixWindows = import ./lib/mk-nix-windows.nix { inherit (nixpkgs) lib; };

      moduleSet = {
        activation = ./modules/activation.nix;
        assertions = ./modules/assertions.nix;
        base = ./modules/base.nix;
        checks = ./modules/checks.nix;
        defaults = ./modules/defaults.nix;
        environment = ./modules/environment.nix;
        registry = ./modules/registry.nix;
        services = ./modules/services.nix;
        komorebi = ./modules/komorebi.nix;
        whkd = ./modules/whkd.nix;
        windows-terminal = ./modules/windows-terminal.nix;
        kanata = ./modules/kanata.nix;
        git = ./modules/git.nix;
        vscode = ./modules/vscode.nix;
        starship = ./modules/starship.nix;
        powershell = ./modules/powershell.nix;
        tasks = ./modules/tasks.nix;
        winget = ./modules/winget.nix;
        wsl = ./modules/wsl.nix;
        ssh = ./modules/ssh.nix;
        glazewm = ./modules/glazewm.nix;
        autohotkey = ./modules/autohotkey.nix;
        flow-launcher = ./modules/flow-launcher.nix;
        wezterm = ./modules/wezterm.nix;
        alacritty = ./modules/alacritty.nix;
        espanso = ./modules/espanso.nix;
        powertoys = ./modules/powertoys.nix;
        firefox = ./modules/firefox.nix;
        nushell = ./modules/nushell.nix;
        oh-my-posh = ./modules/oh-my-posh.nix;
        fastfetch = ./modules/fastfetch.nix;
        mpv = ./modules/mpv.nix;
        rio = ./modules/rio.nix;
      };

      builtinModules = nixpkgs.lib.attrValues moduleSet;
    in
    {
      lib = {
        inherit mkNixWindows;
      };

      nixWindowsModules = moduleSet // {
        default = builtinModules;
      };
    }
    // {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          exampleConfig = mkNixWindows {
            inherit pkgs;
            modules = builtinModules ++ [
              {
                system.stateVersion = 1;
                windows.username = "example";
                programs.git = {
                  enable = true;
                  settings.user = {
                    name = "Example User";
                    email = "user@example.com";
                  };
                };
              }
            ];
          };

          optionsDocs = pkgs.nixosOptionsDoc {
            inherit (exampleConfig.passthru) options;
            warningsAreErrors = false;
            transformOptions =
              opt:
              opt
              // {
                declarations = [ ];
              };
          };
        in
        {
          example = exampleConfig;
          docs = optionsDocs.optionsCommonMark;
        }
      );

      formatter = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        (treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }).config.build.wrapper
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          testSuite = import ./tests {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
        in
        {
          example = mkNixWindows {
            inherit pkgs;
            modules = builtinModules ++ [
              {
                system.stateVersion = 1;
                windows.username = "testuser";
                programs.git = {
                  enable = true;
                  settings.user = {
                    name = "Test";
                    email = "test@example.com";
                  };
                };
              }
            ];
          };
        }
        // testSuite.tests
      );
    };
}
