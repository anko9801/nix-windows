# Core evaluator: evalModules + activation script builder
{ lib }:
{
  pkgs,
  modules ? [ ],
  extraSpecialArgs ? { },
}:
let
  dagLib = import ./dag.nix { inherit lib; };
  deploy = import ./deploy.nix { inherit lib; };

  evaluated = lib.evalModules {
    specialArgs = {
      inherit pkgs deploy;
      dag = dagLib;
    }
    // extraSpecialArgs;
    inherit modules;
  };

  cfg = evaluated.config;

  # HM-style assertion/warning checks
  failedAssertions = map (x: x.message) (builtins.filter (x: !x.assertion) cfg.assertions);

  moduleChecks =
    if failedAssertions != [ ] then
      throw "\nFailed assertions:\n${lib.concatStringsSep "\n" (map (x: "- ${x}") failedAssertions)}"
    else
      lib.showWarnings cfg.warnings cfg;

  checkedCfg = builtins.seq moduleChecks cfg;

  # DAG-based activation script assembly
  scripts = checkedCfg.system.activationScripts;

  nonEmpty = lib.filterAttrs (_: v: v.data != "") scripts;
  sorted = dagLib.topoSort nonEmpty;
  activationScript = lib.concatMapStringsSep "\n" (e: e.data) sorted.result;

  # Version info for tracking
  revisionStr =
    if checkedCfg.system.configurationRevision != null then
      checkedCfg.system.configurationRevision
    else
      "unknown";

  # The main activation derivation
  toplevel = pkgs.writeShellScriptBin "activate-nix-windows" ''
    set -euo pipefail

    # Parse flags
    DRY_RUN=0
    LIST_GENERATIONS=0
    for arg in "$@"; do
      case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --list-generations) LIST_GENERATIONS=1 ;;
        --help|-h)
          echo "Usage: activate-nix-windows [--dry-run] [--list-generations]"
          echo ""
          echo "Options:"
          echo "  --dry-run           Show what would be done without making changes"
          echo "  --list-generations  List previous activation generations"
          echo "  --help              Show this help message"
          exit 0
          ;;
        *) echo "Unknown option: $arg (use --help for usage)"; exit 1 ;;
      esac
    done
    export DRY_RUN

    if [ "$DRY_RUN" = "1" ]; then
      echo "[dry-run] No changes will be made"
    fi

    # Verify we're running inside WSL
    if [ -z "''${WSL_DISTRO_NAME:-}" ] \
       && [ ! -e /proc/sys/fs/binfmt_misc/WSLInterop ] \
       && ! grep -qi microsoft /proc/version 2>/dev/null; then
      echo "Error: This script must be run from WSL"
      exit 1
    fi

    # Prevent concurrent activation
    LOCK_FILE="/tmp/nw-activate.lock"
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
      echo "Error: Another activation is already running"
      exit 1
    fi
    trap 'flock -u 9; rm -f "$LOCK_FILE"' EXIT

    # Resolve Windows environment variables at runtime via a single cmd.exe call
    WIN_ENV="$(cmd.exe /C "echo %USERNAME%^|%USERPROFILE%^|%APPDATA%^|%LOCALAPPDATA%^|%PROGRAMDATA%^|%TEMP%" 2>/dev/null | tr -d '\r' | sed 's/[[:space:]]*$//')"

    WIN_USER="$(echo "$WIN_ENV" | cut -d'|' -f1)"
    WIN_USERPROFILE_RAW="$(echo "$WIN_ENV" | cut -d'|' -f2)"
    WIN_APPDATA_RAW="$(echo "$WIN_ENV" | cut -d'|' -f3)"
    WIN_LOCALAPPDATA_RAW="$(echo "$WIN_ENV" | cut -d'|' -f4)"
    WIN_PROGRAMDATA_RAW="$(echo "$WIN_ENV" | cut -d'|' -f5)"
    WIN_TEMP_RAW="$(echo "$WIN_ENV" | cut -d'|' -f6)"

    if [ -z "$WIN_USER" ]; then
      echo "Error: Could not detect Windows username via cmd.exe"
      exit 1
    fi

    EXPECTED_USER="${checkedCfg.windows.username}"
    if [ "$WIN_USER" != "$EXPECTED_USER" ]; then
      echo "Error: Windows username '$WIN_USER' does not match configured username '$EXPECTED_USER'"
      echo "  Set windows.username = \"$WIN_USER\"; in your configuration"
      exit 1
    fi

    # Convert Windows paths to WSL paths
    WIN_USERPROFILE="$(wslpath "$WIN_USERPROFILE_RAW")"
    WIN_APPDATA="$(wslpath "$WIN_APPDATA_RAW")"
    WIN_LOCALAPPDATA="$(wslpath "$WIN_LOCALAPPDATA_RAW")"
    WIN_PROGRAMDATA="$(wslpath "$WIN_PROGRAMDATA_RAW")"
    WIN_TEMP="$(wslpath "$WIN_TEMP_RAW")"

    # Validate all resolved paths
    for var_name in WIN_USERPROFILE WIN_APPDATA WIN_LOCALAPPDATA WIN_PROGRAMDATA WIN_TEMP; do
      var_value="''${!var_name}"
      if [ -z "$var_value" ]; then
        echo "Error: $var_name is empty"
        exit 1
      fi
      if [ ! -d "$var_value" ]; then
        echo "Error: $var_name directory not found: $var_value"
        exit 1
      fi
    done

    # Handle --list-generations (early exit after path resolution)
    if [ "$LIST_GENERATIONS" = "1" ]; then
      NW_GEN_DIR="$WIN_USERPROFILE/.config/nix-windows/generations"
      if [ ! -d "$NW_GEN_DIR" ]; then
        echo "No generations found"
        exit 0
      fi
      printf "%-6s %-26s %-12s %s\n" "ID" "Date" "Revision" ""
      printf "%-6s %-26s %-12s %s\n" "---" "---" "---" ""
      for gen in $(ls -1 "$NW_GEN_DIR" 2>/dev/null | grep -E '^[0-9]+$' | sort -n); do
        ts=""
        rev=""
        if [ -f "$NW_GEN_DIR/$gen/timestamp" ]; then
          ts=$(cat "$NW_GEN_DIR/$gen/timestamp")
        fi
        if [ -f "$NW_GEN_DIR/$gen/metadata.json" ]; then
          rev=$(grep -o '"configurationRevision":"[^"]*"' "$NW_GEN_DIR/$gen/metadata.json" | cut -d'"' -f4)
        fi
        current=""
        if [ -f "$NW_GEN_DIR/current" ] && [ "$(cat "$NW_GEN_DIR/current")" = "$gen" ]; then
          current="(current)"
        fi
        printf "%-6s %-26s %-12s %s\n" "$gen" "''${ts:-unknown}" "''${rev:-unknown}" "$current"
      done
      exit 0
    fi

    echo "=== Activating Windows configuration for $WIN_USER ==="
    echo "  USERPROFILE: $WIN_USERPROFILE"

    # Initialize statistics counters
    NW_STATS_FILES_DEPLOYED=0
    NW_STATS_FILES_UNCHANGED=0
    NW_STATS_FILES_REMOVED=0
    NW_STATS_FONTS_INSTALLED=0
    NW_STATS_FONTS_UNCHANGED=0

    # Initialize manifest tracking for stale file cleanup
    ${deploy.mkStaleFileCleanupScript}

    # Set up logging (skip in dry-run)
    if [ "$DRY_RUN" != "1" ]; then
      NW_LOG_DIR="$WIN_USERPROFILE/.config/nix-windows"
      mkdir -p "$NW_LOG_DIR"
      NW_LOG="$NW_LOG_DIR/last-activation.log"
      NW_LOG_PID=""
      exec > >(while IFS= read -r line; do
        printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line"
      done | tee -a "$NW_LOG") 2>&1
      NW_LOG_PID=$!
      # Ensure the logging process flushes before exit
      trap 'flock -u 9; rm -f "$LOCK_FILE"; if [ -n "$NW_LOG_PID" ]; then wait "$NW_LOG_PID" 2>/dev/null; fi' EXIT
      echo "=== Activation started ==="
    fi

    ${activationScript}

    # Clean up stale files from previous activations
    echo "[cleanup] Checking for stale files..."
    ${deploy.mkStaleFileFinalizationScript}

    # Write version info
    if [ "$DRY_RUN" != "1" ]; then
      cat > "$WIN_USERPROFILE/.config/nix-windows/current-version.json" << 'NW_VERSION_EOF'
    ${builtins.toJSON {
      inherit (checkedCfg.system) stateVersion;
      configurationRevision = revisionStr;
    }}
    NW_VERSION_EOF
    fi

    # Save generation record
    if [ "$DRY_RUN" != "1" ]; then
      NW_GEN_DIR="$WIN_USERPROFILE/.config/nix-windows/generations"
      mkdir -p "$NW_GEN_DIR"

      # Find next generation number
      NW_GEN_CURRENT=0
      if [ -f "$NW_GEN_DIR/current" ]; then
        NW_GEN_CURRENT=$(cat "$NW_GEN_DIR/current")
      fi
      NW_GEN_NEXT=$((NW_GEN_CURRENT + 1))

      mkdir -p "$NW_GEN_DIR/$NW_GEN_NEXT"
      cp -f "$NW_MANIFEST_FILE" "$NW_GEN_DIR/$NW_GEN_NEXT/manifest" 2>/dev/null || true
      cat > "$NW_GEN_DIR/$NW_GEN_NEXT/metadata.json" << NW_GEN_META_EOF
    ${builtins.toJSON {
      inherit (checkedCfg.system) stateVersion;
      configurationRevision = revisionStr;
    }}
    NW_GEN_META_EOF
      date -Iseconds > "$NW_GEN_DIR/$NW_GEN_NEXT/timestamp"
      echo "$NW_GEN_NEXT" > "$NW_GEN_DIR/current"

      # Prune old generations (keep last 10)
      for old_gen in $(ls -1 "$NW_GEN_DIR" 2>/dev/null | grep -E '^[0-9]+$' | sort -n | head -n -10); do
        rm -rf "''${NW_GEN_DIR:?}/$old_gen"
      done
    fi

    # Print activation summary
    if [ "$DRY_RUN" != "1" ]; then
      echo ""
      echo "=== Activation summary ==="
      echo "  Files: $NW_STATS_FILES_DEPLOYED deployed, $NW_STATS_FILES_UNCHANGED unchanged, $NW_STATS_FILES_REMOVED removed"
      echo "  Fonts: $NW_STATS_FONTS_INSTALLED installed, $NW_STATS_FONTS_UNCHANGED unchanged"
      echo "  Generation: $NW_GEN_NEXT"
    fi

    echo "=== Windows configuration activated ==="
  '';
in
# Return derivation with passthru for inspection and composition
toplevel.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    # Evaluated module config for inspection
    inherit (evaluated) config options;

    # Intermediate build products
    inherit activationScript;

    # Extend the configuration with additional modules
    extendModules =
      args:
      import ./mk-nix-windows.nix { inherit lib; } {
        inherit pkgs extraSpecialArgs;
        modules = modules ++ (args.modules or [ ]);
      };
  };
})
