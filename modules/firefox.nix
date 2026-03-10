{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.firefox;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.firefox = {
    enable = lib.mkEnableOption "Firefox enterprise policies";

    policies = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      example = {
        DisableTelemetry = true;
        DisablePocket = true;
        DontCheckDefaultBrowser = true;
        ExtensionSettings = { };
      };
      description = ''
        Firefox enterprise policies (policies.json).
        Deployed to the Firefox installation directory.
      '';
    };

    installDir = lib.mkOption {
      type = lib.types.str;
      default = "%PROGRAMFILES%/Mozilla Firefox";
      description = "Firefox installation directory.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.policies != { }) {
        windows.file."${cfg.installDir}/distribution/policies.json".source =
          jsonFormat.generate "firefox-policies.json"
            { policies = cfg.policies; };
      })
    ]
  );
}
