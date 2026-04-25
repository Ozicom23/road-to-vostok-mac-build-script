#!/bin/bash

# Exit on error
set -e

# Configuration
PCK_FILE="RTV.pck"
GDRE_DIR="gdre_tools"
RECOVER_DIR="RTV_recovered"
REPO="GDRETools/gdsdecomp"

echo "Starting Godot Mac Build..."

# Check if the PCK file exists
if [ ! -f "$PCK_FILE" ]; then
    echo "Error: Could not find '$PCK_FILE' in the current directory."
    echo "Make sure you are running this script in the game's main directory."
    exit 1
fi

# Download GDRE Tools if not already present
if [ ! -d "$GDRE_DIR" ]; then
    echo "Downloading GDRE Tools..."
    mkdir -p "$GDRE_DIR"
    cd "$GDRE_DIR"

    # Fetch the latest release API and extract the macOS browser_download_url
    DOWNLOAD_URL=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" | grep -o '"browser_download_url": *"[^"]*macos\.zip"' | cut -d '"' -f 4)

    if [ -z "$DOWNLOAD_URL" ]; then
        echo "Error: Could not find the latest macOS release URL."
        exit 1
    fi

    curl -sL -o gdre.zip "$DOWNLOAD_URL"
    unzip -q -o gdre.zip

    # Make the binary executable
    chmod +x "Godot RE Tools.app/Contents/MacOS/Godot RE Tools"
    cd ..
fi

# Set the executable path
GDRE_EXE="$GDRE_DIR/Godot RE Tools.app/Contents/MacOS/Godot RE Tools"

if [ ! -f "$GDRE_EXE" ]; then
    echo "Error: Could not find the gdre executable inside $GDRE_DIR."
    exit 1
fi

mkdir -p "$RECOVER_DIR"
cd "$RECOVER_DIR"

# Create symlink to PCK if it doesn't exist
if [ ! -L "$PCK_FILE" ]; then
    ln -s "../$PCK_FILE" .
fi

# Run the recovery tool
echo "Recovering project... (takes a few mins)"

# Run headless recovery
"../$GDRE_EXE" --headless --recover="$PCK_FILE"

echo "Extraction complete."

cd ..

# Setup Godot Engine
GODOT_DIR="godot_bin"

DETECTED_VERSION=""
if [ -f "$RECOVER_DIR/RTV/gdre_export.log" ]; then
    DETECTED_VERSION=$(grep "Detected Engine Version:" "$RECOVER_DIR/RTV/gdre_export.log" | awk '{print $4}')
fi

API_URL="https://api.github.com/repos/godotengine/godot/releases/latest"
if [ -n "$DETECTED_VERSION" ]; then
    echo "Target Godot version: $DETECTED_VERSION"
    API_URL="https://api.github.com/repos/godotengine/godot/releases/tags/${DETECTED_VERSION}-stable"
fi

if [ ! -d "$GODOT_DIR" ]; then
    echo "Downloading Godot engine..."
    mkdir -p "$GODOT_DIR"
    cd "$GODOT_DIR"

    GODOT_URL=$(curl -sL "$API_URL" | grep -o '"browser_download_url": *"[^"]*macos\.universal\.zip"' | grep -v 'mono' | cut -d '"' -f 4 | head -n 1)

    # Fallback to latest if download URL is empty (release doesn't exist)
    if [ -z "$GODOT_URL" ] && [ -n "$DETECTED_VERSION" ]; then
        GODOT_URL=$(curl -sL "https://api.github.com/repos/godotengine/godot/releases/latest" | grep -o '"browser_download_url": *"[^"]*macos\.universal\.zip"' | grep -v 'mono' | cut -d '"' -f 4 | head -n 1)
    fi

    if [ -z "$GODOT_URL" ]; then
        echo "Error: Could not find Godot macOS release."
        exit 1
    fi

    curl -sL -o godot.zip "$GODOT_URL"
    unzip -q -o godot.zip
    chmod +x "Godot.app/Contents/MacOS/Godot"
    cd ..
fi

# Download Godot Templates
if [ ! -f "$GODOT_DIR/templates/macos.zip" ]; then
    echo "Downloading templates (~1GB)..."
    cd "$GODOT_DIR"

    GODOT_TPZ_URL=$(curl -sL "$API_URL" | grep -o '"browser_download_url": *"[^"]*export_templates\.tpz"' | grep -v 'mono' | cut -d '"' -f 4 | head -n 1)

    if [ -z "$GODOT_TPZ_URL" ] && [ -n "$DETECTED_VERSION" ]; then
        GODOT_TPZ_URL=$(curl -sL "https://api.github.com/repos/godotengine/godot/releases/latest" | grep -o '"browser_download_url": *"[^"]*export_templates\.tpz"' | grep -v 'mono' | cut -d '"' -f 4 | head -n 1)
    fi

    if [ -n "$GODOT_TPZ_URL" ]; then
        curl -sL -o godot_templates.tpz "$GODOT_TPZ_URL"
        unzip -q -o godot_templates.tpz templates/macos.zip
        rm godot_templates.tpz
    else
        echo "Error: Could not find Godot export templates release."
        exit 1
    fi
    cd ..
fi

# Set Godot executable path
GODOT_EXE="$(pwd)/$GODOT_DIR/Godot.app/Contents/MacOS/Godot"

if [ ! -f "$GODOT_EXE" ]; then
    echo "Error: Could not find the Godot executable inside $GODOT_DIR."
    exit 1
fi

# Setup Export Presets
cd "$RECOVER_DIR/RTV"

# We overwrite the export_presets.cfg so it strictly targets macOS
cat << 'EOF' > export_presets.cfg
[preset.0]

name="macOS"
platform="macOS"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="../../mac_build/RoadToVostok.app"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.0.options]

custom_template/debug=""
custom_template/release="../../godot_bin/templates/macos.zip"
application/bundle_identifier="com.roadtovostok"
architecture/x86_64=false
architecture/arm64=true
codesign/enable=false
notarization/enable=false
texture_format/bptc=true
texture_format/s3tc=true
texture_format/etc=false
texture_format/etc2=true
EOF

echo >> project.godot
echo "[rendering]" >> project.godot
echo "textures/vram_compression/import_etc2_astc=true" >> project.godot

# Export Native Build
echo "Exporting macOS app... (compiling textures takes a while)"
mkdir -p "../../mac_build"

"$GODOT_EXE" --headless --export-release "macOS" "../../mac_build/RoadToVostok.app"

echo "Build complete! App is in mac_build"
