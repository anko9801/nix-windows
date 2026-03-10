{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.wezterm;
in
{
  options.programs.wezterm = {
    enable = lib.mkEnableOption "WezTerm terminal emulator";

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "WezTerm configuration (Lua).";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.extraConfig != "") {
        windows.file."%USERPROFILE%/.wezterm.lua".text = cfg.extraConfig;
      })
    ]
  );
}
