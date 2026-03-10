{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.alacritty;
  tomlFormat = pkgs.formats.toml { };
in
{
  options.programs.alacritty = {
    enable = lib.mkEnableOption "Alacritty terminal emulator";

    settings = lib.mkOption {
      inherit (tomlFormat) type;
      default = { };
      description = "Alacritty configuration (serialized to TOML).";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.settings != { }) {
        windows.file."%APPDATA%/alacritty/alacritty.toml".source =
          tomlFormat.generate "alacritty.toml" cfg.settings;
      })
    ]
  );
}
