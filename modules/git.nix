# Git for Windows configuration
# Follows HM's programs/git.nix pattern:
#   - gitIniType for structured INI settings
#   - iniContent as internal merge target
#   - lib.generators.toGitINI for serialization
#   - conditional includes via programs.git.includes
{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;

  cfg = config.programs.git;

  gitIniType =
    with types;
    let
      primitiveType = either str (either bool int);
      multipleType = either primitiveType (listOf primitiveType);
      sectionType = attrsOf multipleType;
      supersectionType = attrsOf (either multipleType sectionType);
    in
    attrsOf supersectionType;

  includeType = types.submodule {
    options = {
      path = mkOption {
        type = types.str;
        description = "Path to the included gitconfig file.";
      };
      condition = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "gitdir:~/work/";
        description = ''
          Conditional include filter.
          Supported prefixes: gitdir:, gitdir/i:, onbranch:, hasconfig:remote.*.url:
        '';
      };
    };
  };
in
{
  options.programs.git = {
    enable = mkEnableOption "Git for Windows";

    settings = mkOption {
      type = gitIniType;
      default = { };
      description = "Git configuration (INI sections).";
    };

    iniContent = mkOption {
      type = gitIniType;
      default = { };
      internal = true;
    };

    ignores = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Global gitignore patterns.";
    };

    includes = mkOption {
      type = types.listOf includeType;
      default = [ ];
      example = [
        {
          path = "~/.gitconfig-work";
          condition = "gitdir:~/work/";
        }
      ];
      description = ''
        Git configuration includes.
        Entries without a condition generate [include] sections.
        Entries with a condition generate [includeIf "condition"] sections.
      '';
    };

  };

  config = mkIf cfg.enable (mkMerge [
    (mkIf (cfg.iniContent != { }) {
      windows.file."%USERPROFILE%/.gitconfig".text = lib.generators.toGitINI cfg.iniContent;
    })

    (mkIf (cfg.settings != { }) {
      programs.git.iniContent = cfg.settings;
    })

    (mkIf (cfg.ignores != [ ]) {
      windows.file."%USERPROFILE%/.config/git/ignore".text = concatStringsSep "\n" cfg.ignores + "\n";
    })

    (mkIf (cfg.includes != [ ]) (
      let
        unconditional = builtins.filter (i: i.condition == null) cfg.includes;
        conditional = builtins.filter (i: i.condition != null) cfg.includes;
      in
      {
        programs.git.iniContent =
          lib.optionalAttrs (unconditional != [ ]) {
            include.path = map (i: i.path) unconditional;
          }
          // builtins.listToAttrs (
            map (inc: {
              name = "includeIf \"${inc.condition}\"";
              value = {
                inherit (inc) path;
              };
            }) conditional
          );
      }
    ))
  ]);
}
