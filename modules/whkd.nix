# whkd - Windows Hot Key Daemon configuration
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.whkd;

  configText =
    let
      shellLine = lib.optionalString (cfg.shell != null) ".shell ${cfg.shell}\n\n";
      bindingLines = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (keys: command: "${keys} : ${command}") cfg.bindings
      );
    in
    shellLine + bindingLines + "\n";
in
{
  options.programs.whkd = {
    enable = lib.mkEnableOption "whkd hotkey daemon";

    shell = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "powershell";
      description = "Shell to use for executing commands.";
    };

    bindings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "alt + win + h" = "komorebic focus left";
        "alt + win + j" = "komorebic focus down";
      };
      description = "Key bindings (key combination → command).";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Raw whkdrc content appended to generated config.";
    };

  };

  config = lib.mkIf cfg.enable {
    windows.file."%USERPROFILE%/.config/whkdrc".text =
      configText + lib.optionalString (cfg.extraConfig != "") cfg.extraConfig;
  };
}
