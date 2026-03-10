{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.edge;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.edge = {
    enable = lib.mkEnableOption "Microsoft Edge enterprise policies";

    policies = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      example = {
        HomepageLocation = "https://example.com";
        PasswordManagerEnabled = false;
      };
      description = "Edge enterprise policies (deployed via registry-compatible JSON).";
    };

    installDir = lib.mkOption {
      type = lib.types.str;
      default = "%PROGRAMFILES(X86)%/Microsoft/Edge/Application";
      description = "Edge installation directory.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.policies != { }) {
        windows.file."${cfg.installDir}/policies/managed/policies.json".source =
          jsonFormat.generate "edge-policies.json" cfg.policies;
      })
    ]
  );
}
