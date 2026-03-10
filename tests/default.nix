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
