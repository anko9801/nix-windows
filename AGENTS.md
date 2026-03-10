# Development Guide

## Architecture

```
mkNixWindows { pkgs, modules }
  → lib.evalModules (specialArgs = { pkgs })
  → assertion/warning checks (HM pattern)
  → collects config.windows.{file, fonts}
  → produces activation script (bash, runs from WSL)
```

Scope: configuration files and fonts only. Package management is out of scope — use `winget configure` (DSC) directly.

Core files:
- `lib/mk-nix-windows.nix` — evaluator entry point (evalModules + assertion checks + writeShellScriptBin)
- `lib/file-type.nix` — file entry submodule (follows HM's lib/file-type.nix pattern)
- `lib/deploy.nix` — path resolution and deployment script generators
- `modules/assertions.nix` — assertion/warning option declarations (mirrors NixOS/HM)
- `modules/base.nix` — core option declarations (`windows.username`, `windows.file`, `windows.fonts`) + duplicate target assertion

## Module patterns (following Home Manager)

- **`specialArgs`** for passing `pkgs` (not `_module.args`)
- **`lib.mkMerge`** for conditional definitions (not `//`)
- **`pkgs.formats.*.generate` → `.source`** for structured data (JSON, TOML)
- **`lib.generators.*` → `.text`** for string serializers (toGitINI)
- **Structured types** (e.g. `gitIniType` for INI, `keybindingType` submodule for VS Code)
- **Internal options** for merge targets (e.g. `programs.git.iniContent`)
- **`source` auto-derived from `text`** in file-type submodule (via `mkDefault` + `pkgs.writeTextFile`)
- **`mkDefault` for schema injection** (komorebi, windows-terminal) — user can override
- **`assertions`/`warnings`** — modules add to `config.assertions` / `config.warnings`; evaluated in `mk-nix-windows.nix`
- **`target`** — deploy path separate from attribute name (default = name)
- **`onChange`** — shell commands run after each file deploy

## Adding a new program module

1. Create `modules/<name>.nix`
2. Declare options under `programs.<name>` with proper types
3. In `config`, use `lib.mkIf cfg.enable (lib.mkMerge [...])` for conditional definitions
4. Map options to `windows.file`
5. Add the module path to `builtinModules` in `flake.nix`

Template:

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.<name>;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.<name> = {
    enable = lib.mkEnableOption "<name>";
    settings = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    windows.file."<target-path>".source =
      jsonFormat.generate "<name>.json" cfg.settings;
  };
}
```

## Runtime path resolution

Path variables (`%USERPROFILE%`, `%APPDATA%`, etc.) are resolved at **runtime** via `cmd.exe` + `wslpath`, not at Nix build time. This handles custom WSL mount points.

## Testing

```bash
nix flake check
nix build .#example
cat ./result/bin/activate-nix-windows
statix check .
nix run nixpkgs#deadnix -- .
nix fmt
```
