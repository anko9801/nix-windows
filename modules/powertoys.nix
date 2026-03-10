{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.powertoys;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.powertoys = {
    enable = lib.mkEnableOption "Microsoft PowerToys";

    settings = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      description = "PowerToys general settings.";
    };

    modules = lib.mkOption {
      type = lib.types.attrsOf jsonFormat.type;
      default = { };
      example = {
        "FancyZones" = {
          "fancyzones_editor_hotkey" = "Win+Shift+Backtick";
        };
      };
      description = ''
        Per-module PowerToys settings. Attribute names are module names
        (e.g. FancyZones, PowerRename). Each generates a settings.json
        under the module directory.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.settings != { }) {
        windows.file."%LOCALAPPDATA%/Microsoft/PowerToys/settings.json".source =
          jsonFormat.generate "powertoys-settings.json" cfg.settings;
      })
      {
        windows.file = lib.mapAttrs' (name: value: {
          name = "%LOCALAPPDATA%/Microsoft/PowerToys/${name}/settings.json";
          value.source = jsonFormat.generate "powertoys-${name}-settings.json" value;
        }) cfg.modules;
      }
    ]
  );
}
