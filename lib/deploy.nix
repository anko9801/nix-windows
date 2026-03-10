# Deployment script generation helpers
{ lib }:
let
  # Escape a string for safe use inside PowerShell single-quoted strings.
  # PowerShell's only escape inside '...' is '' for a literal single quote.
  escapePowerShell = s: builtins.replaceStrings [ "'" ] [ "''" ] s;

  # Generate shell code that resolves a Windows path variable at runtime.
  # The activation script sets WIN_USERPROFILE, WIN_APPDATA, etc. via wslpath + cmd.exe.
  resolveWindowsPath =
    path:
    let
      resolved =
        builtins.replaceStrings
          [
            "%USERPROFILE%"
            "%APPDATA%"
            "%LOCALAPPDATA%"
            "%PROGRAMDATA%"
            "%TEMP%"
          ]
          [
            "\$WIN_USERPROFILE"
            "\$WIN_APPDATA"
            "\$WIN_LOCALAPPDATA"
            "\$WIN_PROGRAMDATA"
            "\$WIN_TEMP"
          ]
          path;
    in
    if
      builtins.match ".*\\.\\./.*" path != null
      || builtins.match ".*\\.\\.$" path != null
      || builtins.match ".*\\.\\\\.*" path != null
    then
      builtins.throw "windows.file path '${path}' contains path traversal (../ or ..\\)"
    else if builtins.match ".*%[^%]+%.*" resolved != null then
      builtins.throw "windows.file path '${path}' contains unsupported variable (only %USERPROFILE%, %APPDATA%, %LOCALAPPDATA%, %PROGRAMDATA%, %TEMP% are supported)"
    else
      resolved;

  # Generate file deployment script from windows.file entries
  mkFileDeployScript =
    files:
    let
      enabledFiles = lib.filterAttrs (_: f: f.enable) files;
      entries = lib.mapAttrsToList (_: file: {
        inherit (file)
          source
          executable
          onChange
          force
          recursive
          ;
        target = resolveWindowsPath file.target;
      }) enabledFiles;
      count = toString (builtins.length entries);
      chmodFor = {
        "true" = ''chmod +x "$target"'';
        "false" = ''chmod -x "$target"'';
        "null" = "";
      };
      # Deploy a single file to its target
      deploySingleFile = e: chmodCmd: ''
        target="${e.target}"
        if [ "$DRY_RUN" = "1" ]; then
          if [ -f "$target" ]; then
            if cmp -s "${e.source}" "$target" 2>/dev/null; then
              echo "  [dry-run] unchanged: $target"
            else
              echo "  [dry-run] would update: $target"
              diff -u "$target" "${e.source}" --label "current: $target" --label "new: $target" 2>/dev/null || true
            fi
          else
            echo "  [dry-run] would create: $target"
          fi
        else
          mkdir -p "$(dirname "$target")" || { echo "Error: failed to create directory for $target"; exit 1; }
          NW_SKIP=0
          ${lib.optionalString (!e.force) ''
            # Conflict detection: check if file was modified outside nix-windows
            NW_HASH_DIR="$WIN_USERPROFILE/.config/nix-windows/hashes"
            mkdir -p "$NW_HASH_DIR"
            NW_HASH_FILE="$NW_HASH_DIR/$(echo "$target" | md5sum | cut -d' ' -f1)"
            if [ -f "$target" ] && [ -f "$NW_HASH_FILE" ]; then
              NW_LAST_HASH="$(cat "$NW_HASH_FILE")"
              NW_CURR_HASH="$(sha256sum "$target" | cut -d' ' -f1)"
              if [ "$NW_LAST_HASH" != "$NW_CURR_HASH" ]; then
                echo "  Warning: $target was modified outside nix-windows, skipping (use force=true to overwrite)"
                NW_SKIP=1
              fi
            fi
          ''}
          if [ "$NW_SKIP" = "0" ]; then
            NW_CHANGED=0
            if ! cmp -s "${e.source}" "$target" 2>/dev/null; then
              NW_CHANGED=1
            fi
            # Backup unmanaged files before first overwrite
            if [ "$NW_CHANGED" = "1" ] && [ -f "$target" ]; then
              if ! grep -qFx "$target" "$NW_MANIFEST_FILE" 2>/dev/null; then
                cp -f "$target" "$target.nw-backup"
                echo "  backed up: $target -> $target.nw-backup"
              fi
            fi
            cp -f "${e.source}" "$target" || { echo "Error: failed to copy ${e.source} to $target"; exit 1; }
            ${lib.optionalString (chmodCmd != "") chmodCmd}
            ${lib.optionalString (e.onChange != "") ''
              if [ "$NW_CHANGED" = "1" ]; then
                ${e.onChange}
              fi''}
            ${lib.optionalString (!e.force) ''
              sha256sum "$target" | cut -d' ' -f1 > "$NW_HASH_FILE"
            ''}
            if [ "$NW_CHANGED" = "1" ]; then
              NW_STATS_FILES_DEPLOYED=$((NW_STATS_FILES_DEPLOYED + 1))
              echo "  deployed: $target"
            else
              NW_STATS_FILES_UNCHANGED=$((NW_STATS_FILES_UNCHANGED + 1))
            fi
          fi
        fi
        # Record this target in the new manifest
        echo "$target" >> "$NW_MANIFEST_NEW"
      '';

      # Recursively deploy all files within a directory source
      deployRecursiveDir = e: ''
        NW_RSRC="${e.source}"
        NW_RTGT="${e.target}"
        if [ "$DRY_RUN" = "1" ]; then
          echo "  [dry-run] would recursively deploy: $NW_RTGT (from $NW_RSRC)"
        else
          while IFS= read -r -d "" src_file; do
            relative="''${src_file#$NW_RSRC/}"
            subtarget="$NW_RTGT/$relative"
            mkdir -p "$(dirname "$subtarget")"
            if ! cmp -s "$src_file" "$subtarget" 2>/dev/null; then
              cp -f "$src_file" "$subtarget"
              NW_STATS_FILES_DEPLOYED=$((NW_STATS_FILES_DEPLOYED + 1))
              echo "  deployed: $subtarget"
            else
              NW_STATS_FILES_UNCHANGED=$((NW_STATS_FILES_UNCHANGED + 1))
            fi
            echo "$subtarget" >> "$NW_MANIFEST_NEW"
          done < <(find "$NW_RSRC" -type f -print0)
        fi
      '';

      deployOne =
        e:
        let
          chmodCmd = chmodFor.${builtins.toJSON e.executable};
        in
        if e.recursive then deployRecursiveDir e else deploySingleFile e chmodCmd;
    in
    if entries == [ ] then
      ""
    else
      ''
        echo "[files] Deploying ${count} file(s)..."
        ${lib.concatMapStringsSep "" deployOne entries}
      '';

  # Generate stale file cleanup script
  mkStaleFileCleanupScript = ''
    NW_MANIFEST_DIR="$WIN_USERPROFILE/.config/nix-windows"
    NW_MANIFEST_FILE="$NW_MANIFEST_DIR/manifest"
    NW_MANIFEST_NEW="$NW_MANIFEST_DIR/manifest.new"
    mkdir -p "$NW_MANIFEST_DIR"
    : > "$NW_MANIFEST_NEW"
  '';

  mkStaleFileFinalizationScript = ''
    if [ -f "$NW_MANIFEST_FILE" ]; then
      while IFS= read -r old_target; do
        if [ -n "$old_target" ] && ! grep -qFx "$old_target" "$NW_MANIFEST_NEW" 2>/dev/null; then
          if [ "$DRY_RUN" = "1" ]; then
            echo "  [dry-run] would remove stale: $old_target"
          else
            if [ -f "$old_target" ]; then
              rm -f "$old_target"
              NW_STATS_FILES_REMOVED=$((NW_STATS_FILES_REMOVED + 1))
              echo "  removed stale: $old_target"
            fi
          fi
        fi
      done < "$NW_MANIFEST_FILE"
    fi
    if [ "$DRY_RUN" != "1" ]; then
      mv -f "$NW_MANIFEST_NEW" "$NW_MANIFEST_FILE"
    else
      rm -f "$NW_MANIFEST_NEW"
    fi
  '';

  # Generate font installation script
  mkFontDeployScript =
    fontPackages:
    let
      count = toString (builtins.length fontPackages);
      # Register all fonts in the user registry so Windows recognizes them
      registerFontsScript = ''
        echo "  Registering fonts in registry..."
        ${mkPowerShellExec ''
          $fontsKey = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
          if (-not (Test-Path $fontsKey)) {
            New-Item -Path $fontsKey -Force | Out-Null
          }
          $fontsDir = $env:LOCALAPPDATA + '\Microsoft\Windows\Fonts'
          Get-ChildItem -Path $fontsDir -Include *.ttf,*.otf -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            Set-ItemProperty -Path $fontsKey -Name $_.Name -Value $_.FullName -Force
          }
        ''}
      '';
      deployFont = pkg: ''
        if [ -d "${pkg}/share/fonts" ]; then
          if [ "$DRY_RUN" = "1" ]; then
            echo "  [dry-run] would install: ${pkg.name or "font"}"
          else
            NW_FONT_COUNT=0
            NW_FONT_SKIP=0
            while IFS= read -r -d "" font_file; do
              font_name="$(basename "$font_file")"
              if cmp -s "$font_file" "$FONTS_DIR/$font_name" 2>/dev/null; then
                NW_FONT_SKIP=$((NW_FONT_SKIP + 1))
                NW_STATS_FONTS_UNCHANGED=$((NW_STATS_FONTS_UNCHANGED + 1))
              else
                cp -f "$font_file" "$FONTS_DIR/" || { echo "  Warning: failed to install $font_name"; continue; }
                NW_FONT_COUNT=$((NW_FONT_COUNT + 1))
                NW_STATS_FONTS_INSTALLED=$((NW_STATS_FONTS_INSTALLED + 1))
              fi
            done < <(find "${pkg}/share/fonts" -type f \( -name '*.ttf' -o -name '*.otf' \) -print0)
            echo "  ${pkg.name or "font"}: $NW_FONT_COUNT installed, $NW_FONT_SKIP unchanged"
          fi
        fi
      '';
    in
    if fontPackages == [ ] then
      ""
    else
      ''
        echo "[fonts] Installing ${count} font package(s)..."
        FONTS_DIR="$WIN_LOCALAPPDATA/Microsoft/Windows/Fonts"
        if [ "$DRY_RUN" != "1" ]; then
          mkdir -p "$FONTS_DIR"
        fi
        ${lib.concatMapStringsSep "" deployFont fontPackages}
        ${registerFontsScript}
      '';

  # Execute a PowerShell script from WSL via a temp file.
  # Requires WIN_TEMP to be set by the activation script preamble.
  mkPowerShellExec = scriptContent: ''
    if [ "$DRY_RUN" = "1" ]; then
      echo "  [dry-run] would execute PowerShell script"
    else
      NW_PS="$(mktemp "$WIN_TEMP/nw-XXXXXX.ps1")"
      cat > "$NW_PS" << '__NW_PS_SCRIPT__'
    ${scriptContent}
    __NW_PS_SCRIPT__
      powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass \
        -File "$(wslpath -w "$NW_PS")"
      NW_PS_EXIT=$?
      rm -f "$NW_PS"
      if [ "$NW_PS_EXIT" -ne 0 ]; then
        echo "Error: PowerShell script failed with exit code $NW_PS_EXIT"
        exit "$NW_PS_EXIT"
      fi
    fi
  '';

in
{
  inherit
    escapePowerShell
    resolveWindowsPath
    mkFileDeployScript
    mkStaleFileCleanupScript
    mkStaleFileFinalizationScript
    mkFontDeployScript
    mkPowerShellExec
    ;
}
