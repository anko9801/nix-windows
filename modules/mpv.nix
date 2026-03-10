{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.mpv;

  renderConfig = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: "${k}=${toString v}") cfg.settings
  );
in
{
  options.programs.mpv = {
    enable = lib.mkEnableOption "mpv media player";

    settings = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.oneOf [
          lib.types.str
          lib.types.int
          lib.types.bool
        ]
      );
      default = { };
      example = {
        hwdec = "auto";
        vo = "gpu-next";
        keep-open = true;
      };
      description = "mpv configuration options (mpv.conf).";
    };

    bindings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "WHEEL_UP" = "add volume 2";
        "WHEEL_DOWN" = "add volume -2";
      };
      description = "mpv key bindings (input.conf).";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.settings != { }) {
        windows.file."%APPDATA%/mpv/mpv.conf".text = renderConfig + "\n";
      })
      (lib.mkIf (cfg.bindings != { }) {
        windows.file."%APPDATA%/mpv/input.conf".text =
          lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k} ${v}") cfg.bindings) + "\n";
      })
    ]
  );
}
