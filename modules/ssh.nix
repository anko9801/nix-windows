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
    optionalString
    types
    ;

  cfg = config.programs.ssh;

  matchBlockType = types.submodule {
    options = {
      host = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Host pattern for this block.";
      };

      match = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Match criteria (alternative to host).";
      };

      hostname = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Real hostname to connect to.";
      };

      user = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Username for connection.";
      };

      port = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Port number.";
      };

      identityFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to identity file.";
      };

      identitiesOnly = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Only use configured identity files.";
      };

      proxyJump = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Proxy jump host.";
      };

      forwardAgent = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Forward SSH agent.";
      };

      extraOptions = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Additional SSH options as key-value pairs.";
      };
    };
  };

  boolToYesNo = b: if b then "yes" else "no";

  renderBlock =
    block:
    let
      header =
        if block.host != null then
          "Host ${block.host}"
        else if block.match != null then
          "Match ${block.match}"
        else
          null;

      fields =
        lib.optional (block.hostname != null) "  HostName ${block.hostname}"
        ++ lib.optional (block.user != null) "  User ${block.user}"
        ++ lib.optional (block.port != null) "  Port ${toString block.port}"
        ++ lib.optional (block.identityFile != null) "  IdentityFile ${block.identityFile}"
        ++ lib.optional (
          block.identitiesOnly != null
        ) "  IdentitiesOnly ${boolToYesNo block.identitiesOnly}"
        ++ lib.optional (block.proxyJump != null) "  ProxyJump ${block.proxyJump}"
        ++ lib.optional (block.forwardAgent != null) "  ForwardAgent ${boolToYesNo block.forwardAgent}"
        ++ lib.mapAttrsToList (k: v: "  ${k} ${v}") block.extraOptions;
    in
    optionalString (header != null) (header + "\n" + concatStringsSep "\n" fields);
in
{
  options.programs.ssh = {
    enable = mkEnableOption "SSH client configuration";

    matchBlocks = mkOption {
      type = types.attrsOf matchBlockType;
      default = { };
      description = "SSH match blocks. Attribute names are used as Host if host is not set.";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Raw text appended to ssh_config.";
    };
  };

  config = mkIf cfg.enable (
    let
      blocks = lib.mapAttrsToList (
        name: block:
        renderBlock (
          block // lib.optionalAttrs (block.host == null && block.match == null) { host = name; }
        )
      ) cfg.matchBlocks;

      configText =
        concatStringsSep "\n\n" (builtins.filter (s: s != "") blocks)
        + optionalString (cfg.extraConfig != "") ("\n\n" + cfg.extraConfig)
        + "\n";
    in
    mkMerge [
      (mkIf (cfg.matchBlocks != { } || cfg.extraConfig != "") {
        windows.file."%USERPROFILE%/.ssh/config".text = configText;
      })
    ]
  );
}
