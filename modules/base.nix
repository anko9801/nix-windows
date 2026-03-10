# Core options: windows.username, windows.file, windows.fonts, path aliases
{
  config,
  lib,
  pkgs,
  deploy,
  dag,
  ...
}:
let
  fileTypeModule = import ../lib/file-type.nix { inherit lib pkgs; };

  enabledFiles = lib.filterAttrs (_: f: f.enable) config.windows.file;

  targetList = lib.mapAttrsToList (_: f: f.target) enabledFiles;

  duplicates =
    let
      grouped = builtins.groupBy (x: x) targetList;
    in
    lib.attrNames (lib.filterAttrs (_: v: builtins.length v > 1) grouped);
in
{
  options.system = {
    stateVersion = lib.mkOption {
      type = lib.types.ints.between 1 config.system.maxStateVersion;
      description = ''
        The state version of the configuration.
        Changing this may trigger breaking-change migrations in future releases.
        Set this to the nix-windows version you initially started with and do not change it.
      '';
    };

    maxStateVersion = lib.mkOption {
      type = lib.types.int;
      default = 1;
      internal = true;
      description = "Maximum supported state version.";
    };

    configurationRevision = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Git revision of the configuration repository.
        Set this to `self.rev or self.dirtyRev or null` in your flake
        to track which commit produced the active configuration.
      '';
    };
  };

  options.windows = {
    username = lib.mkOption {
      type = lib.types.str;
      description = "Windows username (used for path resolution).";
    };

    file = lib.mkOption {
      type = fileTypeModule.fileType;
      default = { };
      description = ''
        Files to deploy to Windows.
        Keys use Windows path variables: %USERPROFILE%, %APPDATA%, %LOCALAPPDATA%, %PROGRAMDATA%, %TEMP%.
      '';
    };

    fonts = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Font packages to install to Windows.";
    };

    # Path aliases (XDG-equivalent for Windows)
    appDataFile = lib.mkOption {
      type = fileTypeModule.fileType;
      default = { };
      description = ''
        Files to deploy under %APPDATA% (Roaming AppData).
        Keys are relative paths: `"Code/User/settings.json"` deploys to
        `%APPDATA%/Code/User/settings.json`.
      '';
    };

    localAppDataFile = lib.mkOption {
      type = fileTypeModule.fileType;
      default = { };
      description = ''
        Files to deploy under %LOCALAPPDATA% (Local AppData).
        Keys are relative paths within the Local AppData directory.
      '';
    };

    programDataFile = lib.mkOption {
      type = fileTypeModule.fileType;
      default = { };
      description = ''
        Files to deploy under %PROGRAMDATA%.
        Keys are relative paths within the ProgramData directory.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = builtins.match "[A-Za-z0-9._-]+" config.windows.username != null;
        message = "windows.username '${config.windows.username}' is invalid (must match [A-Za-z0-9._-]+)";
      }
      {
        assertion = duplicates == [ ];
        message = "Conflicting managed target files: ${lib.concatStringsSep ", " duplicates}";
      }
    ];

    # Remap path aliases into windows.file with the appropriate prefix
    windows.file = lib.mkMerge [
      (lib.mapAttrs' (name: file: lib.nameValuePair "%APPDATA%/${name}" file) config.windows.appDataFile)
      (lib.mapAttrs' (
        name: file: lib.nameValuePair "%LOCALAPPDATA%/${name}" file
      ) config.windows.localAppDataFile)
      (lib.mapAttrs' (
        name: file: lib.nameValuePair "%PROGRAMDATA%/${name}" file
      ) config.windows.programDataFile)
    ];

    system.activationScripts = {
      files = dag.entryAfter [ "writeBoundary" ] (deploy.mkFileDeployScript config.windows.file);
      fonts = dag.entryAfter [ "files" ] (deploy.mkFontDeployScript config.windows.fonts);
    };
  };
}
