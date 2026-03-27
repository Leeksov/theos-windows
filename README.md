# Theos for Windows

Build iOS tweaks natively on Windows. No WSL, no VM, no macOS required.

## What This Does

Builds a complete iOS development toolchain on Windows:
- **Clang** cross-compiler (Apple fork by [L1ghtmann](https://github.com/L1ghtmann/llvm-project)) targeting arm64 iOS
- **lld** linker patched for iOS Mach-O linking on Windows
- **Theos** build system with Windows platform support
- All required tools: make, perl, ldid, dpkg-deb, fakeroot, etc.

## Prerequisites

| Tool | Required | Install |
|------|----------|---------|
| **Git for Windows** | Yes | https://git-scm.com/download/win |
| **Visual Studio 2022+** | Yes (C++ workload) | https://visualstudio.microsoft.com/ |
| **Python 3.x** | Yes (+ `zstandard` pip package) | https://python.org |

> Install Python `zstandard` module: `pip install zstandard`

## Installation

Open **Git Bash** and run:

```bash
git clone https://github.com/YourUsername/theos-windows.git
cd theos-windows
bash install.sh
```

The installer will:
1. Clone and build LLVM/Clang from source (~30-90 min)
2. Patch lld for iOS cross-compilation
3. Set up Theos with Windows platform support
4. Download iOS SDK
5. Install Strawberry Perl (for Logos preprocessor)
6. Create tool stubs (fakeroot, dpkg-deb, rsync)

Default install location: `~/theos-windows`. Override with:
```bash
bash install.sh /c/path/to/install
```

## Post-Install Setup

Add to your `~/.bashrc`:

```bash
export THEOS="$HOME/theos-windows/theos"
export PATH="$HOME/theos-windows/tools-bin:$THEOS/toolchain/windows/iphone/bin:$PATH"
export MSYS2_ARG_CONV_EXCL="-install_name;-dylib_install_name;/Library"
```

Then restart your terminal or `source ~/.bashrc`.

## Usage

### Create a new tweak

```bash
$THEOS/bin/nic.pl
```

### Makefile template

```makefile
ARCHS = arm64
TARGET = iphone:16.5:15.0
TARGET_CODESIGN =
_THEOS_PLATFORM_DPKG_DEB = dpkg-deb

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MyTweak
MyTweak_FILES = Tweak.x
MyTweak_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
```

### Build

```bash
make                    # compile
make package            # compile + .deb
make clean              # clean build
```

The `.deb` package will be in `./packages/`.

## Supported File Types

| Extension | Description | Status |
|-----------|-------------|--------|
| `.m` | Objective-C | Fully supported |
| `.mm` | Objective-C++ | Fully supported |
| `.c` | C | Fully supported |
| `.cpp` | C++ | Fully supported |
| `.x` | Logos (ObjC) | Fully supported |
| `.xm` | Logos (ObjC++) | Fully supported |
| `.swift` | Swift | Not supported (no Swift cross-compiler) |

## Important Notes

- **No spaces in project path.** GNU Make doesn't handle spaces. Keep projects in paths like `C:\dev\tweaks\MyTweak`.
- **MSYS2 path conversion.** The `MSYS2_ARG_CONV_EXCL` env var prevents Git Bash from mangling iOS paths like `/Library/`.
- **Code signing** is disabled by default (`TARGET_CODESIGN =`). Sign on-device or use ldid separately.
- **CydiaSubstrate** is provided as a stub dylib for linking. The real library loads at runtime on the device.

## Project Structure

```
theos-windows/
├── install.sh              # Automated installer
├── theos/                  # Theos build system
│   ├── toolchain/windows/iphone/bin/   # Cross-compiler
│   ├── sdks/               # iOS SDKs
│   └── makefiles/          # Patched for Windows
├── tools-bin/              # Windows-native tools
│   ├── make.exe            # MSYS2 GNU Make
│   ├── perl                # Strawberry Perl wrapper
│   ├── fakeroot            # Stub (no-op on Windows)
│   ├── dpkg-deb            # Minimal .deb packager
│   └── rsync               # cp-based replacement
├── strawberry-perl/        # Full Perl for Logos
├── llvm-build/             # Built LLVM binaries
└── tools-src/              # Build sources
```

## Troubleshooting

### "does not support linking for platform iOS"
The lld patch wasn't applied. Re-run the installer or manually edit `llvm-project/lld/MachO/InputFiles.cpp` — remove the `error()` call in `checkCompatibility()`.

### "stdarg.h not found"
Clang can't find its builtin headers. Ensure `toolchain/windows/iphone/lib/clang/<version>/include/` exists and contains `stdarg.h`.

### Logos (.x) files fail with "Can't locate..."
Strawberry Perl isn't in PATH, or its modules are missing. Verify: `perl -e "use Locale::Maketext::Simple; print 'OK'"`.

### "platform does not define a default target"
Platform detection failed. Ensure you're using MSYS2 make (not MSVC native make): `make --version` should show `Built for x86_64-pc-msys`.

## Credits

- [Theos](https://github.com/theos/theos) — the jailbreak build system
- [L1ghtmann/llvm-project](https://github.com/L1ghtmann/llvm-project) — Apple LLVM fork with iOS cross-compilation support
- [Strawberry Perl](https://strawberryperl.com/) — full Perl for Windows

## License

The installer scripts are MIT licensed. Individual components have their own licenses:
- LLVM: Apache 2.0 with LLVM Exception
- Theos: GPLv3
- Strawberry Perl: Artistic License / GPL
