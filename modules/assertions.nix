# Assertion and warning infrastructure (mirrors NixOS/HM pattern)
{ lib, ... }:
{
  options = {
    assertions = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      internal = true;
      default = [ ];
    };

    warnings = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      internal = true;
      default = [ ];
    };
  };
}
