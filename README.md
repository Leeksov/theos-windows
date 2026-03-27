# Theos for Windows

Build iOS tweaks natively on Windows. No WSL, no VM, no macOS required.

## Install

Everything downloads automatically from GitHub. Nothing to build.

### Option 1: PowerShell (recommended, auto-installs Git if needed)

```powershell
powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/Leeksov/theos-windows/master/install.ps1 -OutFile i.ps1; .\i.ps1; del i.ps1"
```

### Option 2: Git Bash (if you already have Git)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Leeksov/theos-windows/master/install.sh)
```

### Prerequisites
- [Python 3](https://python.org) + `pip install zstandard`
- Git for Windows — installed automatically if missing

Installs to `~/.theos` (`%USERPROFILE%\.theos`). Restart terminal after install.

## Usage

### Create a tweak

```bash
$THEOS/bin/nic.pl
```

### Makefile

```makefile
ARCHS = arm64
TARGET = iphone:16.5:15.0
TARGET_CODESIGN = true
_THEOS_PLATFORM_DPKG_DEB = dpkg-deb

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MyTweak
MyTweak_FILES = Tweak.x
MyTweak_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
```

### Build

```bash
make              # compile only
make package      # compile + .deb
make clean        # clean
```

`.deb` goes to `./packages/`.

## What Gets Installed

| Component | Size | Source |
|-----------|------|--------|
| Clang/LLD cross-compiler | ~150 MB | Pre-built from [L1ghtmann/llvm-project](https://github.com/L1ghtmann/llvm-project) (Apple fork) |
| GNU Make (MSYS2) | ~1 MB | Pre-built |
| ldid (code signing) | ~1 MB | Built from [ProcursusTeam/ldid](https://github.com/ProcursusTeam/ldid) |
| Theos | ~50 MB | Cloned from [theos/theos](https://github.com/theos/theos) |
| iOS SDK | ~70 MB | Downloaded by Theos |
| Strawberry Perl | ~290 MB | Downloaded from [strawberryperl.com](https://strawberryperl.com) (needed for Logos `.x` files) |
| Tool stubs | ~5 KB | fakeroot, dpkg-deb, rsync replacements |

## Supported File Types

| Extension | Type | Status |
|-----------|------|--------|
| `.m` | Objective-C | ✅ |
| `.mm` | Objective-C++ | ✅ |
| `.c` / `.cpp` | C / C++ | ✅ |
| `.x` | Logos (ObjC) | ✅ |
| `.xm` | Logos (ObjC++) | ✅ |
| `.swift` | Swift | ❌ No cross-compiler |

## Important Notes

- **No spaces in project path.** Use paths like `C:\dev\tweaks\MyTweak`
- **Code signing** is disabled by default. Sign on-device or use ldid separately
- **CydiaSubstrate** is a stub for linking — the real lib loads on-device
- Uses MSYS2 make (not MSVC make) — required for bash-based Theos makefiles

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `platform does not define a default target` | Use MSYS2 make: `make --version` → must say `x86_64-pc-msys` |
| `stdarg.h not found` | Missing clang headers. Re-run installer |
| Logos `.x` fails with `Can't locate...` | Perl issue. Run: `perl -e "use Locale::Maketext::Simple"` |
| `does not support linking for platform iOS` | lld not patched. Re-download toolchain |
| Path errors with `C:/Program Files/...` | Set `export MSYS2_ARG_CONV_EXCL="-install_name;-dylib_install_name;/Library"` |

## How It Works

The installer downloads a pre-built LLVM/Clang cross-compiler (Apple fork with iOS support), patches lld's Mach-O linker to allow iOS linking on Windows, sets up Theos with Windows platform detection, and provides stub replacements for Unix-only tools.

Key patches:
- **lld**: Removes Apple's "platform not supported" check in `InputFiles.cpp` that blocks iOS linking on non-macOS
- **ld wrapper**: Translates `-iphoneos_version_min` to `-platform_version ios` (lld ld64 flavor requirement)
- **Theos makefiles**: MINGW/MSYS → Windows platform mapping, ld64.lld linker path

## Credits

- [Theos](https://github.com/theos/theos)
- [L1ghtmann/llvm-project](https://github.com/L1ghtmann/llvm-project)
- [ProcursusTeam/ldid](https://github.com/ProcursusTeam/ldid)
- [Strawberry Perl](https://strawberryperl.com/)

## License

MIT (installer scripts). Components have their own licenses (LLVM: Apache 2.0, Theos: GPLv3, Perl: Artistic/GPL).
