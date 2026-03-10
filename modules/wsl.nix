# WSL configuration
# Manages both:
#   .wslconfig  → %USERPROFILE%/.wslconfig  (global VM settings, Windows-side)
#   wsl.conf    → %USERPROFILE%/.config/wsl/wsl.conf (per-distro, staged for /etc/)
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.wsl;

  primitiveType =
    with lib.types;
    oneOf [
      bool
      int
      float
      str
    ];

  sectionType = lib.types.attrsOf primitiveType;

  toINI =
    sections:
    lib.generators.toINI {
      mkKeyValue = lib.generators.mkKeyValueDefault {
        mkValueString = v: if builtins.isBool v then if v then "true" else "false" else toString v;
      } "=";
    } sections;
in
{
  options.programs.wsl = {
    enable = lib.mkEnableOption "WSL configuration";

    # .wslconfig (Windows-side, global)
    settings = lib.mkOption {
      type = sectionType;
      default = { };
      description = "[wsl2] section of .wslconfig.";
    };

    experimental = lib.mkOption {
      type = sectionType;
      default = { };
      description = "[experimental] section of .wslconfig.";
    };

    # wsl.conf (Linux-side, per-distro)
    conf = lib.mkOption {
      type = lib.types.attrsOf sectionType;
      default = { };
      example = {
        boot.systemd = true;
        interop.enabled = true;
      };
      description = "wsl.conf sections (boot, network, interop, automount, user).";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.settings != { } || cfg.experimental != { }) {
        windows.file."%USERPROFILE%/.wslconfig".text = toINI (
          lib.filterAttrs (_: v: v != { }) {
            wsl2 = cfg.settings;
            inherit (cfg) experimental;
          }
        );
      })

      (lib.mkIf (cfg.conf != { }) {
        windows.file."%USERPROFILE%/.config/wsl/wsl.conf".text = toINI cfg.conf;
      })
    ]
  );
}
