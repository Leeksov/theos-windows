# Theos Windows Patches

All modifications to the original [theos/theos](https://github.com/theos/theos) source code for Windows support.

## 1. Platform Detection — `makefiles/common.mk`

Maps MINGW/MSYS/Cygwin to unified "Windows" platform.

```diff
 uname_s := $(shell uname -s)
 uname_o := $(shell uname -o 2>/dev/null)

+ifneq ($(filter MINGW% MSYS% CYGWIN%,$(uname_s)),)
+export _THEOS_PLATFORM := Windows
+export _THEOS_OS := Windows
+else
 export _THEOS_PLATFORM = $(uname_s)
 export _THEOS_OS = $(if $(uname_o),$(uname_o),$(uname_s))
+endif
 export _THEOS_PLATFORM_CALCULATED := 1
```

## 2. Windows Platform Config — `makefiles/platform/Windows.mk`

Added `_THEOS_PLATFORM_DPKG_DEB` and `TARGET_CODESIGN` defaults:

```makefile
ifeq ($(_THEOS_PLATFORM_LOADED),)
_THEOS_PLATFORM_LOADED := 1
THEOS_PLATFORM_NAME := windows

_THEOS_PLATFORM_DEFAULT_TARGET := iphone
_THEOS_PLATFORM_DU_EXCLUDE := --exclude
_THEOS_PLATFORM_MD5SUM := md5sum
_THEOS_PLATFORM_SHOW_IN_FILE_MANAGER := explorer /select,
_THEOS_PLATFORM_SHOW_IN_FILE_MANAGER_PATH_TRANSLATOR := cygpath -aw
_THEOS_PLATFORM_GET_LOGICAL_CORES := nproc
_THEOS_PLATFORM_DPKG_DEB ?= dpkg-deb    # <-- NEW: use stub
TARGET_CODESIGN ?= true                  # <-- NEW: skip ldid

endif
```

## 3. Codesign Bypass — `makefiles/targets/_common/darwin_head.mk`

Skip ldid on Windows (it crashes on `C:` paths in temp files).

```diff
 ifeq ($(TARGET_CODESIGN),)
+ifeq ($(THEOS_PLATFORM_NAME),windows)
+	TARGET_CODESIGN = true
+else
 ifeq ($(call __executable,ldid),$(_THEOS_TRUE))
 	TARGET_CODESIGN = ldid
 ...
 endif
+endif
 endif
```

## 4. Linker Config — `makefiles/targets/_common/darwin_tail.mk`

Detect `ld64.lld.exe` wrapper and add `-B` search path.

```diff
 ifneq ($(_THEOS_TARGET_SDK_BIN_PREFIX),)
 _THEOS_TARGET_LDFLAGS += -fuse-ld=$(SDKBINPATH)/$(_THEOS_TARGET_SDK_BIN_PREFIX)ld
+else ifneq ($(wildcard $(SDKBINPATH)/ld64.lld.exe),)
+_THEOS_TARGET_LDFLAGS += -B$(SDKBINPATH)
 endif
```

## 5. Broken Symlinks → Real Files

Windows Git doesn't create real symlinks. These files are text pointers that need to be replaced with actual copies:

| Symlink | Target |
|---------|--------|
| `bin/logos.pl` | `vendor/logos/bin/logos.pl` |
| `bin/logify.pl` | `vendor/logos/bin/logify.pl` |
| `bin/dm.pl` | `vendor/dm.pl/dm.pl` |
| `bin/nic.pl` | `vendor/nic/bin/nic.pl` |
| `bin/nicify.pl` | `vendor/nic/bin/nicify.pl` |
| `bin/denicify.pl` | `vendor/nic/bin/denicify.pl` |
| `vendor/include/substrate.h` | `vendor/include/CydiaSubstrate.h` |
| `vendor/include/IOKit/IOKit.h` | `vendor/include/IOKit/IOKitLib.h` |

## 6. Logos Perl Modules — `bin/lib/`

Copied from `vendor/logos/bin/lib/` to `bin/lib/` (39 files). Required because `logos.pl` references `$FindBin::RealBin/lib`.

## 7. CydiaSubstrate Stub — `vendor/lib/CydiaSubstrate.framework/`

Replaced `.tbd` (text-based stub) with real Mach-O arm64 dylib. LLD on Windows doesn't support `.tbd` files.

- **Deleted:** `CydiaSubstrate.tbd`, `libsubstrate.tbd`
- **Added:** `CydiaSubstrate` (Mach-O 64-bit arm64 dylib with stub symbols)

Stub exports: `MSHookMessageEx`, `MSHookFunction`, `MSGetImageByName`, `MSFindSymbol`

## 8. ld64.lld Wrapper — `toolchain/windows/iphone/bin/ld64.lld.exe`

Small C wrapper that invokes `ld64.lld.real.exe` with:
- `-flavor ld64` (force Mach-O mode, since lld detects flavor by argv[0])
- `-iphoneos_version_min X` → `-platform_version ios X Y` translation
- Strips unsupported `-multiply_defined` flag

```
ld64.lld.exe (wrapper, 112 KB)  →  ld64.lld.real.exe (real lld, 50 MB)
ld.exe (copy of wrapper)
```

## 9. LLD iOS Patch — `llvm-project/lld/MachO/InputFiles.cpp`

Apple's LLVM fork blocks iOS linking in lld with a hardcoded error. Removed:

```diff
 static bool checkCompatibility(const InputFile *input) {
   ...
-  // Swift LLVM fork downstream change start
-  error("This version of lld does not support linking for platform " +
-        getPlatformName(platformInfos.front().target.Platform));
-  return false;
-  // Swift LLVM fork downstream change end
+  // Swift LLVM fork downstream change disabled for Windows cross-compilation
   ...
```

## 10. Clang Builtin Headers

Copied `llvm-build/lib/clang/19/include/` → `toolchain/windows/iphone/lib/clang/19/include/`

Required for `stdarg.h`, `stdbool.h`, `stddef.h` etc. that iOS SDK headers depend on.

## Toolchain Binaries

All in `toolchain/windows/iphone/bin/`:

| Binary | Source | Purpose |
|--------|--------|---------|
| `clang.exe` | LLVM build | C/ObjC compiler |
| `clang++.exe` | LLVM build | C++/ObjC++ compiler |
| `lld.exe` | LLVM build | LLVM linker (multi-flavor) |
| `ld64.lld.real.exe` | LLVM build | Real Mach-O linker |
| `ld64.lld.exe` | C wrapper | Mach-O linker wrapper |
| `ld.exe` | C wrapper | Same wrapper |
| `dsymutil.exe` | LLVM build | Debug symbols |
| `strip.exe` | `llvm-strip` | Strip binaries |
| `ar.exe` | `llvm-ar` | Archive tool |
| `nm.exe` | `llvm-nm` | Symbol table |
| `lipo.exe` | `llvm-lipo` | Universal binaries |
| `otool.exe` | `llvm-otool` | Object file viewer |
| `libtool.exe` | `llvm-libtool-darwin` | Static library tool |
| `install_name_tool.exe` | `llvm-install-name-tool` | Mach-O install names |
