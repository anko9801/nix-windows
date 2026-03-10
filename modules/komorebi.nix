# Komorebi tiling window manager configuration
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.komorebi;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.komorebi = {
    enable = lib.mkEnableOption "komorebi window manager";

    settings = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      description = "Komorebi configuration (serialized to JSON).";
    };

  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        programs.komorebi.settings."$schema" =
          lib.mkDefault "https://raw.githubusercontent.com/LGUG2Z/komorebi/master/schema.json";
      }
      {
        windows.file."%USERPROFILE%/.config/komorebi/komorebi.json".source =
          jsonFormat.generate "komorebi.json" cfg.settings;
      }
    ]
  );
}
