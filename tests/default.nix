# Test framework for nix-windows
# Inspired by nix-darwin's test runner: builds test configurations
# and inspects the resulting activation scripts.
{ pkgs, lib }:
let
  mkNixWindows = import ../lib/mk-nix-windows.nix { inherit lib; };
  builtinModules = import ./module-list.nix;

  # Build a nix-windows configuration with the given test module
  mkTest =
    {
      name,
      config,
      assertions ? (_: [ ]),
    }:
    let
      result = mkNixWindows {
        inherit pkgs;
        modules = builtinModules ++ [
          {
            system.stateVersion = 1;
            windows.username = "testuser";
          }
          config
        ];
      };

      script = result.passthru.activationScript;
      cfg = result.passthru.config;

      testAssertions = assertions {
        inherit script cfg result;
      };

      failedAssertions = builtins.filter (a: !a.ok) testAssertions;

      report =
        if failedAssertions == [ ] then
          "PASS: ${name} (${toString (builtins.length testAssertions)} assertions)"
        else
          builtins.throw (
            "FAIL: ${name}\n" + lib.concatMapStringsSep "\n" (a: "  - ${a.msg}") failedAssertions
          );
    in
    pkgs.runCommand "nw-test-${name}" { } ''
      echo "${report}"
      touch $out
    '';

  # Helper: check that a string contains a substring
  assertContains = script: needle: {
    ok = lib.hasInfix needle script;
    msg = "expected activation script to contain: ${needle}";
  };

  # Helper: check that a string does NOT contain a substring
  assertNotContains = script: needle: {
    ok = !(lib.hasInfix needle script);
    msg = "expected activation script NOT to contain: ${needle}";
  };

  # Helper: find the first index of a substring in a string
  indexOf =
    needle: s:
    let
      len = builtins.stringLength needle;
      sLen = builtins.stringLength s;
      check =
        i:
        if i > sLen - len then
          -1
        else if builtins.substring i len s == needle then
          i
        else
          check (i + 1);
    in
    check 0;
in
{
  inherit mkTest assertContains assertNotContains;

  tests = {
    minimal = mkTest {
      name = "minimal";
      config = { };
      assertions =
        { script, ... }:
        [
          {
            ok = builtins.isString script;
            msg = "activation script should be a string";
          }
        ];
    };

    file-deploy = mkTest {
      name = "file-deploy";
      config = {
        windows.file."%USERPROFILE%/.config/test.txt" = {
          text = "hello world";
        };
      };
      assertions =
        { script, ... }:
        [
          (assertContains script "[files] Deploying 1 file(s)")
          (assertContains script "$WIN_USERPROFILE/.config/test.txt")
        ];
    };

    registry = mkTest {
      name = "registry";
      config = {
        system.registry.HKCU.Software.TestApp.Setting = 42;
      };
      assertions =
        { script, ... }:
        [
          (assertContains script "[registry]")
          (assertContains script "TestApp")
        ];
    };

    defaults-explorer = mkTest {
      name = "defaults-explorer";
      config = {
        system.defaults.explorer.showFileExtensions = true;
      };
      assertions =
        { script, cfg, ... }:
        [
          {
            ok =
              cfg.system.registry.HKCU.Software.Microsoft.Windows.CurrentVersion.Explorer.Advanced.HideFileExt
              == 0;
            msg = "showFileExtensions=true should set HideFileExt=0";
          }
          (assertContains script "[registry]")
        ];
    };

    defaults-appearance = mkTest {
      name = "defaults-appearance";
      config = {
        system.defaults.appearance.appsTheme = "dark";
      };
      assertions =
        { cfg, ... }:
        [
          {
            ok =
              cfg.system.registry.HKCU.Software.Microsoft.Windows.CurrentVersion.Themes.Personalize.AppsUseLightTheme
              == 0;
            msg = "appsTheme=dark should set AppsUseLightTheme=0";
          }
        ];
    };

    environment-variables = mkTest {
      name = "environment-variables";
      config = {
        environment.variables.MY_VAR = "my_value";
      };
      assertions =
        { script, ... }:
        [
          (assertContains script "[environment]")
          (assertContains script "MY_VAR")
          (assertContains script "my_value")
        ];
    };

    environment-path = mkTest {
      name = "environment-path";
      config = {
        environment.userPath = [ "C:\\Tools" ];
      };
      assertions =
        { script, ... }:
        [
          (assertContains script "[environment]")
          (assertContains script "C:\\Tools")
          (assertContains script "-inotcontains")
        ];
    };

    pre-post-hooks = mkTest {
      name = "pre-post-hooks";
      config = {
        system = {
          preActivation = "echo PRE_HOOK_MARKER";
          postActivation = "echo POST_HOOK_MARKER";
        };
      };
      assertions =
        { script, ... }:
        [
          (assertContains script "PRE_HOOK_MARKER")
          (assertContains script "POST_HOOK_MARKER")
        ];
    };

    checks-enabled = mkTest {
      name = "checks-enabled";
      config = { };
      assertions =
        { script, ... }:
        [
          (assertContains script "[checks] Running pre-activation checks")
          (assertContains script "NW_WIN_BUILD")
          (assertContains script "NW_PS_VER")
        ];
    };

    git-config = mkTest {
      name = "git-config";
      config = {
        programs.git = {
          enable = true;
          settings.user = {
            name = "Test User";
            email = "test@example.com";
          };
        };
      };
      assertions =
        { script, cfg, ... }:
        [
          (assertContains script "[files]")
          {
            ok = cfg.windows.file ? "%USERPROFILE%/.gitconfig";
            msg = "git module should create a .gitconfig file entry";
          }
        ];
    };

    # DAG ordering: checks (before writeBoundary) < files (after writeBoundary) < registry (after fonts) < postActivation
    dag-ordering = mkTest {
      name = "dag-ordering";
      config = {
        system = {
          preActivation = "echo __PRE__";
          postActivation = "echo __POST__";
          registry.HKCU.Software.OrderTest.Val = 1;
        };
        windows.file."%USERPROFILE%/.config/order-test" = {
          text = "test";
        };
      };
      assertions =
        { script, ... }:
        let
          checksIdx = indexOf "[checks]" script;
          filesIdx = indexOf "[files]" script;
          registryIdx = indexOf "[registry]" script;
          preIdx = indexOf "__PRE__" script;
          postIdx = indexOf "__POST__" script;
        in
        [
          {
            ok = preIdx >= 0 && checksIdx >= 0;
            msg = "preActivation and checks should both be present";
          }
          {
            ok = checksIdx >= 0 && filesIdx >= 0 && checksIdx < filesIdx;
            msg = "checks (before writeBoundary) should come before files (after writeBoundary)";
          }
          {
            ok = filesIdx >= 0 && registryIdx >= 0 && filesIdx < registryIdx;
            msg = "files should come before registry (registry depends on fonts which depends on files)";
          }
          {
            ok = registryIdx >= 0 && postIdx >= 0 && registryIdx < postIdx;
            msg = "registry should come before postActivation";
          }
        ];
    };

    extend-modules = mkTest {
      name = "extend-modules";
      config = { };
      assertions =
        { result, ... }:
        let
          extended = result.passthru.extendModules {
            modules = [
              {
                environment.variables.EXTENDED = "yes";
              }
            ];
          };
          extScript = extended.passthru.activationScript;
        in
        [
          (assertContains extScript "EXTENDED")
          (assertContains extScript "yes")
        ];
    };

    # Path alias: appDataFile maps to windows.file with %APPDATA% prefix
    path-aliases = mkTest {
      name = "path-aliases";
      config = {
        windows.appDataFile."Code/User/settings.json" = {
          text = "{}";
        };
        windows.localAppDataFile."MyApp/config.json" = {
          text = "{}";
        };
      };
      assertions =
        { cfg, ... }:
        [
          {
            ok = cfg.windows.file ? "%APPDATA%/Code/User/settings.json";
            msg = "appDataFile should map to %APPDATA%/ prefix";
          }
          {
            ok = cfg.windows.file ? "%LOCALAPPDATA%/MyApp/config.json";
            msg = "localAppDataFile should map to %LOCALAPPDATA%/ prefix";
          }
        ];
    };

    # Git includes: conditional and unconditional
    git-includes = mkTest {
      name = "git-includes";
      config = {
        programs.git = {
          enable = true;
          settings.user = {
            name = "Test";
            email = "test@test.com";
          };
          includes = [
            { path = "~/.gitconfig-work"; }
            {
              path = "~/.gitconfig-oss";
              condition = "gitdir:~/oss/";
            }
          ];
        };
      };
      assertions =
        { cfg, ... }:
        let
          gitconfigText = cfg.windows.file."%USERPROFILE%/.gitconfig".text;
        in
        [
          {
            ok = lib.hasInfix "[include]" gitconfigText;
            msg = "gitconfig should have [include] section";
          }
          {
            ok = lib.hasInfix "gitconfig-work" gitconfigText;
            msg = "gitconfig should reference gitconfig-work";
          }
          {
            ok = lib.hasInfix "includeIf" gitconfigText;
            msg = "gitconfig should have includeIf section";
          }
          {
            ok = lib.hasInfix "gitdir:~/oss/" gitconfigText;
            msg = "gitconfig should have gitdir condition";
          }
        ];
    };

    # Starship PowerShell integration
    starship-ps-integration = mkTest {
      name = "starship-ps-integration";
      config = {
        programs.starship.enable = true;
        programs.powershell.enable = true;
      };
      assertions =
        { cfg, ... }:
        let
          profilePath = "%USERPROFILE%/Documents/PowerShell/Microsoft.PowerShell_profile.ps1";
          profileText = cfg.windows.file.${profilePath}.text;
        in
        [
          {
            ok = lib.hasInfix "starship init powershell" profileText;
            msg = "PowerShell profile should contain starship init";
          }
        ];
    };

    # SSH config generation
    ssh-config = mkTest {
      name = "ssh-config";
      config = {
        programs.ssh = {
          enable = true;
          matchBlocks = {
            "github.com" = {
              hostname = "github.com";
              user = "git";
              identityFile = "~/.ssh/id_ed25519";
            };
            "dev-server" = {
              hostname = "10.0.0.1";
              user = "deploy";
              port = 2222;
              forwardAgent = true;
            };
          };
        };
      };
      assertions =
        { cfg, ... }:
        let
          sshConfig = cfg.windows.file."%USERPROFILE%/.ssh/config".text;
        in
        [
          {
            ok = cfg.windows.file ? "%USERPROFILE%/.ssh/config";
            msg = "ssh module should create a config file entry";
          }
          {
            ok = lib.hasInfix "Host github.com" sshConfig;
            msg = "ssh config should contain Host github.com";
          }
          {
            ok = lib.hasInfix "IdentityFile ~/.ssh/id_ed25519" sshConfig;
            msg = "ssh config should contain IdentityFile";
          }
          {
            ok = lib.hasInfix "Port 2222" sshConfig;
            msg = "ssh config should contain Port";
          }
          {
            ok = lib.hasInfix "ForwardAgent yes" sshConfig;
            msg = "ssh config should contain ForwardAgent";
          }
        ];
    };

    # GlazeWM config
    glazewm-config = mkTest {
      name = "glazewm-config";
      config = {
        programs.glazewm = {
          enable = true;
          settings = {
            general = {
              border_width = 2;
            };
          };
        };
      };
      assertions =
        { cfg, ... }:
        [
          {
            ok = cfg.windows.file ? "%USERPROFILE%/.glzr/glazewm/config.yaml";
            msg = "glazewm module should create config.yaml file entry";
          }
        ];
    };

    # AutoHotkey script deployment
    autohotkey-scripts = mkTest {
      name = "autohotkey-scripts";
      config = {
        programs.autohotkey = {
          enable = true;
          scripts = {
            "remap.ahk" = "CapsLock::Ctrl";
            "launch.ahk" = "#n::Run notepad";
          };
        };
      };
      assertions =
        { cfg, ... }:
        [
          {
            ok = cfg.windows.file ? "%USERPROFILE%/Documents/AutoHotkey/remap.ahk";
            msg = "autohotkey should deploy remap.ahk";
          }
          {
            ok = cfg.windows.file ? "%USERPROFILE%/Documents/AutoHotkey/launch.ahk";
            msg = "autohotkey should deploy launch.ahk";
          }
          {
            ok = cfg.windows.file."%USERPROFILE%/Documents/AutoHotkey/remap.ahk".text == "CapsLock::Ctrl";
            msg = "remap.ahk should have correct content";
          }
        ];
    };

    # Flow Launcher settings
    flow-launcher-settings = mkTest {
      name = "flow-launcher-settings";
      config = {
        programs.flow-launcher = {
          enable = true;
          settings = {
            Hotkey = "Alt+Space";
            Language = "en";
          };
        };
      };
      assertions =
        { cfg, ... }:
        [
          {
            ok = cfg.windows.file ? "%APPDATA%/FlowLauncher/Settings/Settings.json";
            msg = "flow-launcher should create Settings.json file entry";
          }
        ];
    };

    # WezTerm config
    wezterm-config = mkTest {
      name = "wezterm-config";
      config = {
        programs.wezterm = {
          enable = true;
          extraConfig = ''
            local wezterm = require 'wezterm'
            return { font_size = 14.0 }
          '';
        };
      };
      assertions =
        { cfg, ... }:
        [
          {
            ok = cfg.windows.file ? "%USERPROFILE%/.wezterm.lua";
            msg = "wezterm should create .wezterm.lua file entry";
          }
        ];
    };

    # Alacritty config
    alacritty-config = mkTest {
      name = "alacritty-config";
      config = {
        programs.alacritty = {
          enable = true;
          settings = {
            font.size = 12;
          };
        };
      };
      assertions =
        { cfg, ... }:
        [
          {
            ok = cfg.windows.file ? "%APPDATA%/alacritty/alacritty.toml";
            msg = "alacritty should create alacritty.toml file entry";
          }
        ];
    };

    # Espanso config
    espanso-config = mkTest {
      name = "espanso-config";
      config = {
        programs.espanso = {
          enable = true;
          config = {
            toggle_key = "ALT";
          };
          matches = {
            "base" = {
              matches = [
                {
                  trigger = ":date";
                  replace = "{{date}}";
                }
              ];
            };
          };
        };
      };
      assertions =
        { cfg, ... }:
        [
          {
            ok = cfg.windows.file ? "%APPDATA%/espanso/config/default.yml";
            msg = "espanso should create default.yml config";
          }
          {
            ok = cfg.windows.file ? "%APPDATA%/espanso/match/base.yml";
            msg = "espanso should create base.yml match file";
          }
        ];
    };

    # PowerToys config
    powertoys-config = mkTest {
      name = "powertoys-config";
      config = {
        programs.powertoys = {
          enable = true;
          settings = {
            theme = "dark";
          };
          modules = {
            "FancyZones" = {
              "fancyzones_editor_hotkey" = "Win+Shift+Backtick";
            };
          };
        };
      };
      assertions =
        { cfg, ... }:
        [
          {
            ok = cfg.windows.file ? "%LOCALAPPDATA%/Microsoft/PowerToys/settings.json";
            msg = "powertoys should create settings.json";
          }
          {
            ok = cfg.windows.file ? "%LOCALAPPDATA%/Microsoft/PowerToys/FancyZones/settings.json";
            msg = "powertoys should create FancyZones/settings.json";
          }
        ];
    };

    # Firefox policies
    firefox-policies = mkTest {
      name = "firefox-policies";
      config = {
        programs.firefox = {
          enable = true;
          policies = {
            DisableTelemetry = true;
          };
        };
      };
      assertions =
        { cfg, ... }:
        [
          {
            ok = cfg.windows.file ? "%PROGRAMFILES%/Mozilla Firefox/distribution/policies.json";
            msg = "firefox should create policies.json";
          }
        ];
    };

    # Nushell config
    nushell-config = mkTest {
      name = "nushell-config";
      config = {
        programs.nushell = {
          enable = true;
          configFile = "$env.config.show_banner = false";
          envFile = "$env.PATH = ($env.PATH | prepend 'C:\\Tools')";
        };
      };
      assertions =
        { cfg, ... }:
        [
          {
            ok = cfg.windows.file ? "%APPDATA%/nushell/config.nu";
            msg = "nushell should create config.nu";
          }
          {
            ok = cfg.windows.file ? "%APPDATA%/nushell/env.nu";
            msg = "nushell should create env.nu";
          }
        ];
    };

    # Oh My Posh config
    oh-my-posh-config = mkTest {
      name = "oh-my-posh-config";
      config = {
        programs.oh-my-posh = {
          enable = true;
          enablePowerShellIntegration = false;
          settings = {
            "$schema" = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json";
            blocks = [ ];
          };
        };
      };
      assertions =
        { cfg, ... }:
        [
          {
            ok = cfg.windows.file ? "%USERPROFILE%/.config/oh-my-posh/config.json";
            msg = "oh-my-posh should create config.json";
          }
        ];
    };

    # Fastfetch config
    fastfetch-config = mkTest {
      name = "fastfetch-config";
      config = {
        programs.fastfetch = {
          enable = true;
          settings = {
            logo.type = "small";
          };
        };
      };
      assertions =
        { cfg, ... }:
        [
          {
            ok = cfg.windows.file ? "%LOCALAPPDATA%/fastfetch/config.jsonc";
            msg = "fastfetch should create config.jsonc";
          }
        ];
    };

    # mpv config
    mpv-config = mkTest {
      name = "mpv-config";
      config = {
        programs.mpv = {
          enable = true;
          settings = {
            hwdec = "auto";
            vo = "gpu-next";
          };
          bindings = {
            "WHEEL_UP" = "add volume 2";
          };
        };
      };
      assertions =
        { cfg, ... }:
        let
          mpvConf = cfg.windows.file."%APPDATA%/mpv/mpv.conf".text;
        in
        [
          {
            ok = cfg.windows.file ? "%APPDATA%/mpv/mpv.conf";
            msg = "mpv should create mpv.conf";
          }
          {
            ok = lib.hasInfix "hwdec=auto" mpvConf;
            msg = "mpv.conf should contain hwdec setting";
          }
          {
            ok = cfg.windows.file ? "%APPDATA%/mpv/input.conf";
            msg = "mpv should create input.conf";
          }
        ];
    };

    # Rio terminal config
    rio-config = mkTest {
      name = "rio-config";
      config = {
        programs.rio = {
          enable = true;
          settings = {
            editor = "code";
            fonts.size = 16;
          };
        };
      };
      assertions =
        { cfg, ... }:
        [
          {
            ok = cfg.windows.file ? "%LOCALAPPDATA%/rio/config.toml";
            msg = "rio should create config.toml";
          }
        ];
    };

    # Recursive directory deployment option
    recursive-file = mkTest {
      name = "recursive-file";
      config = {
        windows.file."%USERPROFILE%/.config/myapp" = {
          source = builtins.path {
            path = ../.;
            name = "test-source";
          };
          recursive = true;
        };
      };
      assertions =
        { cfg, ... }:
        [
          {
            ok = cfg.windows.file."%USERPROFILE%/.config/myapp".recursive;
            msg = "recursive option should be true";
          }
        ];
    };
  };
}
