# winget - Windows Package Manager DSC configuration
# Generates a configuration.dsc.yaml for `winget configure`
#
# Supports all Microsoft.WinGet.DSC resources:
#   WinGetPackage, WinGetSource, WinGetPackageManager,
#   WinGetUserSettings, WinGetAdminSettings
# Plus arbitrary DSC resources via assertions/resources.
{
  config,
  lib,
  deploy,
  dag,
  ...
}:
let
  cfg = config.programs.winget;

  inherit (lib) types;

  yaml = import ../lib/yaml.nix { inherit lib; };
  inherit (yaml) renderResource;

  # ── Directive / dependency helpers ─────────────────

  mkDirectives =
    d:
    lib.filterAttrs (_: v: v != null) {
      inherit (d) description module;
      inherit (d) allowPrerelease securityContext;
    };

  addMeta =
    r: opts:
    lib.optionalAttrs (opts.resourceId != null) { id = opts.resourceId; }
    // lib.optionalAttrs (opts.dependsOn != [ ]) { inherit (opts) dependsOn; }
    // (
      let
        dirs = mkDirectives opts;
      in
      lib.optionalAttrs (dirs != { }) { directives = dirs; }
    )
    // r;

  # ── Resource builders ──────────────────────────────

  mkPackageResource =
    pkg:
    addMeta {
      resource = "Microsoft.WinGet.DSC/WinGetPackage";
      settings = {
        id = pkg.id;
      }
      // lib.optionalAttrs (pkg.source != null) { source = pkg.source; }
      // lib.optionalAttrs (pkg.version != null) { Version = pkg.version; }
      // {
        Ensure = pkg.ensure;
      }
      // {
        UseLatest = pkg.useLatest;
      }
      // lib.optionalAttrs (pkg.matchOption != null) { MatchOption = pkg.matchOption; }
      // lib.optionalAttrs (pkg.installMode != null) { InstallMode = pkg.installMode; };
    } pkg;

  mkSourceResource =
    src:
    addMeta {
      resource = "Microsoft.WinGet.DSC/WinGetSource";
      settings = {
        Name = src.name;
        Argument = src.argument;
      }
      // lib.optionalAttrs (src.type != null) { Type = src.type; }
      // lib.optionalAttrs (src.trustLevel != null) { TrustLevel = src.trustLevel; }
      // lib.optionalAttrs (src.explicit != null) { Explicit = src.explicit; }
      // lib.optionalAttrs (src.priority != null) { Priority = src.priority; }
      // lib.optionalAttrs (src.ensure != null) { Ensure = src.ensure; };
    } src;

  mkManagerResource =
    mgr:
    addMeta {
      resource = "Microsoft.WinGet.DSC/WinGetPackageManager";
      settings =
        { }
        // lib.optionalAttrs (mgr.version != null) { Version = mgr.version; }
        // lib.optionalAttrs (mgr.useLatest != null) { UseLatest = mgr.useLatest; }
        // lib.optionalAttrs (mgr.useLatestPreRelease != null) {
          UseLatestPreRelease = mgr.useLatestPreRelease;
        };
    } mgr;

  mkUserSettingsResource =
    us:
    addMeta {
      resource = "Microsoft.WinGet.DSC/WinGetUserSettings";
      settings = {
        Settings = us.settings;
      }
      // lib.optionalAttrs (us.action != null) { Action = us.action; };
    } us;

  mkAdminSettingsResource =
    as':
    addMeta {
      resource = "Microsoft.WinGet.DSC/WinGetAdminSettings";
      settings = {
        Settings = as'.settings;
      };
    } as';

  mkGenericResource =
    r:
    addMeta {
      inherit (r) resource settings;
    } r;

  # ── Full YAML generation ───────────────────────────

  allAssertions = map mkGenericResource cfg.assertions;

  allResources =
    (lib.optional (cfg.manager != null) (mkManagerResource cfg.manager))
    ++ (map mkSourceResource cfg.sources)
    ++ (lib.optional (cfg.userSettings != null) (mkUserSettingsResource cfg.userSettings))
    ++ (lib.optional (cfg.adminSettings != null) (mkAdminSettingsResource cfg.adminSettings))
    ++ (map mkGenericResource cfg.resources)
    ++ (map mkPackageResource cfg.packages);

  configText =
    "# yaml-language-server: $schema=https://aka.ms/configuration-dsc-schema/0.2\n"
    + "properties:\n"
    + "  configurationVersion: ${cfg.configurationVersion}\n"
    + lib.optionalString (allAssertions != [ ]) (
      "  assertions:\n" + lib.concatMapStringsSep "\n" (renderResource 2) allAssertions + "\n"
    )
    + lib.optionalString (allResources != [ ]) (
      "  resources:\n" + lib.concatMapStringsSep "\n" (renderResource 2) allResources + "\n"
    );

  # ── Shared option fragments ────────────────────────

  directiveOptions = {
    description = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Human-readable description of this resource.";
    };
    allowPrerelease = lib.mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = "Whether to allow prerelease versions.";
    };
    securityContext = lib.mkOption {
      type = types.nullOr (
        types.enum [
          "current"
          "elevated"
          "restricted"
        ]
      );
      default = null;
      description = "Security context for this resource.";
    };
    module = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "DSC module name for this resource.";
    };
  };

  dependencyOptions = {
    resourceId = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Unique ID for this resource (used by dependsOn).";
    };
    dependsOn = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Resource IDs that this resource depends on.";
    };
  };

  settingsType = types.lazyAttrsOf (
    types.oneOf [
      types.bool
      types.int
      types.str
      (types.lazyAttrsOf types.anything)
    ]
  );

  # ── Option types ───────────────────────────────────

  genericResourceType = types.submodule {
    options = {
      resource = lib.mkOption { type = types.str; };
      settings = lib.mkOption {
        type = settingsType;
        default = { };
      };
    }
    // directiveOptions
    // dependencyOptions;
  };

  packageType = types.coercedTo types.str (id: { inherit id; }) (
    types.submodule {
      options = {
        id = lib.mkOption { type = types.str; };
        source = lib.mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        version = lib.mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        ensure = lib.mkOption {
          type = types.enum [
            "Present"
            "Absent"
          ];
          default = "Present";
        };
        useLatest = lib.mkOption {
          type = types.bool;
          default = true;
        };
        matchOption = lib.mkOption {
          type = types.nullOr (
            types.enum [
              "Equals"
              "EqualsCaseInsensitive"
              "StartsWithCaseInsensitive"
              "ContainsCaseInsensitive"
            ]
          );
          default = null;
        };
        installMode = lib.mkOption {
          type = types.nullOr (
            types.enum [
              "Default"
              "Silent"
              "Interactive"
            ]
          );
          default = null;
        };
      }
      // directiveOptions
      // dependencyOptions;
    }
  );

  sourceType = types.submodule {
    options = {
      name = lib.mkOption { type = types.str; };
      argument = lib.mkOption { type = types.str; };
      type = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      trustLevel = lib.mkOption {
        type = types.nullOr (
          types.enum [
            "Undefined"
            "None"
            "Trusted"
          ]
        );
        default = null;
      };
      explicit = lib.mkOption {
        type = types.nullOr types.bool;
        default = null;
      };
      priority = lib.mkOption {
        type = types.nullOr types.int;
        default = null;
      };
      ensure = lib.mkOption {
        type = types.nullOr (
          types.enum [
            "Present"
            "Absent"
          ]
        );
        default = null;
      };
    }
    // directiveOptions
    // dependencyOptions;
  };

  managerType = types.submodule {
    options = {
      version = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      useLatest = lib.mkOption {
        type = types.nullOr types.bool;
        default = null;
      };
      useLatestPreRelease = lib.mkOption {
        type = types.nullOr types.bool;
        default = null;
      };
    }
    // directiveOptions
    // dependencyOptions;
  };

  userSettingsType = types.submodule {
    options = {
      settings = lib.mkOption {
        type = types.attrsOf types.anything;
        description = "Winget user settings (settings.json).";
      };
      action = lib.mkOption {
        type = types.nullOr (
          types.enum [
            "Full"
            "Partial"
          ]
        );
        default = null;
        description = "Full replaces all settings, Partial merges.";
      };
    }
    // directiveOptions
    // dependencyOptions;
  };

  adminSettingsType = types.submodule {
    options = {
      settings = lib.mkOption {
        type = types.attrsOf types.bool;
        description = "Winget admin settings (key → enabled/disabled).";
      };
    }
    // directiveOptions
    // dependencyOptions;
  };

in
{
  options.programs.winget = {
    enable = lib.mkEnableOption "winget configure (DSC)";

    configurationVersion = lib.mkOption {
      type = types.str;
      default = "0.2.0";
    };

    # Preconditions
    assertions = lib.mkOption {
      type = types.listOf genericResourceType;
      default = [ ];
      description = "DSC assertions (preconditions).";
    };

    # WinGetPackageManager
    manager = lib.mkOption {
      type = types.nullOr managerType;
      default = null;
      description = "Manage winget itself (version, updates).";
    };

    # WinGetSource
    sources = lib.mkOption {
      type = types.listOf sourceType;
      default = [ ];
      description = "Winget source management.";
    };

    # WinGetUserSettings
    userSettings = lib.mkOption {
      type = types.nullOr userSettingsType;
      default = null;
      description = "Winget user settings (settings.json).";
    };

    # WinGetAdminSettings
    adminSettings = lib.mkOption {
      type = types.nullOr adminSettingsType;
      default = null;
      description = "Winget admin settings.";
    };

    # General DSC resources
    resources = lib.mkOption {
      type = types.listOf genericResourceType;
      default = [ ];
      description = "Arbitrary DSC resources.";
    };

    # WinGetPackage (sugar)
    packages = lib.mkOption {
      type = types.listOf packageType;
      default = [ ];
      description = "WinGetPackage resources. Strings coerced to {id}.";
    };

    autoApply = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        Run `winget configure` during activation to apply the generated DSC configuration.
        Requires winget to be installed on the Windows host.
      '';
    };

    onActivation.cleanup = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        Remove packages not declared in `programs.winget.packages` during activation.
        Compares installed packages (via `winget list`) with declared package IDs
        and uninstalls any that are not declared. Use with caution.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        windows.file."%USERPROFILE%/configuration.dsc.yaml".text = configText;
      }
      (lib.mkIf cfg.autoApply {
        system.activationScripts.winget = dag.entryAfter [ "environment" ] ''
          echo "[winget] Applying DSC configuration..."
          ${deploy.mkPowerShellExec ''
            winget configure --accept-configuration-agreements "$env:USERPROFILE\configuration.dsc.yaml"
          ''}
        '';
      })
      (lib.mkIf (cfg.autoApply && cfg.onActivation.cleanup) (
        let
          presentPkgs = builtins.filter (p: p.ensure == "Present") cfg.packages;
          declaredIds = map (p: p.id) presentPkgs;
          idListStr = lib.concatStringsSep "," (map deploy.escapePowerShell declaredIds);
        in
        {
          system.activationScripts.winget-cleanup = dag.entryAfter [ "winget" ] ''
            echo "[winget] Cleaning up undeclared packages..."
            ${deploy.mkPowerShellExec ''
              $declaredIds = @('${idListStr}' -split ',')
              $installed = winget list --accept-source-agreements 2>$null |
                Select-String -Pattern '^\S' |
                ForEach-Object { ($_ -split '\s{2,}')[0] }
              foreach ($pkg in $installed) {
                if ($pkg -and $declaredIds -inotcontains $pkg -and $pkg -ne 'Name') {
                  Write-Host "  Removing undeclared: $pkg"
                  winget uninstall --id $pkg --silent --accept-source-agreements 2>$null
                }
              }
            ''}
          '';
        }
      ))
    ]
  );
}
