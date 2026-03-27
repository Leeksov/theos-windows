#!/usr/bin/env bash
# Theos for Windows - One-Click Installer
# Requires: Git Bash (Git for Windows)
# Usage: bash install.sh [install-path]

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()  { printf "${BLUE}==>${NC} %s\n" "$1"; }
ok()    { printf "${GREEN}==>${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}==>${NC} %s\n" "$1"; }
error() { printf "${RED}==>${NC} %s\n" "$1"; exit 1; }

REPO="Leeksov/theos-windows"
TOOLCHAIN_ASSET="theos-windows-toolchain.tar.gz"
PREFIX="${1:-$HOME/theos-windows}"
PREFIX="${PREFIX//\\//}"

echo ""
printf "${BOLD}  Theos for Windows — Installer${NC}\n"
printf "  Build iOS tweaks natively on Windows\n"
echo ""

# ── Checks ─────────────────────────────────────────────────────────
info "Checking prerequisites..."
command -v git  >/dev/null 2>&1 || error "Git not found. Install: https://git-scm.com/download/win"
command -v curl >/dev/null 2>&1 || error "curl not found."
command -v tar  >/dev/null 2>&1 || error "tar not found."

# Find Python for Strawberry Perl extraction
PYTHON=""
for p in python3 python; do command -v "$p" >/dev/null 2>&1 && PYTHON="$p" && break; done
if [ -z "$PYTHON" ]; then
    for p in "/c/Users/$USER/AppData/Local/Programs/Python/"*/python.exe; do
        [ -x "$p" ] && PYTHON="$p" && break
    done
fi

ok "Prerequisites OK"
info "Install path: $PREFIX"

mkdir -p "$PREFIX"

# ── Step 1: Download pre-built toolchain ───────────────────────────
TOOLCHAIN_URL="https://github.com/$REPO/releases/latest/download/$TOOLCHAIN_ASSET"

if [ -f "$PREFIX/toolchain/windows/iphone/bin/clang.exe" ]; then
    info "Toolchain already installed, skipping download..."
else
    info "Downloading pre-built toolchain (~150 MB)..."
    curl -L "$TOOLCHAIN_URL" -o "$PREFIX/$TOOLCHAIN_ASSET" --progress-bar
    [ -f "$PREFIX/$TOOLCHAIN_ASSET" ] || error "Download failed"

    info "Extracting toolchain..."
    tar xzf "$PREFIX/$TOOLCHAIN_ASSET" -C "$PREFIX"
    rm -f "$PREFIX/$TOOLCHAIN_ASSET"
    ok "Toolchain installed"
fi

# ── Step 2: Clone Theos ────────────────────────────────────────────
THEOS="$PREFIX/theos"

if [ -d "$THEOS/.git" ]; then
    info "Theos already cloned"
else
    info "Cloning Theos..."
    git clone --recursive https://github.com/theos/theos.git "$THEOS"
fi

# Ensure submodules
info "Updating submodules..."
(cd "$THEOS" && git submodule update --init --recursive 2>/dev/null) || true

# ── Step 3: Fix Windows symlinks ──────────────────────────────────
info "Fixing symlinks (Windows Git doesn't create real symlinks)..."
cd "$THEOS"

for mapping in \
    "bin/logos.pl:vendor/logos/bin/logos.pl" \
    "bin/logify.pl:vendor/logos/bin/logify.pl" \
    "bin/dm.pl:vendor/dm.pl/dm.pl" \
    "bin/nic.pl:vendor/nic/bin/nic.pl" \
    "bin/nicify.pl:vendor/nic/bin/nicify.pl" \
    "bin/denicify.pl:vendor/nic/bin/denicify.pl" \
    "vendor/include/substrate.h:vendor/include/CydiaSubstrate.h" \
    "vendor/include/IOKit/IOKit.h:vendor/include/IOKit/IOKitLib.h"; do
    dst="${mapping%%:*}"
    src="${mapping##*:}"
    if [ -f "$src" ]; then
        # Only fix if target is a text pointer (broken symlink)
        if [ -f "$dst" ] && [ "$(wc -l < "$dst" 2>/dev/null)" -le 2 ]; then
            content=$(cat "$dst" 2>/dev/null)
            if echo "$content" | grep -q '^\.\./\|^[A-Za-z].*\.[A-Za-z]' 2>/dev/null; then
                cp "$src" "$dst"
            fi
        elif [ ! -f "$dst" ]; then
            mkdir -p "$(dirname "$dst")"
            cp "$src" "$dst"
        fi
    fi
done

# Copy Logos perl modules
mkdir -p bin/lib
cp -r vendor/logos/bin/lib/* bin/lib/ 2>/dev/null || true

ok "Symlinks fixed"

# ── Step 4: Install pre-built components ──────────────────────────
info "Setting up toolchain..."

# Copy toolchain into theos
TCDST="$THEOS/toolchain/windows/iphone"
mkdir -p "$TCDST/bin" "$TCDST/lib"
cp -r "$PREFIX/toolchain/windows/iphone/bin/"* "$TCDST/bin/" 2>/dev/null
cp -r "$PREFIX/toolchain/windows/iphone/lib/"* "$TCDST/lib/" 2>/dev/null

# Install CydiaSubstrate stub
SUBSTRATE_DIR="$THEOS/vendor/lib/CydiaSubstrate.framework"
if [ -f "$PREFIX/stubs/CydiaSubstrate.framework/CydiaSubstrate" ]; then
    cp "$PREFIX/stubs/CydiaSubstrate.framework/CydiaSubstrate" "$SUBSTRATE_DIR/CydiaSubstrate"
    rm -f "$SUBSTRATE_DIR/CydiaSubstrate.tbd" "$THEOS/vendor/lib/libsubstrate.tbd" 2>/dev/null
fi
if [ -f "$PREFIX/stubs/CydiaSubstrate.h" ]; then
    cp "$PREFIX/stubs/CydiaSubstrate.h" "$THEOS/vendor/include/CydiaSubstrate.h"
fi

ok "Toolchain ready"

# ── Step 5: Install iOS SDK ───────────────────────────────────────
if ls "$THEOS/sdks/"iPhoneOS*.sdk/SDKSettings.plist >/dev/null 2>&1; then
    ok "iOS SDK already installed"
else
    info "Downloading iOS SDK..."
    export THEOS
    bash "$THEOS/bin/install-sdk" latest 2>&1 || warn "SDK install had warnings (usually OK)"
    ls "$THEOS/sdks/"iPhoneOS*.sdk/SDKSettings.plist >/dev/null 2>&1 && ok "iOS SDK installed" || warn "SDK may need manual install"
fi

# ── Step 6: Install Strawberry Perl ───────────────────────────────
PERL_DIR="$PREFIX/strawberry-perl"
TOOLS="$PREFIX/tools-bin"

if [ -f "$PERL_DIR/perl/bin/perl.exe" ]; then
    info "Strawberry Perl already installed"
else
    info "Downloading Strawberry Perl (~290 MB, needed for Logos .x files)..."
    PERL_URL=$(curl -sL "https://api.github.com/repos/StrawberryPerl/Perl-Dist-Strawberry/releases/latest" 2>/dev/null | grep "browser_download_url.*portable.*zip" | head -1 | grep -o 'https://[^"]*')
    if [ -n "$PERL_URL" ]; then
        curl -L "$PERL_URL" -o /tmp/strawberry-perl.zip --progress-bar
        mkdir -p "$PERL_DIR"
        unzip -qo /tmp/strawberry-perl.zip -d "$PERL_DIR"
        rm -f /tmp/strawberry-perl.zip
        ok "Strawberry Perl installed"
    else
        warn "Could not download Perl. Logos (.x) files won't work. Install manually from https://strawberryperl.com"
    fi
fi

# Update perl wrapper
if [ -f "$PERL_DIR/perl/bin/perl.exe" ]; then
    cat > "$TOOLS/perl" << PEOF
#!/bin/sh
exec "$PERL_DIR/perl/bin/perl.exe" "\$@"
PEOF
    chmod +x "$TOOLS/perl"
fi

# ── Step 7: Patch Theos makefiles ─────────────────────────────────
info "Patching Theos for Windows..."

# 7a. Platform detection — recognize MINGW/MSYS as Windows
COMMON_MK="$THEOS/makefiles/common.mk"
if ! grep -q 'MINGW%' "$COMMON_MK" 2>/dev/null; then
    # Insert Windows detection before the default platform assignment
    sed -i '/^export _THEOS_PLATFORM = \$(uname_s)$/i\
ifneq ($(filter MINGW% MSYS% CYGWIN%,$(uname_s)),)\
export _THEOS_PLATFORM := Windows\
export _THEOS_OS := Windows\
else' "$COMMON_MK"
    # Close the else/endif after _THEOS_OS line
    sed -i '/^export _THEOS_OS = \$(if/a\
endif' "$COMMON_MK"
    ok "Patched common.mk"
else
    info "common.mk already patched"
fi

# 7b. Linker — use ld64.lld wrapper via -B flag
DARWIN_TAIL="$THEOS/makefiles/targets/_common/darwin_tail.mk"
if ! grep -q 'ld64.lld' "$DARWIN_TAIL" 2>/dev/null; then
    # After the existing -fuse-ld line, add Windows fallback
    sed -i '/^_THEOS_TARGET_LDFLAGS += -fuse-ld=\$(SDKBINPATH)\/\$(_THEOS_TARGET_SDK_BIN_PREFIX)ld$/a\
else ifneq ($(wildcard $(SDKBINPATH)/ld64.lld.exe),)\
_THEOS_TARGET_LDFLAGS += -B$(SDKBINPATH)' "$DARWIN_TAIL"
    ok "Patched darwin_tail.mk"
else
    info "darwin_tail.mk already patched"
fi

ok "Theos patched for Windows"

# ── Step 8: Shell profile ─────────────────────────────────────────
info "Setting up environment..."

PROFILE="$HOME/.bashrc"
MARKER="# theos-windows"

if ! grep -q "$MARKER" "$PROFILE" 2>/dev/null; then
    cat >> "$PROFILE" << ENVEOF

$MARKER
export THEOS="$PREFIX/theos"
export PATH="$PREFIX/tools-bin:\$THEOS/toolchain/windows/iphone/bin:\$PATH"
export MSYS2_ARG_CONV_EXCL="-install_name;-dylib_install_name;/Library"
ENVEOF
    ok "Added to ~/.bashrc"
else
    info "~/.bashrc already configured"
fi

# ── Done ──────────────────────────────────────────────────────────
echo ""
echo "============================================"
ok "Installation complete!"
echo "============================================"
echo ""
echo "  Restart your terminal, then:"
echo ""
echo "  1. Create a project:  \$THEOS/bin/nic.pl"
echo ""
echo "  2. Add to your Makefile:"
echo "     ARCHS = arm64"
echo "     TARGET = iphone:16.5:15.0"
echo "     TARGET_CODESIGN ="
echo "     _THEOS_PLATFORM_DPKG_DEB = dpkg-deb"
echo ""
echo "  3. Build:  make package"
echo ""
echo "  .deb output: ./packages/"
echo ""
