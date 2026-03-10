# Starship prompt configuration
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.starship;
  tomlFormat = pkgs.formats.toml { };
in
{
  options.programs.starship = {
    enable = lib.mkEnableOption "starship prompt";

    settings = lib.mkOption {
      inherit (tomlFormat) type;
      default = { };
      description = "Starship configuration (serialized to TOML).";
    };

    enablePowerShellIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Add starship initialization to the PowerShell profile.
        Requires programs.powershell.enable = true to take effect.
      '';
    };

  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        windows.file."%USERPROFILE%/.config/starship.toml".source =
          tomlFormat.generate "starship.toml" cfg.settings;
      }
      (lib.mkIf cfg.enablePowerShellIntegration {
        programs.powershell.profileExtra = lib.mkAfter ''
          Invoke-Expression (&starship init powershell)
        '';
      })
    ]
  );
}
