{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.brave;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.brave = {
    enable = lib.mkEnableOption "Brave browser enterprise policies";

    policies = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      example = {
        HomepageLocation = "https://example.com";
        PasswordManagerEnabled = false;
      };
      description = "Brave enterprise policies (deployed via registry-compatible JSON).";
    };

    installDir = lib.mkOption {
      type = lib.types.str;
      default = "%PROGRAMFILES%/BraveSoftware/Brave-Browser/Application";
      description = "Brave installation directory.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.policies != { }) {
        windows.file."${cfg.installDir}/policies/managed/policies.json".source =
          jsonFormat.generate "brave-policies.json" cfg.policies;
      })
    ]
  );
}
