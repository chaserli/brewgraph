# BrewGraph

BrewGraph is a simple macOS app for understanding what is installed through Homebrew.

It scans your local Homebrew installation, shows installed formulae and casks, and visualizes formula dependencies as an interactive graph. It is designed for inspection and diagnosis, not package management.

## What You Can Do

- See installed Homebrew formulae and casks.
- Explore a full formula dependency graph.
- Select a package and inspect what it depends on.
- See which installed packages use a selected package.
- View requested packages versus dependency-installed packages.
- Spot packages from third-party taps.
- Check outdated packages, leaves, runtime dependencies, warnings, and optional `brew doctor` output.

## Safety

BrewGraph is read-only.

It does not install, update, upgrade, uninstall, clean, tap, untap, zap, or delete anything. Cleanup information is shown only from Homebrew's dry-run output and is treated as an estimate of cache or old-version data.

## Requirements

- macOS 14 or newer
- Apple Silicon Mac
- Homebrew installed

## Build From Source

You need Xcode with Swift 6 support.

```bash
xcodebuild -project HomebrewLens.xcodeproj -scheme HomebrewLens -configuration Debug build
xcodebuild -project HomebrewLens.xcodeproj -scheme HomebrewLens -configuration Debug test
./script/build_and_run.sh --verify
```

The Xcode project and scheme are still named `HomebrewLens`; the app product is `BrewGraph.app`.

To build a local release zip:

```bash
./script/build_and_run.sh --release-package
```

The zip is written to `build/` and uses the release version in its name:

```text
build/BrewGraph-v0.1.0.zip
```

If you run the command away from a tag, the script uses the nearest tag or `local`.
