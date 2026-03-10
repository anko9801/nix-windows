# VS Code configuration
# Follows HM's programs/vscode pattern:
#   - structured keybinding submodule (key, command, when, args)
#   - JSON format type for settings
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;

  cfg = config.programs.vscode;
  jsonFormat = pkgs.formats.json { };

  variantConfigDirs = {
    "vscode" = "%APPDATA%/Code/User";
    "vscode-insiders" = "%APPDATA%/Code - Insiders/User";
    "vscodium" = "%APPDATA%/VSCodium/User";
  };

  configDir = variantConfigDirs.${cfg.variant};

  keybindingType = types.submodule {
    options = {
      key = mkOption {
        type = types.str;
        description = "Key combination.";
      };
      command = mkOption {
        type = types.str;
        description = "VS Code command to execute.";
      };
      when = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional context filter.";
      };
      args = mkOption {
        type = types.nullOr jsonFormat.type;
        default = null;
        description = "Optional command arguments.";
      };
    };
  };

  serializeKeybindings = map (
    kb:
    lib.filterAttrs (_: v: v != null) {
      inherit (kb)
        key
        command
        when
        args
        ;
    }
  );
in
{
  options.programs.vscode = {
    enable = mkEnableOption "VS Code";

    variant = mkOption {
      type = types.enum [
        "vscode"
        "vscode-insiders"
        "vscodium"
      ];
      default = "vscode";
      description = "VS Code variant. Determines the configuration directory.";
    };

    settings = mkOption {
      inherit (jsonFormat) type;
      default = { };
      description = "VS Code user settings (settings.json).";
    };

    keybindings = mkOption {
      type = types.listOf keybindingType;
      default = [ ];
      description = "VS Code keybindings (keybindings.json).";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    (mkIf (cfg.settings != { }) {
      windows.file."${configDir}/settings.json".source =
        jsonFormat.generate "vscode-user-settings.json" cfg.settings;
    })

    (mkIf (cfg.keybindings != [ ]) {
      windows.file."${configDir}/keybindings.json".source =
        jsonFormat.generate "vscode-keybindings.json" (serializeKeybindings cfg.keybindings);
    })
  ]);
}
