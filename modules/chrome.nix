{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.chrome;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.chrome = {
    enable = lib.mkEnableOption "Google Chrome enterprise policies";

    policies = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      example = {
        HomepageLocation = "https://example.com";
        PasswordManagerEnabled = false;
      };
      description = "Chrome enterprise policies (deployed via registry-compatible JSON).";
    };

    installDir = lib.mkOption {
      type = lib.types.str;
      default = "%PROGRAMFILES%/Google/Chrome/Application";
      description = "Chrome installation directory.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.policies != { }) {
        windows.file."${cfg.installDir}/policies/managed/policies.json".source =
          jsonFormat.generate "chrome-policies.json" cfg.policies;
      })
    ]
  );
}
