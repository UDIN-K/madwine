# madwine

Run [Madium](https://madium.net) on Linux via Wine. Unofficial, community-maintained fork.

> **Original project:** [Ring0lw/madwine](https://github.com/Ring0lw/madwine) (inactive since Oct 2026)

## What it does

- Creates a Wine prefix with all required dependencies
- Installs **.NET 8 Desktop Runtime** automatically
- Installs **WebView2 Runtime** (offline installer — no bootstrapper issues)
- Fixes WebView2 registry keys (Wine's installer often skips this step)
- Handles the half-install problem where WebView2 unpacks to `EdgeCore` but never copies to `EdgeWebView/Application`
- **Downloads Madium CDN files from host Linux** (bypasses Wine SSL-to-IP failure that causes the CDN Error)
- Auto-verifies downloads with SHA256 checksums

## Requirements

- **Wine** (wine-stable, wine-staging, or Proton)
- **curl** or **wget**
- Linux x86_64

### Install Wine (if you don't have it)

**Arch / CachyOS / Manjaro:**
```bash
sudo pacman -S wine
```

**Ubuntu / Debian:**
```bash
sudo apt install wine64
```

**Fedora:**
```bash
sudo dnf install wine
```

## Quick start

```bash
git clone https://github.com/UDIN-K/madwine.git
cd madwine
chmod +x install.sh
./install.sh install
```

That's it. All dependencies and executor files are downloaded and installed automatically.

## Usage

```
./install.sh <command>

Commands:
  install     Full install: prefix + .NET 8 + WebView2 + Madium + CDN files
  update      Update Madium CDN files (DLLs + cache) to latest version
  deps        Install dependencies only (.NET 8 + WebView2)
  launch      Launch Madium
  desktop     Create desktop shortcut
  prefix      Show Wine prefix path
  status      Check installation status
  clean       Remove Wine prefix and cache
  help        Show this help
```

### Launch Madium
```bash
./install.sh launch
```

### Update after Madium releases a new version
```bash
./install.sh update
```

### Create a desktop shortcut
```bash
./install.sh desktop
```

### Check what's installed
```bash
./install.sh status
```

## Using with Proton / Faugus Launcher

If you already have a Wine prefix (e.g. from Faugus Launcher), point madwine at it:

```bash
export WINEPREFIX="/path/to/your/prefix"
./install.sh deps      # install .NET 8 + WebView2 into existing prefix
./install.sh update    # download CDN files into existing prefix
```

For Proton-based setups:
```bash
export WINE="/path/to/Proton/files/bin/wine"
export WINEPREFIX="/path/to/prefix"
./install.sh deps
./install.sh update
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WINEPREFIX` | `~/.local/share/madwine/prefix` | Wine prefix path |
| `WINE` | `wine` | Wine executable |
| `MADWINE_DIR` | `~/.local/share/madwine` | Data/cache directory |

## Troubleshooting

### "The dependency installer stopped before finishing"
This is what madwine fixes. The Madium installer tries to run .NET 8 and WebView2 bootstrappers, which fail under Wine. madwine pre-installs both using methods that work in Wine.

### "Couldn't reach the Madium server" / CDN Error
Wine can't make SSL connections to bare IP addresses (like `165.245.199.89`). madwine downloads the files from the host Linux system instead — no Wine networking needed. Run:
```bash
./install.sh update
```

### Black/blank Madium window
WebView2 registry keys are missing. Run:
```bash
./install.sh deps
```
This re-registers WebView2 in all required registry locations.

### WebView2 installer hangs
The WebView2 bootstrapper (online installer) hangs under Wine. madwine uses the **offline standalone installer** instead, which completes without issues.

### .NET 8 install fails
Try installing manually:
```bash
export WINEPREFIX="$HOME/.local/share/madwine/prefix"
wine ~/.local/share/madwine/cache/dotnet-8-desktop-runtime.exe
```

## How it works

1. Creates an isolated Wine prefix
2. Downloads .NET 8 Desktop Runtime (offline exe) and runs it with `/quiet /norestart`
3. Downloads WebView2 offline standalone installer (not the bootstrapper — the bootstrapper hangs in Wine)
4. Runs the WebView2 installer; if it half-completes (common Wine behavior), manually copies the runtime from `EdgeCore/` to `EdgeWebView/Application/`
5. Registers WebView2 in the Windows registry (3 key locations: HKLM 32-bit, HKLM 64-bit, HKCU)
6. Downloads and runs MadiumInstaller.exe
7. **Fetches Madium CDN files** (Madium.dll, RobloxPlayerBeta.dll, cache.bin) from the host — bypassing Wine's broken SSL-to-IP networking
8. Verifies all downloads with SHA256 checksums from the manifest

## Contributing

PRs welcome. The main areas that need work:

- [x] ~~CDN download fallback~~ — solved: host-side download bypasses Wine
- [ ] Auto-update on Madium version change
- [ ] Flatpak packaging
- [ ] ARM64 support
- [ ] Better Proton/Steam integration
- [ ] Roblox version pinning

## License

MIT

## Credits

- Original madwine: [Ring0lw](https://github.com/Ring0lw/madwine)
- WebView2-on-Wine research: [akacross/fivem-enhanced-linux](https://github.com/akacross/fivem-enhanced-linux), [Amzi-01's FiveM guide](https://gist.github.com/Amzi-01/7ad2ea3f15c4aa2e855c03c71575139a)
