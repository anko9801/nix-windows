{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.oh-my-posh;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.oh-my-posh = {
    enable = lib.mkEnableOption "Oh My Posh prompt";

    settings = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      description = "Oh My Posh theme configuration (JSON).";
    };

    enablePowerShellIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Add oh-my-posh initialization to the PowerShell profile.
        Requires programs.powershell.enable = true to take effect.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.settings != { }) {
        windows.file."%USERPROFILE%/.config/oh-my-posh/config.json".source =
          jsonFormat.generate "oh-my-posh-config.json" cfg.settings;
      })
      (lib.mkIf cfg.enablePowerShellIntegration {
        programs.powershell.profileExtra = lib.mkAfter ''
          oh-my-posh init pwsh --config "$env:USERPROFILE\.config\oh-my-posh\config.json" | Invoke-Expression
        '';
      })
    ]
  );
}
