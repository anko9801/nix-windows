{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.nushell;
in
{
  options.programs.nushell = {
    enable = lib.mkEnableOption "Nushell";

    configFile = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Nushell config.nu content.";
    };

    envFile = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Nushell env.nu content.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.configFile != "") {
        windows.file."%APPDATA%/nushell/config.nu".text = cfg.configFile;
      })
      (lib.mkIf (cfg.envFile != "") {
        windows.file."%APPDATA%/nushell/env.nu".text = cfg.envFile;
      })
    ]
  );
}
