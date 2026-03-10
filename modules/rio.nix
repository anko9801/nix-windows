{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.rio;
  tomlFormat = pkgs.formats.toml { };
in
{
  options.programs.rio = {
    enable = lib.mkEnableOption "Rio terminal";

    settings = lib.mkOption {
      inherit (tomlFormat) type;
      default = { };
      description = "Rio terminal configuration (serialized to TOML).";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.settings != { }) {
        windows.file."%LOCALAPPDATA%/rio/config.toml".source =
          tomlFormat.generate "rio-config.toml" cfg.settings;
      })
    ]
  );
}
