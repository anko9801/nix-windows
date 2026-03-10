# Modular activation-time checks (like nix-darwin's system.checks)
# Runs before writeBoundary to abort before mutations.
{
  config,
  lib,
  dag,
  ...
}:
let
  cfg = config.system.checks;
in
{
  options.system.checks = {
    verifyWindowsVersion = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Verify Windows 10+ (build 19041+) during activation.";
    };

    verifyPowerShellVersion = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Verify PowerShell 5.1+ is available.";
    };

    verifyWingetAvailable = lib.mkOption {
      type = lib.types.bool;
      default = config.programs.winget.enable or false;
      description = "Verify winget is installed (auto-enabled when winget module is active).";
    };

    text = lib.mkOption {
      type = lib.types.lines;
      default = "";
      internal = true;
      description = "Composed check script text.";
    };
  };

  config = {
    system.checks.text = lib.mkMerge [
      (lib.mkIf cfg.verifyWindowsVersion ''
        NW_WIN_BUILD="$(cmd.exe /C "ver" 2>/dev/null | tr -d '\r' | grep -oP '\d+\.\d+\.\K\d+' || echo "0")"
        if [ "$NW_WIN_BUILD" -lt 19041 ] 2>/dev/null; then
          echo "Error: Windows build $NW_WIN_BUILD is too old (requires 19041+)"
          exit 1
        fi
      '')
      (lib.mkIf cfg.verifyPowerShellVersion ''
        NW_PS_VER="$(powershell.exe -NoProfile -Command '$PSVersionTable.PSVersion.Major' 2>/dev/null | tr -d '\r' || echo "0")"
        if [ "$NW_PS_VER" -lt 5 ] 2>/dev/null; then
          echo "Error: PowerShell version $NW_PS_VER is too old (requires 5+)"
          exit 1
        fi
      '')
      (lib.mkIf cfg.verifyWingetAvailable ''
        if ! command -v winget.exe &>/dev/null && ! cmd.exe /C "where winget" &>/dev/null; then
          echo "Error: winget is not installed (required by programs.winget)"
          exit 1
        fi
      '')
    ];

    system.activationScripts.checks = lib.mkIf (cfg.text != "") (
      dag.entryBefore [ "writeBoundary" ] ''
        echo "[checks] Running pre-activation checks..."
        ${cfg.text}
      ''
    );
  };
}
