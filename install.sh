#!/usr/bin/env bash
# Theos for Windows - Automated Installer
# Requires: Git Bash (comes with Git for Windows), Visual Studio 2022+ with C++ workload
# Usage: bash install.sh [--prefix /path/to/install]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { printf "${BLUE}==> ${NC}%s\n" "$1"; }
ok()    { printf "${GREEN}==> ${NC}%s\n" "$1"; }
warn()  { printf "${YELLOW}==> ${NC}%s\n" "$1"; }
error() { printf "${RED}==> ${NC}%s\n" "$1"; exit 1; }

# ── Configuration ──────────────────────────────────────────────────
PREFIX="${1:-$HOME/theos-windows}"
PREFIX="${PREFIX//\\//}" # normalize backslashes

LLVM_REPO="https://github.com/L1ghtmann/llvm-project.git"
THEOS_REPO="https://github.com/theos/theos.git"
STRAWBERRY_PERL_URL="https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/latest"
MSYS2_MAKE_URL="https://repo.msys2.org/msys/x86_64/"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Preflight checks ──────────────────────────────────────────────
info "Checking prerequisites..."

# Git
command -v git >/dev/null 2>&1 || error "Git not found. Install Git for Windows: https://git-scm.com/download/win"

# Python (for extracting zstd archives)
PYTHON=""
for p in python3 python; do
    if command -v "$p" >/dev/null 2>&1; then PYTHON="$p"; break; fi
done
if [ -z "$PYTHON" ]; then
    # Try Windows Python
    for p in "/c/Users/$USER/AppData/Local/Programs/Python/"*/python.exe; do
        [ -x "$p" ] && PYTHON="$p" && break
    done
fi
[ -z "$PYTHON" ] && error "Python not found. Install from https://python.org"

# Visual Studio
VCVARS=""
for year in 18 17 16; do
    for edition in Community Professional Enterprise BuildTools; do
        candidate="/c/Program Files/Microsoft Visual Studio/$year/$edition/VC/Auxiliary/Build/vcvars64.bat"
        [ -f "$candidate" ] && VCVARS="$candidate" && break 2
    done
done
[ -z "$VCVARS" ] && error "Visual Studio with C++ workload not found."

# Find cmake and ninja from VS
CMAKE=$(find "/c/Program Files/Microsoft Visual Studio" -name "cmake.exe" -path "*/CMake/CMake/bin/*" 2>/dev/null | head -1)
NINJA=$(find "/c/Program Files/Microsoft Visual Studio" -name "ninja.exe" -path "*/CMake/Ninja/*" 2>/dev/null | head -1)
[ -z "$CMAKE" ] && error "CMake not found in Visual Studio installation"
[ -z "$NINJA" ] && error "Ninja not found in Visual Studio installation"

VCVARS_WIN="$(cygpath -w "$VCVARS" 2>/dev/null || echo "$VCVARS")"
CMAKE_WIN="$(cygpath -w "$CMAKE" 2>/dev/null || echo "$CMAKE")"
NINJA_WIN="$(cygpath -w "$NINJA" 2>/dev/null || echo "$NINJA")"

ok "All prerequisites found"
info "Install prefix: $PREFIX"
info "Visual Studio: $VCVARS"

# ── Helper: run in VS developer prompt ─────────────────────────────
run_vs() {
    local bat_file="$1"
    cmd.exe //c "$bat_file" 2>&1
}

mkdir -p "$PREFIX"/{tools-bin,tools-src,theos}

# ── Step 1: Clone LLVM ────────────────────────────────────────────
LLVM_SRC="$PREFIX/tools-src/llvm-project"
LLVM_BUILD="$PREFIX/llvm-build"

if [ -d "$LLVM_SRC/.git" ]; then
    info "LLVM source already cloned, skipping..."
else
    info "Cloning L1ghtmann LLVM fork (this may take a while)..."
    git clone --depth 1 "$LLVM_REPO" "$LLVM_SRC"
fi

# Patch lld to allow iOS linking
info "Patching lld for iOS cross-compilation..."
LLD_FILE="$LLVM_SRC/lld/MachO/InputFiles.cpp"
if grep -q 'Swift LLVM fork downstream change start' "$LLD_FILE" 2>/dev/null; then
    sed -i '/Swift LLVM fork downstream change start/,/Swift LLVM fork downstream change end/c\  // Swift LLVM fork downstream change disabled for Windows cross-compilation' "$LLD_FILE"
    ok "lld patched for iOS support"
else
    info "lld already patched or different version"
fi

# ── Step 2: Build LLVM ────────────────────────────────────────────
if [ -f "$LLVM_BUILD/bin/clang.exe" ]; then
    info "LLVM already built, skipping..."
else
    info "Building LLVM (clang, lld, clang-tools-extra)..."
    info "This will take a LONG time (30-90 minutes depending on CPU)..."

    LLVM_SRC_WIN="$(cygpath -w "$LLVM_SRC/llvm")"
    LLVM_BUILD_WIN="$(cygpath -w "$LLVM_BUILD")"

    cat > "$PREFIX/tools-src/_build_llvm.bat" << BATEOF
@echo off
call "$VCVARS_WIN"
"$CMAKE_WIN" -G Ninja -S "$LLVM_SRC_WIN" -B "$LLVM_BUILD_WIN" ^
  -DCMAKE_MAKE_PROGRAM="$NINJA_WIN" ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_C_COMPILER=cl ^
  -DCMAKE_CXX_COMPILER=cl ^
  -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra;lld" ^
  -DLLVM_ENABLE_RUNTIMES="" ^
  -DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" ^
  -DLLVM_INCLUDE_TESTS=OFF ^
  -DLLVM_INCLUDE_EXAMPLES=OFF ^
  -DLLVM_INCLUDE_BENCHMARKS=OFF ^
  -DLLVM_ENABLE_ZLIB=OFF ^
  -DLLVM_ENABLE_ZSTD=OFF ^
  -DLLVM_ENABLE_PTHREADS=OFF
if %ERRORLEVEL% NEQ 0 exit /b 1
"$CMAKE_WIN" --build "$LLVM_BUILD_WIN" --config Release
BATEOF

    run_vs "$(cygpath -w "$PREFIX/tools-src/_build_llvm.bat")"
    [ -f "$LLVM_BUILD/bin/clang.exe" ] || error "LLVM build failed"
    ok "LLVM built successfully"
fi

# ── Step 3: Set up toolchain ──────────────────────────────────────
info "Setting up toolchain..."
TOOLCHAIN="$PREFIX/theos/toolchain/windows/iphone/bin"

# Clone Theos
if [ -d "$PREFIX/theos/.git" ]; then
    info "Theos already cloned"
else
    info "Cloning Theos..."
    git clone --recursive "$THEOS_REPO" "$PREFIX/theos"
fi

# Fix broken symlinks (Windows Git doesn't create real symlinks)
info "Fixing Windows symlinks in Theos..."
cd "$PREFIX/theos"
git submodule update --init --recursive 2>/dev/null || true

# Fix bin/ symlinks
for mapping in \
    "bin/logos.pl:vendor/logos/bin/logos.pl" \
    "bin/logify.pl:vendor/logos/bin/logify.pl" \
    "bin/dm.pl:vendor/dm.pl/dm.pl" \
    "bin/nic.pl:vendor/nic/bin/nic.pl" \
    "bin/nicify.pl:vendor/nic/bin/nicify.pl" \
    "bin/denicify.pl:vendor/nic/bin/denicify.pl" \
    "vendor/include/substrate.h:vendor/include/CydiaSubstrate.h"; do
    dst="${mapping%%:*}"
    src="${mapping##*:}"
    [ -f "$src" ] && cp "$src" "$dst" 2>/dev/null && echo "  Fixed: $dst"
done

# Copy Logos perl lib
mkdir -p bin/lib
cp -r vendor/logos/bin/lib/* bin/lib/ 2>/dev/null

# Set up toolchain binaries
mkdir -p "$TOOLCHAIN"
for tool in clang.exe clang++.exe lld.exe ld64.lld.exe dsymutil.exe; do
    cp "$LLVM_BUILD/bin/$tool" "$TOOLCHAIN/" 2>/dev/null
done

# Create symlink-equivalent tools
for mapping in \
    "llvm-strip.exe:strip.exe" \
    "llvm-ar.exe:ar.exe" \
    "llvm-nm.exe:nm.exe" \
    "llvm-lipo.exe:lipo.exe" \
    "llvm-otool.exe:otool.exe" \
    "llvm-libtool-darwin.exe:libtool.exe" \
    "llvm-install-name-tool.exe:install_name_tool.exe"; do
    src="${mapping%%:*}"
    dst="${mapping##*:}"
    cp "$LLVM_BUILD/bin/$src" "$TOOLCHAIN/$dst" 2>/dev/null
    cp "$LLVM_BUILD/bin/$src" "$TOOLCHAIN/$src" 2>/dev/null
done

# Copy clang builtin headers
CLANG_VER=$(ls "$LLVM_BUILD/lib/clang/")
mkdir -p "$TOOLCHAIN/../lib/clang/$CLANG_VER"
cp -r "$LLVM_BUILD/lib/clang/$CLANG_VER/include" "$TOOLCHAIN/../lib/clang/$CLANG_VER/"

ok "Toolchain configured"

# ── Step 4: Build ld.exe wrapper ──────────────────────────────────
info "Building ld.exe wrapper (lld -flavor ld64 for Mach-O)..."

# Rename real ld64.lld for wrapper use
mv "$TOOLCHAIN/ld64.lld.exe" "$TOOLCHAIN/ld64.lld.real.exe"

cat > "$PREFIX/tools-src/ld_wrapper.c" << 'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <process.h>

int main(int argc, char **argv) {
    char **new_argv = (char **)malloc(sizeof(char *) * (argc * 2 + 10));
    int n = 0;
    char path[4096];
    strncpy(path, argv[0], sizeof(path) - 1);
    path[sizeof(path) - 1] = 0;
    char *last_sep = strrchr(path, '\\');
    char *last_sep2 = strrchr(path, '/');
    if (last_sep2 > last_sep) last_sep = last_sep2;
    if (last_sep) strcpy(last_sep + 1, "ld64.lld.real.exe");
    else strcpy(path, "ld64.lld.real.exe");

    new_argv[n++] = path;
    new_argv[n++] = "-flavor";
    new_argv[n++] = "ld64";

    char *sdk_version = NULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-syslibroot") == 0 && i + 1 < argc) {
            const char *p = strstr(argv[i+1], "iPhoneOS");
            if (p) { p += 8; static char ver[32]; int j = 0;
                while (*p && *p != '.' && j < 30) ver[j++] = *p++;
                if (*p == '.') { ver[j++] = *p++; while (*p && *p != '.' && j < 30) ver[j++] = *p++; }
                ver[j] = 0; sdk_version = ver; }
        }
    }
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-iphoneos_version_min") == 0 && i + 1 < argc) {
            new_argv[n++] = "-platform_version"; new_argv[n++] = "ios";
            new_argv[n++] = argv[i + 1];
            new_argv[n++] = sdk_version ? sdk_version : argv[i + 1];
            i++;
        } else if (strcmp(argv[i], "-multiply_defined") == 0 && i + 1 < argc) {
            i++;
        } else { new_argv[n++] = argv[i]; }
    }
    new_argv[n] = NULL;
    return _spawnv(_P_WAIT, path, (const char *const *)new_argv);
}
CEOF

TOOLCHAIN_WIN="$(cygpath -w "$TOOLCHAIN")"
cat > "$PREFIX/tools-src/_build_ld_wrapper.bat" << BATEOF
@echo off
call "$VCVARS_WIN"
cl /nologo /O2 "$(cygpath -w "$PREFIX/tools-src/ld_wrapper.c")" /Fe:"$TOOLCHAIN_WIN\\ld64.lld.exe"
copy /Y "$TOOLCHAIN_WIN\\ld64.lld.exe" "$TOOLCHAIN_WIN\\ld.exe"
BATEOF

run_vs "$(cygpath -w "$PREFIX/tools-src/_build_ld_wrapper.bat")"
[ -f "$TOOLCHAIN/ld64.lld.exe" ] || error "ld wrapper build failed"
ok "ld.exe wrapper built"

# ── Step 5: Create CydiaSubstrate stub ────────────────────────────
info "Creating CydiaSubstrate stub dylib..."
cat > /tmp/substrate_stub.c << 'EOF'
void MSHookMessageEx(void *c, void *s, void *i, void **o) {}
void MSHookFunction(void *s, void *h, void **o) {}
void MSGetImageByName(const char *f) {}
void MSFindSymbol(void *i, const char *n) {}
EOF

export PATH="$TOOLCHAIN:$PATH"
export MSYS2_ARG_CONV_EXCL="-install_name;/Library"
SUBSTRATE_DIR="$PREFIX/theos/vendor/lib/CydiaSubstrate.framework"

clang -target arm64-apple-ios15.0 \
    -isysroot "$PREFIX/theos/sdks/iPhoneOS"*.sdk 2>/dev/null || true

SDK_PATH=$(ls -d "$PREFIX/theos/sdks/iPhoneOS"*.sdk 2>/dev/null | head -1)
if [ -n "$SDK_PATH" ]; then
    clang -target arm64-apple-ios15.0 -isysroot "$SDK_PATH" -dynamiclib \
        -install_name /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate \
        -o "$SUBSTRATE_DIR/CydiaSubstrate" /tmp/substrate_stub.c 2>/dev/null
    rm -f "$SUBSTRATE_DIR/CydiaSubstrate.tbd" "$PREFIX/theos/vendor/lib/libsubstrate.tbd" 2>/dev/null
    ok "Substrate stub created"
fi

# ── Step 6: Install tools-bin ─────────────────────────────────────
info "Setting up tools-bin..."
TOOLS="$PREFIX/tools-bin"

# MSYS2 make
info "Downloading MSYS2 make..."
MAKE_PKG=$(curl -sL "$MSYS2_MAKE_URL" | grep -o 'make-[0-9.]*-[0-9]*-x86_64.pkg.tar.zst' | sort -V | tail -1)
if [ -n "$MAKE_PKG" ]; then
    curl -sL "${MSYS2_MAKE_URL}${MAKE_PKG}" -o /tmp/make.pkg.tar.zst
    "$PYTHON" -c "
import zstandard, tarfile, io, sys
with open('/tmp/make.pkg.tar.zst','rb') as f:
    data = zstandard.ZstdDecompressor().decompress(f.read(), max_output_size=50*1024*1024)
    t = tarfile.open(fileobj=io.BytesIO(data))
    for m in t.getmembers():
        if m.name.endswith('bin/make.exe'):
            t.extract(m, '/tmp/msys2make')
            print('Extracted:', m.name)
" 2>/dev/null
    cp /tmp/msys2make/usr/bin/make.exe "$TOOLS/make.exe" 2>/dev/null
    ok "MSYS2 make installed"
else
    warn "Could not download MSYS2 make. You may need to install it manually."
fi

# Strawberry Perl
info "Downloading Strawberry Perl..."
PERL_URL=$(curl -sL "https://api.github.com/repos/StrawberryPerl/Perl-Dist-Strawberry/releases/latest" | grep "browser_download_url.*portable.*zip" | head -1 | grep -o 'https://[^"]*')
if [ -n "$PERL_URL" ]; then
    curl -L "$PERL_URL" -o /tmp/strawberry.zip
    mkdir -p "$PREFIX/strawberry-perl"
    unzip -qo /tmp/strawberry.zip -d "$PREFIX/strawberry-perl"
    cat > "$TOOLS/perl" << PEOF
#!/bin/sh
exec "$PREFIX/strawberry-perl/perl/bin/perl.exe" "\$@"
PEOF
    chmod +x "$TOOLS/perl"
    ok "Strawberry Perl installed"
else
    warn "Could not download Strawberry Perl. Logos (.x files) won't work without it."
fi

# Stubs
cat > "$TOOLS/fakeroot" << 'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
    case "$1" in
        -i|-s|-b) shift; shift ;;
        --) shift; break ;;
        -*) shift ;;
        *) break ;;
    esac
done
exec "$@"
EOF

cat > "$TOOLS/dpkg-deb" << 'DEBEOF'
#!/bin/sh
set -e
while [ $# -gt 0 ]; do
    case "$1" in
        -b|--build) shift; break ;;
        -Z*|-S*) shift ;;
        --) shift ;;
        -*) shift ;;
        *) break ;;
    esac
done
SRCDIR="$1"; OUTPUT="$2"
if [ -n "$SRCDIR" ] && [ -n "$OUTPUT" ]; then
    TMPDIR=$(mktemp -d); trap "rm -rf '$TMPDIR'" EXIT
    echo "2.0" > "$TMPDIR/debian-binary"
    [ -d "$SRCDIR/DEBIAN" ] && (cd "$SRCDIR/DEBIAN" && tar czf "$TMPDIR/control.tar.gz" ./*)
    (cd "$SRCDIR" && tar czf "$TMPDIR/data.tar.gz" --exclude='./DEBIAN' .)
    (cd "$TMPDIR" && ar rcs "$OLDPWD/$OUTPUT" debian-binary control.tar.gz data.tar.gz 2>/dev/null) || \
    (cd "$TMPDIR" && cat debian-binary control.tar.gz data.tar.gz > "$OLDPWD/$OUTPUT")
    echo "dpkg-deb: building package from '$SRCDIR' into '$OUTPUT'"
else
    echo "Usage: dpkg-deb [-Zgzip] -b <directory> <output.deb>" >&2; exit 1
fi
DEBEOF

cat > "$TOOLS/rsync" << 'EOF'
#!/bin/sh
ARGS=()
for arg in "$@"; do case "$arg" in -*) ;; *) ARGS+=("$arg") ;; esac; done
if [ ${#ARGS[@]} -lt 2 ]; then exit 1; fi
DEST="${ARGS[${#ARGS[@]}-1]}"; unset 'ARGS[${#ARGS[@]}-1]'
mkdir -p "$DEST" 2>/dev/null
for src in "${ARGS[@]}"; do cp -rf "$src" "$DEST" 2>/dev/null; done
EOF

chmod +x "$TOOLS/fakeroot" "$TOOLS/dpkg-deb" "$TOOLS/rsync"
ok "Tool stubs created"

# ── Step 7: Install iOS SDK ───────────────────────────────────────
info "Installing iOS SDK..."
export THEOS="$PREFIX/theos"
if ls "$THEOS/sdks/"iPhoneOS*.sdk/SDKSettings.plist >/dev/null 2>&1; then
    ok "iOS SDK already installed"
else
    bash "$THEOS/bin/install-sdk" latest 2>&1 || warn "SDK install had errors (may still work)"
fi

# ── Step 8: Patch Theos makefiles ─────────────────────────────────
info "Patching Theos for Windows..."

# Patch common.mk platform detection
COMMON_MK="$THEOS/makefiles/common.mk"
if ! grep -q 'MINGW%' "$COMMON_MK" 2>/dev/null; then
    sed -i '/^export _THEOS_PLATFORM = \$(uname_s)/i\
ifneq ($(filter MINGW% MSYS% CYGWIN%,$(uname_s)),)\
export _THEOS_PLATFORM := Windows\
export _THEOS_OS := Windows\
else' "$COMMON_MK"
    sed -i '/^export _THEOS_OS = /a\
endif' "$COMMON_MK"
fi

# Patch darwin_tail.mk for ld64.lld
DARWIN_TAIL="$THEOS/makefiles/targets/_common/darwin_tail.mk"
if ! grep -q 'ld64.lld' "$DARWIN_TAIL" 2>/dev/null; then
    sed -i 's|^_THEOS_TARGET_LDFLAGS += -fuse-ld=\$(SDKBINPATH)/\$(_THEOS_TARGET_SDK_BIN_PREFIX)ld$|& \
else ifneq ($(wildcard $(SDKBINPATH)/ld64.lld.exe),)\
_THEOS_TARGET_LDFLAGS += -B$(SDKBINPATH)|' "$DARWIN_TAIL"
fi

ok "Theos patched"

# ── Done ──────────────────────────────────────────────────────────
PREFIX_WIN="$(cygpath -w "$PREFIX" 2>/dev/null || echo "$PREFIX")"

echo ""
echo "============================================"
ok "Installation complete!"
echo "============================================"
echo ""
echo "Add to your ~/.bashrc:"
echo ""
echo "  export THEOS=\"$PREFIX/theos\""
echo "  export PATH=\"$PREFIX/tools-bin:\$THEOS/toolchain/windows/iphone/bin:\$PATH\""
echo "  export MSYS2_ARG_CONV_EXCL=\"-install_name;-dylib_install_name;/Library\""
echo ""
echo "Then in your Theos Makefile:"
echo ""
echo "  ARCHS = arm64"
echo "  TARGET = iphone:16.5:15.0"
echo "  TARGET_CODESIGN ="
echo "  _THEOS_PLATFORM_DPKG_DEB = dpkg-deb"
echo ""
echo "Build: make package"
echo ""
