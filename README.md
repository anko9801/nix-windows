# nix-windows

Declarative Windows configuration — packages, dotfiles, services, and registry — defined in Nix, deployed from WSL.

Built on `lib.evalModules`, the same module system as NixOS and Home Manager.

## Quick Start

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-windows.url = "github:anko9801/nix-windows";
  };

  outputs = { nixpkgs, nix-windows, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      packages.x86_64-linux.windows = nix-windows.lib.mkNixWindows {
        inherit pkgs;
        modules = nix-windows.nixWindowsModules.default ++ [
          {
            system.stateVersion = 1;
            windows.username = "your-username";

            programs.git = {
              enable = true;
              settings.user = {
                name = "Your Name";
                email = "you@example.com";
              };
            };

            system.defaults = {
              appearance.appsTheme = "dark";
              explorer.showFileExtensions = true;
              explorer.showHiddenFiles = true;
            };

            windows.fonts = [ pkgs.moralerspace ];
          }
        ];
      };
    };
}
```

```bash
nix run .#windows               # activate
nix run .#windows -- --dry-run  # preview changes
```

## What You Can Configure

### Program Modules

Typed configuration modules for shells, editors, terminals, window managers, key remappers, and more. Options are type-checked at build time — invalid values are caught before anything touches your system. Modules integrate with each other where it makes sense.

### System Defaults & Registry

`system.defaults` provides typed options for common Windows settings — explorer, taskbar, appearance, input — that map to registry entries automatically. For anything beyond defaults, `system.registry` gives direct HKCU/HKLM access.

```nix
system.defaults.appearance.appsTheme = "dark";
system.defaults.taskbar.alignment = 0;        # left-aligned
system.defaults.explorer.launchTo = 1;        # This PC

system.registry.HKCU.Software.MyApp.Setting = "value";
```

### Services, Tasks & Environment

Manage Windows services, scheduled tasks, and user environment variables declaratively. Admin-level operations generate separate PowerShell scripts that require elevation.

```nix
system.services."ServiceName".startupType = "Manual";

windows.tasks."BackupTask" = {
  executable = "C:\\backup.exe";
  schedule = { type = "daily"; at = "02:00AM"; };
};

environment.variables.EDITOR = "code";
environment.userPath = [ "C:\\Tools" ];
```

### Files

Deploy files to Windows paths, following the same pattern as Home Manager's `home.file`:

```nix
windows.file."%USERPROFILE%/.config/app.conf".text = "key = value";
windows.file."%APPDATA%/app/config.json".source = ./config.json;
```

Path variables (`%USERPROFILE%`, `%APPDATA%`, `%LOCALAPPDATA%`, `%PROGRAMDATA%`) are resolved at runtime via `cmd.exe`. Files are tracked by content hash — external modifications trigger warnings, stale files are cleaned up, and every activation is recorded as a generation.

## Examples

<details>
<summary>Komorebi tiling WM + whkd hotkeys</summary>

```nix
{
  programs.komorebi = {
    enable = true;
    settings = {
      activeWindowBorderEnabled = true;
      activeWindowBorderColour = { r = 150; g = 150; b = 255; a = 255; };
    };
  };

  programs.whkd = {
    enable = true;
    bindings = {
      "alt + h" = "komorebic focus left";
      "alt + j" = "komorebic focus down";
      "alt + k" = "komorebic focus up";
      "alt + l" = "komorebic focus right";
      "alt + shift + h" = "komorebic move left";
      "alt + shift + j" = "komorebic move down";
      "alt + shift + k" = "komorebic move up";
      "alt + shift + l" = "komorebic move right";
    };
  };
}
```

</details>

<details>
<summary>WSL configuration (.wslconfig + wsl.conf)</summary>

```nix
{
  programs.wsl = {
    enable = true;
    settings = {
      memory = "8GB";
      processors = 4;
      swap = "4GB";
      localhostForwarding = true;
    };
    experimental = {
      sparseVhd = true;
      autoMemoryReclaim = "gradual";
    };
    conf = {
      boot.systemd = true;
      interop.enabled = true;
    };
  };
}
```

</details>

<details>
<summary>Winget package management</summary>

```nix
{
  programs.winget = {
    enable = true;
    autoApply = true;
    onActivation.cleanup = true;

    packages = [
      "Microsoft.PowerShell"
      "7zip.7zip"
      "Git.Git"
      { id = "Mozilla.Firefox"; version = "130.0"; }
    ];
  };
}
```

</details>


## Prerequisites

- WSL 2
- Nix with flakes enabled
- Windows 10 (build 19041+) or 11

## Contributing

```bash
nix flake check    # run tests
nix fmt            # format code
```

## License

MIT
