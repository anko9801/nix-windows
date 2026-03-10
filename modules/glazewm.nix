{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.glazewm;
  yamlFormat = pkgs.formats.yaml { };
in
{
  options.programs.glazewm = {
    enable = lib.mkEnableOption "GlazeWM tiling window manager";

    settings = lib.mkOption {
      inherit (yamlFormat) type;
      default = { };
      description = "GlazeWM configuration (serialized to YAML).";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.settings != { }) {
        windows.file."%USERPROFILE%/.glzr/glazewm/config.yaml".source =
          yamlFormat.generate "glazewm-config.yaml" cfg.settings;
      })
    ]
  );
}
