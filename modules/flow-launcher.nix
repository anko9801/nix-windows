{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.flow-launcher;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.flow-launcher = {
    enable = lib.mkEnableOption "Flow Launcher";

    settings = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      description = "Flow Launcher user settings (Settings.json).";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.settings != { }) {
        windows.file."%APPDATA%/FlowLauncher/Settings/Settings.json".source =
          jsonFormat.generate "flow-launcher-settings.json" cfg.settings;
      })
    ]
  );
}
