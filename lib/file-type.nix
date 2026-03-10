# File entry submodule type
# Follows home-manager's lib/file-type.nix pattern:
#   - source is always set (either explicitly or derived from text)
#   - text → source conversion uses pkgs.writeTextFile with executable bit
{ lib, pkgs }:
let
  inherit (lib)
    mkDefault
    mkIf
    mkOption
    types
    ;

  # Sanitize a Windows file path for use as a Nix store file name.
  # Uses a hash prefix to avoid collisions from character replacement
  # (e.g. %USERPROFILE%/file vs %USERPROFILE_/file), plus a readable
  # basename suffix for debuggability.
  storeFileName =
    name:
    let
      hash = builtins.substring 0 8 (builtins.hashString "sha256" name);
      base = builtins.baseNameOf name;
      sanitized = builtins.replaceStrings [ "%" "/" " " ] [ "_" "_" "_" ] base;
    in
    "nw_${hash}_${sanitized}";
in
{
  fileType = types.attrsOf (
    types.submodule (
      { config, name, ... }:
      {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether this file should be deployed.";
          };

          target = mkOption {
            type = types.str;
            description = ''
              Deploy target path. Defaults to the attribute name.
              Allows multiple attribute names to map to the same target
              (which will be caught by the duplicate-target assertion).
            '';
          };

          source = mkOption {
            type = types.path;
            description = "Path to the source file in the Nix store.";
          };

          text = mkOption {
            type = types.nullOr types.lines;
            default = null;
            description = "Text content of the file.";
          };

          executable = mkOption {
            type = types.nullOr types.bool;
            default = null;
            description = ''
              Whether the file should be executable.
              `null` (default) preserves the source file's permissions.
              `true` runs chmod +x, `false` runs chmod -x after deploy.
              Note: chmod has no effect on WSL's DrvFs mounts unless the
              metadata mount option is enabled in /etc/wsl.conf.
            '';
          };

          onChange = mkOption {
            type = types.lines;
            default = "";
            description = ''
              Shell commands to run after deploying this file.
              Runs only when the file content changes.
            '';
          };

          force = mkOption {
            type = types.bool;
            default = true;
            description = ''
              Whether to overwrite existing files unconditionally.
              When false, warns and skips if the target has been modified
              outside of nix-windows (compared to the last deployed source).
            '';
          };

          recursive = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Whether to recursively deploy a directory source.
              When true, all files within the source directory are
              individually copied to the target directory tree.
            '';
          };
        };

        config = {
          target = mkDefault name;

          source = mkIf (config.text != null) (
            mkDefault (
              pkgs.writeTextFile {
                name = storeFileName name;
                inherit (config) text;
                executable = config.executable != null && config.executable;
              }
            )
          );
        };
      }
    )
  );
}
