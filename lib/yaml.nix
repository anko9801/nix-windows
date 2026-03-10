# Shallow YAML serializer for DSC configuration files
{ lib }:
let
  # Characters that require quoting in YAML scalar values
  needsQuoting =
    s:
    s == ""
    || s == "true"
    || s == "false"
    || s == "null"
    || builtins.match ".*[:{}\n\r\"'\\[\\],&#*?|>!%@`].*" s != null
    || builtins.match "[ \t].*" s != null
    || builtins.match ".*[ \t]" s != null;

  quoteYaml =
    s:
    let
      escaped = builtins.replaceStrings [ "\\" "\"" "\n" "\r" ] [ "\\\\" "\\\"" "\\n" "\\r" ] s;
    in
    "\"${escaped}\"";

  yamlValue =
    v:
    if v == null then
      "null"
    else if builtins.isBool v then
      if v then "true" else "false"
    else if builtins.isInt v || builtins.isFloat v then
      builtins.toString v
    else if builtins.isString v then
      if needsQuoting v then quoteYaml v else v
    else
      quoteYaml (builtins.toString v);

  ind = n: lib.concatStrings (lib.replicate n "  ");

  renderAttrs =
    level: attrs:
    let
      filtered = lib.filterAttrs (_: v: v != null && v != [ ] && v != { }) attrs;
    in
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        k: v:
        if builtins.isAttrs v then
          "${ind level}${k}:\n${renderAttrs (level + 1) v}"
        else if builtins.isList v then
          "${ind level}${k}:\n${lib.concatMapStringsSep "\n" (x: "${ind (level + 1)}- ${yamlValue x}") v}"
        else
          "${ind level}${k}: ${yamlValue v}"
      ) filtered
    );

  renderResource =
    level: r:
    let
      lines = renderAttrs (level + 1) r;
    in
    if lines == "" then
      "${ind level}- {}"
    else
      let
        prefix = ind (level + 1);
        prefixLen = builtins.stringLength prefix;
      in
      "${ind level}- ${builtins.substring prefixLen (builtins.stringLength lines - prefixLen) lines}";
in
{
  inherit
    yamlValue
    ind
    renderAttrs
    renderResource
    ;
}
