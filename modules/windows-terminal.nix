# Windows Terminal configuration
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.windows-terminal;
  jsonFormat = pkgs.formats.json { };

  variantPaths = {
    "stable" =
      "%LOCALAPPDATA%/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json";
    "preview" =
      "%LOCALAPPDATA%/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json";
    "canary" =
      "%LOCALAPPDATA%/Packages/Microsoft.WindowsTerminalCanary_8wekyb3d8bbwe/LocalState/settings.json";
    "unpackaged" = "%LOCALAPPDATA%/Microsoft/Windows Terminal/settings.json";
  };

  settingsPath = variantPaths.${cfg.variant};
in
{
  options.programs.windows-terminal = {
    enable = lib.mkEnableOption "Windows Terminal";

    variant = lib.mkOption {
      type = lib.types.enum [
        "stable"
        "preview"
        "canary"
        "unpackaged"
      ];
      default = "stable";
      description = ''
        Windows Terminal variant. Determines the settings.json path.
        - stable: Microsoft Store release
        - preview: Microsoft Store preview
        - canary: Microsoft Store canary
        - unpackaged: GitHub releases / Chocolatey
      '';
    };

    settings = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      description = "Windows Terminal settings (serialized to JSON).";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        programs.windows-terminal.settings = {
          "$help" = lib.mkDefault "https://aka.ms/terminal-documentation";
          "$schema" = lib.mkDefault "https://aka.ms/terminal-profiles-schema";
        };
      }
      {
        windows.file.${settingsPath}.source =
          jsonFormat.generate "windows-terminal-settings.json" cfg.settings;
      }
    ]
  );
}
