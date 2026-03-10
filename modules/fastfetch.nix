{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.fastfetch;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.fastfetch = {
    enable = lib.mkEnableOption "fastfetch system info";

    settings = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      description = "Fastfetch configuration (JSON).";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.settings != { }) {
        windows.file."%LOCALAPPDATA%/fastfetch/config.jsonc".source =
          jsonFormat.generate "fastfetch-config.json" cfg.settings;
      })
    ]
  );
}
