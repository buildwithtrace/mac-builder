# Trace Mac Builder

This repository contains the build system for creating signed and notarized macOS DMG installers for **Trace**, a fork of KiCad focused on AI-powered PCB design.

## Requirements

- macOS 15.6 or later
- Xcode Command Line Tools
- Homebrew
- At least 30GB of free disk space
- Apple Developer ID certificate (for signing)
- Apple App-Specific Password (for notarization)

## Directory Structure

The build system expects the following directory layout:

```
parent-directory/
├── trace-mac-builder/     # This repository
└── Trace/                 # The Trace source code repository
```

**Important:** Both repositories must be in the same parent directory. The build script references the Trace source using a relative path.

## Setup

### 1. Clone both repositories

```bash
cd /path/to/parent-directory

# Clone this repository
git clone https://github.com/elcruzo/trace-mac-builder.git

# Clone the Trace source code
git clone https://github.com/yourusername/Trace.git
```

### 2. Install dependencies

Review and run the appropriate bootstrap script from `ci/`:

```bash
cd trace-mac-builder
# Review the script first!
./ci/src/bootstrap.sh
```

## Building Trace

### Basic Build

To build Trace with default settings:

```bash
cd trace-mac-builder
./build.py --arch arm64 --target package-kicad-unified
```

### Full Build with Signing and Notarization

For a complete signed build ready for distribution:

```bash
cd trace-mac-builder

WX_SKIP_DOXYGEN_VERSION_CHECK=1 ./build.py \
  --kicad-source-dir /path/to/parent-directory/Trace \
  --arch arm64 \
  --signing-identity "Developer ID Application: Your Name (TEAM_ID)" \
  --signing-certificate-id YOUR_CERTIFICATE_ID \
  --hardened-runtime \
  --target package-kicad-unified
```

**Replace:**
- `/path/to/parent-directory/Trace` with the actual path to your Trace source directory
- `Developer ID Application: Your Name (TEAM_ID)` with your Apple Developer signing identity
- `YOUR_CERTIFICATE_ID` with your certificate ID (found with `security find-identity -v -p codesigning`)

### Build Options

- `--arch arm64` - Build for Apple Silicon (use `x86_64` for Intel Macs)
- `--kicad-source-dir` - Path to the Trace source directory
- `--signing-identity` - Your Apple Developer ID Application identity
- `--signing-certificate-id` - The certificate ID from your keychain
- `--hardened-runtime` - Enable Hardened Runtime (required for notarization)
- `--target package-kicad-unified` - Build a complete DMG with all content

## Output

The built DMG will be located in:

```
trace-mac-builder/build/dmg/trace-unified-YYYYMMDD-HHMMSS-GITHASH.dmg
```

The DMG includes:
- Trace.app (main application)
- All sub-applications (Schematic Editor, PCB Editor, etc.)
- Component libraries (footprints, symbols, 3D models)
- Documentation
- Demo projects

## Notarization and Stapling

After the build completes, notarize the DMG with Apple:

```bash
cd trace-mac-builder/build/dmg

# Submit for notarization
xcrun notarytool submit Trace.dmg \
  --apple-id your-apple-id@email.com \
  --team-id YOUR_TEAM_ID \
  --password YOUR_APP_SPECIFIC_PASSWORD \
  --wait

# Staple the notarization ticket
xcrun stapler staple Trace.dmg

# Validate the notarization
xcrun stapler validate Trace.dmg
```

**Replace:**
- `your-apple-id@email.com` with your Apple ID
- `YOUR_TEAM_ID` with your Apple Team ID
- `YOUR_APP_SPECIFIC_PASSWORD` with your app-specific password ([create one here](https://appleid.apple.com/account/manage))

### Getting Your Credentials

1. **Team ID**: Found in your [Apple Developer account](https://developer.apple.com/account)
2. **Certificate ID**: Run `security find-identity -v -p codesigning`
3. **App-Specific Password**: Generate at [appleid.apple.com](https://appleid.apple.com/account/manage)

## Apple Silicon Notes

On Apple Silicon Macs:
- Use `--arch arm64` for native builds
- Ensure Homebrew is installed in `/opt/homebrew`
- Make sure `/opt/homebrew/bin` is in your PATH before any `/usr/local/bin`

For Intel builds on Apple Silicon:
```bash
PATH=/usr/local/bin:$PATH arch -x86_64 ./build.py --arch x86_64
```

## Troubleshooting

### Build artifacts in the way

Clean the build directory:
```bash
rm -rf trace-mac-builder/build
```

### DMG too small errors

The DMG size is configured in `kicad-mac-builder/bin/package.sh`. If you get errors about insufficient space, increase the `DMG_SIZE` value.

If you need to manually enlarge the template DMG, use the script in `dmgbuild/`.

### Notarization fails

Common issues:
- Unsigned `.o` files in the bundle (should be cleaned automatically)
- Missing Hardened Runtime flag
- Invalid certificate or expired credentials

Check the notarization log:
```bash
xcrun notarytool log SUBMISSION_ID \
  --apple-id your-apple-id@email.com \
  --team-id YOUR_TEAM_ID \
  --password YOUR_APP_SPECIFIC_PASSWORD
```

### Dependencies issues

If you encounter issues with dependencies:
1. Check the output of `ci/src/watermark.sh` for diagnostic information about your setup
2. Review and re-run the appropriate `bootstrap.sh` script in `ci/`
3. Ensure Homebrew paths are correct (see Apple Silicon Notes above)

### Debugging dylib issues

When debugging dynamic library loading issues, use:
```bash
DYLD_PRINT_LIBRARIES=YES DYLD_PRINT_LIBRARIES_POST_LAUNCH=YES \
  /Applications/Trace/Trace.app/Contents/MacOS/trace
```

## Setting up a Trace Development Environment

You can use trace-mac-builder to set up a development environment for Trace on macOS.

1. Run the setup target:
```bash
./build.py --arch=arm64 --target setup-kicad-dependencies
```

2. At the end, you'll see CMake arguments. Save these.

3. In your Trace source directory:
```bash
mkdir build
cd build
cmake [paste those CMake arguments here] ../
make
make install
```

The built Trace will be at the location specified in `CMAKE_INSTALL_PREFIX`.

**Note:** Apps built this way work but may not be relocatable or distributable. Use the full build process above to create distributable DMGs.

## Testing Your Build

After building, verify the key functionality:

### Basic functionality
- Open Trace.app and launch each sub-application (Schematic Editor, PCB Editor, etc.)
- Open each app in standalone mode from `/Applications/Trace/`

### Python integration
- Open PCB Editor, go to Tools → Scripting Console
- Type `import pcbnew` and press Enter - should not error
- Verify Python build date matches package build date

### Trace AI features
- Open a `.kicad_sch` file - should auto-convert to `.trace_sch`
- Verify toolbar is visible on launch
- Test AI chat in Schematic Editor

### 3D Models
- Open `demos/pic_programmer/` project in PCB Editor
- Click View → 3D Viewer - should show populated PCB with components

### Localization
- Go to Preferences → Language and change language
- Verify menubar text changes

## What's Different from KiCad Mac Builder?

This is a fork of the official KiCad Mac Builder with modifications for Trace:
- Renamed output from `KiCad` to `Trace`
- Updated branding and application identifiers
- Modified to include Trace-specific features and backend integration
- Adjusted Python scripting paths for Trace's format conversion tools
- Added support for `.trace_sch` and `.trace_pcb` file formats
- Integrated Trace backend API communication

## Making Changes to trace-mac-builder

### New Dependencies

- Do not assume Homebrew uses default paths. See `build.py` for examples.
- Add any new dependencies to this README and to the `ci/` scripts.
- Test changes on a clean VM to ensure reproducible builds.

### Linting

To check your changes for style issues, install `shellcheck` and `cmakelint`:

```bash
# Check shell scripts
find . -path ./build -prune -o -name \*.sh -exec shellcheck {} \;

# Check CMake files
cmakelint --filter=-linelength,-readability/wonkycase kicad-mac-builder/CMakeLists.txt
find . -path ./build -prune -o -name \*.cmake -exec cmakelint --filter=-linelength,-readability/wonkycase {} \;
```

### Testing Changes

Before major releases or changes:
1. Remove the `build/` directory and run a clean build with `./build.py`
2. Rerun `./build.py` to verify incremental builds work
3. Run the test procedure above to verify all functionality
4. Test on both Intel and Apple Silicon if possible

## Issues and Support

For issues with:
- **Trace application**: Report at the Trace repository
- **Build system**: Report at this repository (trace-mac-builder)
- **macOS-specific packaging**: Check both repositories

When reporting build issues, include:
- Output of `ci/src/watermark.sh`
- Full build log
- macOS version and architecture
- Homebrew version and installation path

## Contributing

This is the build system for Trace. Contributions are welcome for:
- Build system improvements
- macOS packaging enhancements
- Documentation updates
- Bug fixes

Please ensure all changes:
- Work on both Intel and Apple Silicon
- Pass linting checks
- Include updated documentation
- Are tested with clean builds

## License

This build system is based on KiCad Mac Builder and inherits its license. See the original [KiCad Mac Builder repository](https://gitlab.com/kicad/packaging/kicad-mac-builder) for license details.

Trace modifications are subject to the Trace project license.

---

**Note:** This builder does not install Trace onto your system or modify any existing installations. It only creates a distributable DMG file.

## Credits

Based on [KiCad Mac Builder](https://gitlab.com/kicad/packaging/kicad-mac-builder) by the KiCad development team.

Modified for Trace by the Trace development team.
