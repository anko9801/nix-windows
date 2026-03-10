# DAG (Directed Acyclic Graph) library for activation script ordering
# Inspired by home-manager's lib/dag.nix — provides declarative
# before/after dependencies instead of numeric priorities.
{ lib }:
let
  entryAnywhere = data: {
    inherit data;
    after = [ ];
    before = [ ];
  };

  entryAfter = after: data: {
    inherit data after;
    before = [ ];
  };

  entryBefore = before: data: {
    inherit data before;
    after = [ ];
  };

  entryBetween = before: after: data: {
    inherit data after before;
  };

  # Topological sort of a DAG (attrset of { data, after, before } entries).
  # Returns { result = [ { name; data; } ... ]; } or throws on cycle.
  # References to non-existent entries are silently ignored.
  topoSort =
    dag:
    let
      entryNames = lib.attrNames dag;

      # Build dependency sets: for each entry, collect what must come before it.
      # Combines explicit `after` declarations with reverse `before` references.
      depSets = lib.mapAttrs (
        name: entry:
        let
          explicitAfter = builtins.filter (n: dag ? ${n}) entry.after;
          implicitAfter = builtins.filter (
            other: other != name && builtins.elem name (dag.${other}.before or [ ])
          ) entryNames;
        in
        explicitAfter ++ implicitAfter
      ) dag;

      entries = lib.mapAttrsToList (name: entry: {
        inherit name;
        inherit (entry) data;
      }) dag;

      # lib.toposort: `before a b` = true means a should appear before b
      sorted = lib.toposort (a: b: builtins.elem a.name (depSets.${b.name} or [ ])) entries;
    in
    if sorted ? result then
      sorted
    else
      builtins.throw (
        "Dependency cycle in activation scripts: "
        + lib.concatStringsSep " -> " (map (e: e.name) (sorted.cycle or [ ]))
      );

  dagEntryOf =
    elemType:
    lib.types.submodule {
      options = {
        data = lib.mkOption {
          type = elemType;
          description = "Entry content.";
        };
        after = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Entries that must come before this one.";
        };
        before = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Entries that must come after this one.";
        };
      };
    };

  # attrsOf DAG entries with auto-coercion from plain values
  dagOf =
    elemType: lib.types.attrsOf (lib.types.coercedTo elemType entryAnywhere (dagEntryOf elemType));
in
{
  inherit
    entryAnywhere
    entryAfter
    entryBefore
    entryBetween
    topoSort
    dagEntryOf
    dagOf
    ;
}
