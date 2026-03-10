# Windows environment variables and user PATH management
{
  config,
  lib,
  deploy,
  dag,
  ...
}:
let
  esc = deploy.escapePowerShell;

  inherit (config.environment) variables userPath;

  hasVars = variables != { };
  hasPath = userPath != [ ];

  setVarCommands = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: value: "[Environment]::SetEnvironmentVariable('${esc name}', '${esc value}', 'User')"
    ) variables
  );

  pathEntries = lib.concatStringsSep ";" (map esc userPath);

  pathScript = ''
    $currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $newEntries = '${pathEntries}' -split ';'
    $currentEntries = @()
    if ($currentPath) { $currentEntries = $currentPath -split ';' }
    $merged = [System.Collections.ArrayList]@($currentEntries)
    foreach ($entry in $newEntries) {
      if ($entry -and ($merged -inotcontains $entry)) {
        [void]$merged.Add($entry)
      }
    }
    [Environment]::SetEnvironmentVariable('Path', ($merged -join ';'), 'User')
  '';

  broadcastChange = ''
    if (-not ([System.Management.Automation.PSTypeName]'Win32.NativeMethods').Type) {
      Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr SendMessageTimeout(
          IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
          uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
    "@
    }
    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_SETTINGCHANGE = 0x1a
    $result = [UIntPtr]::Zero
    [Win32.NativeMethods]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result) | Out-Null
  '';

  psScript = lib.concatStringsSep "\n" (
    lib.optional hasVars setVarCommands ++ lib.optional hasPath pathScript ++ [ broadcastChange ]
  );

  varCount = toString (builtins.length (lib.attrNames variables));
  pathCount = toString (builtins.length userPath);

  summaryParts =
    lib.optional hasVars "${varCount} variable(s)"
    ++ lib.optional hasPath "${pathCount} PATH entry(ies)";
  summary = lib.concatStringsSep ", " summaryParts;
in
{
  options.environment = {
    variables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "User-level environment variables to set on Windows.";
    };

    userPath = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Entries to append to the user PATH on Windows (deduplicated).";
    };

    shellInit = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        PowerShell code executed in all sessions (interactive and non-interactive).
        Inserted into the CurrentUserAllHosts profile before program-specific config.
      '';
    };

    loginShellInit = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        PowerShell code executed only in the current user's profile.
        Inserted before programs.powershell.profileExtra.
      '';
    };
  };

  config.assertions =
    let
      invalidNames = builtins.filter (name: builtins.match "[A-Za-z_][A-Za-z0-9_]*" name == null) (
        lib.attrNames variables
      );
    in
    map (name: {
      assertion = false;
      message = "environment.variables: invalid name '${name}' (must match [A-Za-z_][A-Za-z0-9_]*)";
    }) invalidNames;

  config.system.activationScripts.environment = lib.mkIf (hasVars || hasPath) (
    dag.entryAfter [ "registry" ] ''
      echo "[environment] Setting ${summary}..."
      ${deploy.mkPowerShellExec psScript}
    ''
  );
}
