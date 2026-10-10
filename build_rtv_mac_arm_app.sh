#!/bin/bash

# Exit on error
set -e

# Configuration
PCK_FILE="RTV.pck"
GDRE_DIR="gdre_tools"
RECOVER_DIR="RTV_recovered"
REPO="GDRETools/gdsdecomp"
STEAM_APP_ID="1963610"

usage() {
    echo "Usage: bash $(basename "$0") [--steam-user <name>]"
    echo
    echo "Builds a native macOS (Apple Silicon) app from the Road to Vostok game files."
    echo "Run it in a folder that contains RTV.pck, or let it fetch the game files:"
    echo
    echo "  --steam-user <name>   Download (or update) the game files into this folder with SteamCMD."
    echo "                        Needs 'brew install steamcmd' and a Steam account that owns the game."
    echo "  -h, --help            Show this help."
}

STEAM_USER=""
while [ $# -gt 0 ]; do
    case "$1" in
        --steam-user)
            if [ -z "$2" ]; then
                echo "Error: --steam-user needs your Steam username."
                exit 1
            fi
            STEAM_USER="$2"
            shift 2
            ;;
        --steam-user=*)
            STEAM_USER="${1#*=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'"
            echo
            usage
            exit 1
            ;;
    esac
done

echo "Starting Godot Mac Build..."

# Download or update the game files with SteamCMD
if [ -n "$STEAM_USER" ]; then
    if ! command -v steamcmd >/dev/null 2>&1; then
        echo "Error: steamcmd is not installed. Install it with: brew install steamcmd"
        exit 1
    fi

    echo "Fetching game files with SteamCMD into $(pwd) (~6GB on first download)..."
    echo "SteamCMD will ask for your Steam password and Steam Guard code."

    # force_install_dir must come before login, or SteamCMD ignores it.
    # SteamCMD's exit code is unreliable, so the file check below decides whether it worked.
    steamcmd +force_install_dir "$(pwd)" +@sSteamCmdForcePlatformType windows +login "$STEAM_USER" +app_update "$STEAM_APP_ID" +quit || true

    if [ ! -f "$PCK_FILE" ]; then
        echo "Error: SteamCMD finished but '$PCK_FILE' is not here. Check the SteamCMD output above."
        exit 1
    fi
fi

# Check if the PCK file exists
if [ ! -f "$PCK_FILE" ]; then
    echo "Error: Could not find '$PCK_FILE' in the current directory."
    echo "Either copy or move your RTV.pck into this folder, or let the script download it:"
    echo "  bash $(basename "$0") --steam-user <your_steam_username>"
    exit 1
fi

# Set the executable path
GDRE_EXE="$GDRE_DIR/Godot RE Tools.app/Contents/MacOS/Godot RE Tools"

# Download GDRE Tools if not already present (checks the binary, so an empty or partial folder is re-downloaded)
if [ ! -f "$GDRE_EXE" ]; then
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

# Set Godot executable path
GODOT_EXE="$(pwd)/$GODOT_DIR/Godot.app/Contents/MacOS/Godot"

# Download Godot if not already present (checks the binary, so an empty or partial folder is re-downloaded)
if [ ! -f "$GODOT_EXE" ]; then
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

# Apply macOS compatibility patches
echo "Applying macOS patches..."

# Patch 1: Remap item_transfer Ctrl+click -> Cmd+click (macOS intercepts Ctrl+click as right-click)
python3 - <<'PYEOF'
import re
with open('project.godot', 'r') as f:
    content = f.read()
patched, count = re.subn(
    r'(item_transfer=\{.*?"physical_keycode":)4194326',
    r'\g<1>4194327',
    content,
    flags=re.DOTALL
)
if count == 0:
    print("  [SKIP] item_transfer keycode not found (already patched?)")
else:
    with open('project.godot', 'w') as f:
        f.write(patched)
    print("  [OK] item_transfer: Ctrl (4194326) -> Cmd (4194327)")
PYEOF

# Leftover from older versions of this script (software cursor patch, since removed)
rm -f Scripts/MacCursor.gd

# Patch 2: Fixed resolution presets + resolution control in fullscreen.
# window.set_size() has no effect in macOS fullscreen, so in fullscreen the chosen preset is
# applied as the 3D render scale instead. The game's own Rendering Low/Native setting writes
# the same viewport property (World.gd), so it is patched to multiply by our factor.
# The decompiled scripts are tab-indented. Every replacement must match, or the build stops
# rather than exporting a broken settings menu.
python3 - <<'PYEOF'
import re, sys

SIZES = [(3840, 2160), (2560, 1440), (1920, 1080), (1600, 900), (1280, 720), (1024, 576)]

def patch(path, marker, steps, append=''):
    with open(path) as f:
        content = f.read()
    if marker in content:
        print(f"  [SKIP] {path}: already patched")
        return
    for name, pattern, repl, expected in steps:
        content, n = re.subn(pattern, repl, content, flags=re.M | re.S)
        if n != expected:
            sys.exit(f"  [FAIL] {path}: '{name}' matched {n} time(s), expected {expected}. "
                     f"The game scripts changed; this patch needs updating.")
        print(f"  [OK] {path}: {name}")
    content += append
    with open(path, 'w') as f:
        f.write(content)

SIZES_HANDLER = (
    "func _on_sizes_item_selected(index: int) -> void :\n"
    "\tvar window = get_window()\n"
    "\tvar option = clampi(sizes.get_item_id(index), 0, MAC_RES_SIZES.size() - 1)\n"
    "\tpreferences.windowSize = option\n"
    "\n"
    "\tif preferences.displayMode == 1:\n"
    "\t\tMacApplyResolution()\n"
    "\telse:\n"
    "\t\twindow.set_mode(Window.MODE_WINDOWED)\n"
    "\t\twindow.set_size(MAC_RES_SIZES[option])\n"
    "\t\tCenterWindow()\n"
    "\n"
    "\tpreferences.Save()\n"
    "\tPlayClick()\n"
)

HELPER = (
    "\n"
    "\n"
    "# macOS port: resolution presets. In fullscreen the preset height becomes the 3D render scale.\n"
    "const MAC_RES_SIZES = [" + ", ".join(f"Vector2i({w}, {h})" for w, h in SIZES) + "]\n"
    "\n"
    "func MacApplyResolution() -> void :\n"
    "\tvar root = get_tree().get_root()\n"
    "\tif not root.size_changed.is_connected(MacApplyResolution):\n"
    "\t\troot.size_changed.connect(MacApplyResolution)\n"
    "\n"
    "\tvar resScale = 1.0\n"
    "\tif preferences.displayMode == 1:\n"
    "\t\tvar option = clampi(preferences.windowSize, 0, MAC_RES_SIZES.size() - 1)\n"
    "\t\tresScale = clampf(float(MAC_RES_SIZES[option].y) / maxf(1.0, float(root.size.y)), 0.1, 1.0)\n"
    "\n"
    "\troot.set_meta(\"mac_res_scale\", resScale)\n"
    "\tvar renderScale = 0.9 if preferences.rendering == 1 else 1.0\n"
    "\tRenderingServer.viewport_set_scaling_3d_scale(root.get_viewport_rid(), resScale * renderScale)\n"
)

PERCENT_BLOCK = (
    r'^(\t+)if preferences\.windowSize == 0:\n'
    r'\1\twindow\.set_size\(DisplayServer\.screen_get_size\(\)\)\n'
    r'\1elif preferences\.windowSize == 1:\n'
    r'\1\twindow\.set_size\(DisplayServer\.screen_get_size\(\) / 1\.1\)\n'
    r'\1elif preferences\.windowSize == 2:\n'
    r'\1\twindow\.set_size\(DisplayServer\.screen_get_size\(\) / 1\.25\)\n'
    r'\1elif preferences\.windowSize == 3:\n'
    r'\1\twindow\.set_size\(DisplayServer\.screen_get_size\(\) / 1\.5\)\n'
    r'\n?\1CenterWindow\(\)\n'
)

patch('Scripts/Settings.gd', 'MacApplyResolution', [
    ("resolution presets",
     r'var windowSizes: Dictionary = \{[^}]*\}',
     'var windowSizes: Dictionary = {\n' + ',\n'.join(f'"{w} x {h}": int({i})' for i, (w, h) in enumerate(SIZES)) + '}',
     1),
    ("sizes dropdown enabled in fullscreen",
     r'^(\t+)sizes\.disabled = true\n',
     r'\1sizes.disabled = false\n',
     2),
    ("apply resolution on load",
     r'^(\t+)windowed\.set_pressed_no_signal\(false\)\n\1window\.set_mode\(Window\.MODE_FULLSCREEN\)\n',
     r'\1windowed.set_pressed_no_signal(false)\n\1window.set_mode(Window.MODE_FULLSCREEN)\n\1MacApplyResolution()\n',
     1),
    ("apply resolution when display mode changes",
     r'^(\t+)preferences\.displayMode = ([12])\n',
     r'\1preferences.displayMode = \2\n\1MacApplyResolution()\n',
     2),
    ("sizes handler: fullscreen -> render scale, windowed -> window size",
     r'^func _on_sizes_item_selected\(index: int\) -> void :\n.*?\n\tPlayClick\(\)\n',
     SIZES_HANDLER,
     1),
    ("windowed sizes: screen percentages -> presets",
     PERCENT_BLOCK,
     r'\1window.call_deferred("set_size", MAC_RES_SIZES[clampi(preferences.windowSize, 0, MAC_RES_SIZES.size() - 1)])\n'
     r'\1call_deferred("CenterWindow")\n',
     3),
], append=HELPER)

patch('Scripts/World.gd', 'mac_res_scale', [
    ("Rendering Low keeps the resolution scale",
     r'viewport_set_scaling_3d_scale\(currentRID, 0\.9\)',
     r'viewport_set_scaling_3d_scale(currentRID, 0.9 * get_tree().get_root().get_meta("mac_res_scale", 1.0))',
     1),
    ("Rendering Native keeps the resolution scale",
     r'viewport_set_scaling_3d_scale\(currentRID, 1\.0\)',
     r'viewport_set_scaling_3d_scale(currentRID, 1.0 * get_tree().get_root().get_meta("mac_res_scale", 1.0))',
     1),
])

patch('Scripts/Preferences.gd', '@export var windowSize = 2', [
    ("default resolution 1920 x 1080",
     r'^(@export var windowSize = )0$',
     r'\g<1>2',
     1),
])
PYEOF

# The patched scripts must still parse. Autoload lookups fail under --check-only, so only parse errors count.
for script in Scripts/Settings.gd Scripts/World.gd Scripts/Preferences.gd; do
    if "$GODOT_EXE" --headless --path . --check-only --script "res://$script" 2>&1 | grep -q "Parse Error"; then
        echo "Error: $script does not parse after patching. Build stopped."
        exit 1
    fi
done
echo "  [OK] patched scripts parse"

echo "Patches applied."

# Export Native Build
echo "Exporting macOS app... (compiling textures takes a while)"
mkdir -p "../../mac_build"

"$GODOT_EXE" --headless --export-release "macOS" "../../mac_build/RoadToVostok.app"

APP_PATH="$(cd ../../mac_build && pwd)/RoadToVostok.app"
APP_SIZE=$(du -sh "$APP_PATH" | cut -f1)
GAME_VERSION=$(grep -o '^config/version="[^"]*"' project.godot | cut -d '"' -f 2)
GODOT_VERSION=$("$GODOT_EXE" --version 2>/dev/null | tail -n 1 | cut -d. -f1-3)

# Colors only when printing to a terminal
if [ -t 1 ]; then
    GREEN=$'\033[1;32m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    GREEN=""; DIM=""; RESET=""
fi

echo
echo "${GREEN}✔ Build successful${RESET}"
echo "  App:    $APP_PATH"
echo "  Size:   $APP_SIZE"
echo "  Game:   ${GAME_VERSION:-unknown}"
echo "  Godot:  $GODOT_VERSION"
echo "  Run:    open \"$APP_PATH\""
echo "${DIM}  The \"leaked at exit\" lines above come from Godot's editor shutdown and don't affect the app.${RESET}"
