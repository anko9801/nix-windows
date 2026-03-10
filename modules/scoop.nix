{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.scoop;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.scoop = {
    enable = lib.mkEnableOption "Scoop package manager";

    config = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      example = {
        use_lessmsi = true;
        aria2-enabled = true;
      };
      description = "Scoop configuration (config.json).";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.config != { }) {
        windows.file."%USERPROFILE%/.config/scoop/config.json".source =
          jsonFormat.generate "scoop-config.json" cfg.config;
      })
    ]
  );
}
