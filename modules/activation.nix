# system.activationScripts — DAG-ordered shell script fragments
# Each entry declares before/after dependencies for deterministic ordering.
# Plain strings are auto-coerced to entries with no ordering constraints.
{
  config,
  lib,
  dag,
  ...
}:
{
  options.system = {
    activationScripts = lib.mkOption {
      type = dag.dagOf lib.types.lines;
      default = { };
      description = ''
        Named shell script fragments to execute during activation.
        Ordered by DAG dependencies (after/before).
        Plain strings are treated as entries with no ordering constraints.
      '';
    };

    preActivation = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Shell commands to run before all write operations.";
    };

    postActivation = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Shell commands to run after all activation scripts.";
    };
  };

  config.system.activationScripts = lib.mkMerge [
    {
      # Boundary between read-only checks and write operations.
      # Checks should declare `before = ["writeBoundary"]`.
      # Writes should declare `after = ["writeBoundary"]` (or after a specific write entry).
      writeBoundary = dag.entryAnywhere "";
    }
    (lib.mkIf (config.system.preActivation != "") {
      preActivation = dag.entryBefore [ "writeBoundary" ] config.system.preActivation;
    })
    (lib.mkIf (config.system.postActivation != "") {
      postActivation = dag.entryAfter [
        "files"
        "fonts"
        "registry"
        "environment"
        "winget"
        "winget-cleanup"
      ] config.system.postActivation;
    })
  ];
}
