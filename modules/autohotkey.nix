{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.autohotkey;
in
{
  options.programs.autohotkey = {
    enable = lib.mkEnableOption "AutoHotkey";

    scripts = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = { };
      example = {
        "remap.ahk" = ''
          #Requires AutoHotkey v2.0
          CapsLock::Ctrl
        '';
      };
      description = ''
        AHK scripts to deploy. Attribute names are filenames,
        values are script contents. Deployed to %USERPROFILE%/Documents/AutoHotkey/.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    windows.file = lib.mapAttrs' (name: content: {
      name = "%USERPROFILE%/Documents/AutoHotkey/${name}";
      value.text = content;
    }) cfg.scripts;
  };
}
