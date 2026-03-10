# Kanata key remapper configuration
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.kanata;
in
{
  options.programs.kanata = {
    enable = lib.mkEnableOption "kanata key remapper";

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Kanata configuration content.";
    };

    defcfg = lib.mkOption {
      type = lib.types.lines;
      default = ''
        (defcfg
          process-unmapped-keys yes
        )
      '';
      description = "Kanata defcfg block.";
    };
  };

  config = lib.mkIf cfg.enable {
    windows.file."%USERPROFILE%/.config/kanata/kanata.kbd".text =
      cfg.defcfg + lib.optionalString (cfg.extraConfig != "") ("\n" + cfg.extraConfig);
  };
}
