{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.espanso;
  yamlFormat = pkgs.formats.yaml { };
in
{
  options.programs.espanso = {
    enable = lib.mkEnableOption "Espanso text expander";

    config = lib.mkOption {
      inherit (yamlFormat) type;
      default = { };
      description = "Espanso default config (config/default.yml).";
    };

    matches = lib.mkOption {
      type = lib.types.attrsOf yamlFormat.type;
      default = { };
      example = {
        "base" = {
          matches = [
            {
              trigger = ":date";
              replace = "{{date}}";
            }
          ];
        };
      };
      description = ''
        Espanso match files. Attribute names become filenames
        under match/ directory (without .yml extension).
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.config != { }) {
        windows.file."%APPDATA%/espanso/config/default.yml".source =
          yamlFormat.generate "espanso-default.yml" cfg.config;
      })
      {
        windows.file = lib.mapAttrs' (name: value: {
          name = "%APPDATA%/espanso/match/${name}.yml";
          value.source = yamlFormat.generate "espanso-${name}.yml" value;
        }) cfg.matches;
      }
    ]
  );
}
