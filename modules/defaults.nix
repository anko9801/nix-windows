# High-level typed Windows settings (like nix-darwin's system.defaults)
# Maps to system.registry entries internally.
{
  config,
  lib,
  ...
}:
let
  cfg = config.system.defaults;

  inherit (lib) mkOption mkIf types;

  boolToDword = v: if v then 1 else 0;
  invertBoolToDword = v: if v then 0 else 1;

  explorerAdvanced = "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced";
  themesPersonalize = "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
  searchPath = "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Search";

  mkRegistry =
    entries:
    let
      # Convert "HKCU\Foo\Bar" → nested { HKCU.Foo.Bar = value; }
      pathToAttrs =
        pathStr: value:
        let
          parts = lib.splitString "\\" pathStr;
        in
        lib.setAttrByPath parts value;

      merged = lib.foldl' lib.recursiveUpdate { } (
        lib.concatMap (
          { path, values }: map ({ name, value }: pathToAttrs path { ${name} = value; }) values
        ) entries
      );
    in
    merged;

  # Collect all registry entries from defaults
  registryEntries =
    let
      fromExplorer =
        let
          v = cfg.explorer;
          vals =
            lib.optional (v.showFileExtensions != null) {
              name = "HideFileExt";
              value = invertBoolToDword v.showFileExtensions;
            }
            ++ lib.optional (v.showHiddenFiles != null) {
              name = "Hidden";
              value = if v.showHiddenFiles then 1 else 2;
            }
            ++ lib.optional (v.showFullPathInTitleBar != null) {
              name = "FullPath";
              value = boolToDword v.showFullPathInTitleBar;
            }
            ++ lib.optional (v.launchTo != null) {
              name = "LaunchTo";
              value = v.launchTo;
            }
            ++ lib.optional (v.showRecentFiles != null) {
              name = "Start_TrackDocs";
              value = boolToDword v.showRecentFiles;
            };
        in
        lib.optional (vals != [ ]) {
          path = explorerAdvanced;
          values = vals;
        };

      fromTaskbar =
        let
          v = cfg.taskbar;
          vals =
            lib.optional (v.alignment != null) {
              name = "TaskbarAl";
              value = v.alignment;
            }
            ++ lib.optional (v.showTaskView != null) {
              name = "ShowTaskViewButton";
              value = boolToDword v.showTaskView;
            }
            ++ lib.optional (v.showWidgets != null) {
              name = "TaskbarDa";
              value = boolToDword v.showWidgets;
            };
          searchVals = lib.optional (v.searchMode != null) {
            name = "SearchboxTaskbarMode";
            value = v.searchMode;
          };
        in
        lib.optional (vals != [ ]) {
          path = explorerAdvanced;
          values = vals;
        }
        ++ lib.optional (searchVals != [ ]) {
          path = searchPath;
          values = searchVals;
        };

      fromAppearance =
        let
          v = cfg.appearance;
          themeVals =
            lib.optional (v.appsTheme != null) {
              name = "AppsUseLightTheme";
              value = if v.appsTheme == "dark" then 0 else 1;
            }
            ++ lib.optional (v.systemTheme != null) {
              name = "SystemUsesLightTheme";
              value = if v.systemTheme == "dark" then 0 else 1;
            }
            ++ lib.optional (v.enableTransparency != null) {
              name = "EnableTransparency";
              value = boolToDword v.enableTransparency;
            };
        in
        lib.optional (themeVals != [ ]) {
          path = themesPersonalize;
          values = themeVals;
        };

      fromInput =
        let
          v = cfg.input;
          keyboardVals =
            lib.optional (v.keyboardRepeatRate != null) {
              name = "KeyboardSpeed";
              value = {
                type = "string";
                value = toString v.keyboardRepeatRate;
              };
            }
            ++ lib.optional (v.keyboardRepeatDelay != null) {
              name = "KeyboardDelay";
              value = {
                type = "string";
                value = toString v.keyboardRepeatDelay;
              };
            };
          mouseVals =
            lib.optional (v.mouseSensitivity != null) {
              name = "MouseSensitivity";
              value = {
                type = "string";
                value = toString v.mouseSensitivity;
              };
            }
            ++ lib.optional (v.mouseAcceleration != null) {
              name = "MouseSpeed";
              value = {
                type = "string";
                value = if v.mouseAcceleration then "1" else "0";
              };
            };
        in
        lib.optional (keyboardVals != [ ]) {
          path = "HKCU\\Control Panel\\Keyboard";
          values = keyboardVals;
        }
        ++ lib.optional (mouseVals != [ ]) {
          path = "HKCU\\Control Panel\\Mouse";
          values = mouseVals;
        };
    in
    fromExplorer ++ fromTaskbar ++ fromAppearance ++ fromInput;
in
{
  options.system.defaults = {
    explorer = {
      showFileExtensions = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Show file name extensions in Explorer.";
      };
      showHiddenFiles = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Show hidden files and folders in Explorer.";
      };
      showFullPathInTitleBar = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Show full path in Explorer title bar.";
      };
      launchTo = mkOption {
        type = types.nullOr (
          types.enum [
            1
            2
          ]
        );
        default = null;
        description = "Explorer launch target: 1 = This PC, 2 = Quick Access.";
      };
      showRecentFiles = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Track and show recently used files in Quick Access.";
      };
    };

    taskbar = {
      alignment = mkOption {
        type = types.nullOr (
          types.enum [
            0
            1
          ]
        );
        default = null;
        description = "Taskbar alignment: 0 = left, 1 = center (Windows 11).";
      };
      showTaskView = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Show Task View button on the taskbar.";
      };
      showWidgets = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Show Widgets button on the taskbar (Windows 11).";
      };
      searchMode = mkOption {
        type = types.nullOr (
          types.enum [
            0
            1
            2
            3
          ]
        );
        default = null;
        description = "Taskbar search mode: 0 = hidden, 1 = icon, 2 = box, 3 = box with icon.";
      };
    };

    appearance = {
      appsTheme = mkOption {
        type = types.nullOr (
          types.enum [
            "dark"
            "light"
          ]
        );
        default = null;
        description = "Application color theme.";
      };
      systemTheme = mkOption {
        type = types.nullOr (
          types.enum [
            "dark"
            "light"
          ]
        );
        default = null;
        description = "System UI color theme (taskbar, Start menu).";
      };
      enableTransparency = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Enable transparency effects.";
      };
    };

    input = {
      keyboardRepeatRate = mkOption {
        type = types.nullOr (types.ints.between 0 31);
        default = null;
        description = "Keyboard repeat rate (0 = slow, 31 = fast).";
      };
      keyboardRepeatDelay = mkOption {
        type = types.nullOr (types.ints.between 0 3);
        default = null;
        description = "Keyboard repeat delay (0 = short/250ms, 3 = long/1s).";
      };
      mouseSensitivity = mkOption {
        type = types.nullOr (types.ints.between 1 20);
        default = null;
        description = "Mouse pointer sensitivity (1-20, default: 10).";
      };
      mouseAcceleration = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Enable mouse acceleration (enhance pointer precision).";
      };
    };
  };

  config.system.registry = mkIf (registryEntries != [ ]) (mkRegistry registryEntries);
}
