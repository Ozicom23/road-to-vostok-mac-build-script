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

# Patch 2: Software cursor — bypasses macOS pointer acceleration when UI is open
cat > Scripts/MacCursor.gd << 'GDEOF'
extends CanvasLayer

var _sprite: Sprite2D

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sprite = Sprite2D.new()
	_sprite.texture = _build_arrow()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = false
	_sprite.scale = Vector2(2.0, 2.0)
	add_child(_sprite)

func _process(_delta: float) -> void:
	var active := Input.get_mouse_mode() == Input.MOUSE_MODE_CONFINED_HIDDEN
	_sprite.visible = active
	if active:
		_sprite.position = get_viewport().get_mouse_position()

func _build_arrow() -> ImageTexture:
	# B=black, W=white, space=transparent. 12x18px rendered at 2x.
	var rows := [
		"B           ",
		"BB          ",
		"BWB         ",
		"BWWB        ",
		"BWWWB       ",
		"BWWWWB      ",
		"BWWWWWB     ",
		"BWWWWWWB    ",
		"BWWWWWWWWB  ",
		"BWWWWWWWWWB ",
		"BWWWWWWWWWWB",
		"BWWWWWBBBBBB",
		"BWWBWWB     ",
		"BWB BWWB    ",
		"BB  BWWB    ",
		"B    BWWB   ",
		"     BWWB   ",
		"      BBBB  "
	]
	var img := Image.create(12, rows.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in rows.size():
		for x in rows[y].length():
			match rows[y][x]:
				"B": img.set_pixel(x, y, Color.BLACK)
				"W": img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)
GDEOF
echo "  [OK] MacCursor.gd written"

# Register MacCursor as an autoload
if grep -q 'MacCursor' project.godot; then
    echo "  [SKIP] MacCursor autoload already registered"
else
    sed -i '' 's|Simulation="\*res://Resources/Simulation.tscn"|Simulation="*res://Resources/Simulation.tscn"\nMacCursor="*res://Scripts/MacCursor.gd"|' project.godot
    echo "  [OK] MacCursor registered in project.godot autoloads"
fi

# Switch UIManager from MOUSE_MODE_CONFINED to MOUSE_MODE_CONFINED_HIDDEN
if grep -q 'MOUSE_MODE_CONFINED)' Scripts/UIManager.gd; then
    sed -i '' \
        's/Input\.set_mouse_mode(Input\.MOUSE_MODE_CONFINED)/Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)/g' \
        Scripts/UIManager.gd
    echo "  [OK] UIManager: MOUSE_MODE_CONFINED -> MOUSE_MODE_CONFINED_HIDDEN"
else
    echo "  [SKIP] UIManager mouse mode already patched"
fi

# Patch 3a: Set windowSize default to 2 (1920x1080) — ID 0 is now 4K with high-to-low ordering
python3 - <<'PYEOF'
import re, glob
patched_any = False
for path in glob.glob('Scripts/*.gd') + glob.glob('Resources/*.gd'):
    if 'Settings' in path:
        continue
    with open(path) as f:
        content = f.read()
    new_content, n = re.subn(
        r'(var\s+windowSize\s*(?::\s*\w+)?\s*=\s*)0\b',
        r'\g<1>2',
        content
    )
    if n:
        with open(path, 'w') as f:
            f.write(new_content)
        print(f"  [OK] {path}: windowSize default 0 -> 2 (1920x1080)")
        patched_any = True
if not patched_any:
    print("  [SKIP] windowSize default not found (already patched or not in expected location)")
PYEOF

# Patch 3: Replace percentage-based window sizes with fixed resolution presets
python3 - <<'PYEOF'
with open('Scripts/Settings.gd', 'r') as f:
    content = f.read()

MARKER = '"3840 x 2160": int(0)'
if MARKER in content:
    print("  [SKIP] Settings.gd resolution presets already applied")
    exit()

import re

# IDs must be sequential so get_item_id(index)==index (OptionButton auto-assigns IDs)
content = re.sub(
    r'var windowSizes: Dictionary = \{[^}]*\}',
    'var windowSizes: Dictionary = {\n'
    '"3840 x 2160": int(0),\n'
    '"2560 x 1440": int(1),\n'
    '"1920 x 1080": int(2),\n'
    '"1600 x 900": int(3),\n'
    '"1280 x 720": int(4),\n'
    '"1024 x 576": int(5)}',
    content
)

# Load-time block uses call_deferred (set_size in _ready() is ignored by Godot).
# Item-selected handler keeps plain set_size() so Patch 4 can match and rewrite it.
def replace_size_block(m):
    indent = m.group(1)
    i2 = indent + '    '
    var = m.group(2)
    if var == 'preferences.windowSize':
        def sz(w, h): return f'window.call_deferred("set_size", Vector2i({w}, {h}))'
    else:
        def sz(w, h): return f'window.set_size(Vector2i({w}, {h}))'
    return (
        f'{indent}if {var} == 0:\n{i2}{sz(3840, 2160)}\n'
        f'{indent}elif {var} == 1:\n{i2}{sz(2560, 1440)}\n'
        f'{indent}elif {var} == 2:\n{i2}{sz(1920, 1080)}\n'
        f'{indent}elif {var} == 3:\n{i2}{sz(1600, 900)}\n'
        f'{indent}elif {var} == 4:\n{i2}{sz(1280, 720)}\n'
        f'{indent}elif {var} == 5:\n{i2}{sz(1024, 576)}'
    )

content = re.sub(
    r'([ \t]+)if (preferences\.windowSize|option) == 0:\n'
    r'[ \t]+window\.set_size\(DisplayServer\.screen_get_size\(\)\)\n'
    r'[ \t]+elif \2 == 1:\n'
    r'[ \t]+window\.set_size\(DisplayServer\.screen_get_size\(\) / 1\.1\)\n'
    r'[ \t]+elif \2 == 2:\n'
    r'[ \t]+window\.set_size\(DisplayServer\.screen_get_size\(\) / 1\.25\)\n'
    r'[ \t]+elif \2 == 3:\n'
    r'[ \t]+window\.set_size\(DisplayServer\.screen_get_size\(\) / 1\.5\)',
    replace_size_block,
    content
)

with open('Scripts/Settings.gd', 'w') as f:
    f.write(content)
print("  [OK] Settings: window sizes -> 3840x2160 / 2560x1440 / 1920x1080 / 1600x900 / 1280x720 / 1024x576")
PYEOF

# Patch 4: Enable resolution control in fullscreen via scaling_3d_scale
# (window.set_size() has no effect in macOS fullscreen mode)
python3 - <<'PYEOF'
with open('Scripts/Settings.gd', 'r') as f:
    content = f.read()

MARKER = 'window.get_mode() == Window.MODE_FULLSCREEN'
if MARKER in content:
    print("  [SKIP] Settings.gd fullscreen resolution already patched")
    exit()

# set_deferred: scaling_3d_scale set synchronously after set_mode(FULLSCREEN) gets
# reset when the async OS transition completes and the viewport resizes.
content = content.replace(
    '        window.set_mode(Window.MODE_FULLSCREEN)\n'
    '        sizes.disabled = true\n'
    '\n'
    '\n'
    '    elif preferences.displayMode == 2:',
    '        window.set_mode(Window.MODE_FULLSCREEN)\n'
    '        sizes.disabled = false\n'
    '        var _fs_h = [2160.0, 1440.0, 1080.0, 900.0, 720.0, 576.0]\n'
    '        get_viewport().set_deferred("scaling_3d_scale", clampf(_fs_h[preferences.windowSize] / float(DisplayServer.screen_get_size().y), 0.1, 1.0))\n'
    '\n'
    '\n'
    '    elif preferences.displayMode == 2:'
)

# _on_fullscreen_pressed
content = content.replace(
    'func _on_fullscreen_pressed() -> void :\n'
    '    var window = get_window()\n'
    '    window.set_mode(Window.MODE_FULLSCREEN)\n'
    '    sizes.disabled = true\n'
    '\n'
    '    preferences.displayMode = 1\n'
    '    preferences.Save()\n'
    '    PlayClick()\n',
    'func _on_fullscreen_pressed() -> void :\n'
    '    var window = get_window()\n'
    '    window.set_mode(Window.MODE_FULLSCREEN)\n'
    '    sizes.disabled = false\n'
    '    var _fs_h = [2160.0, 1440.0, 1080.0, 900.0, 720.0, 576.0]\n'
    '    get_viewport().scaling_3d_scale = clampf(_fs_h[preferences.windowSize] / float(DisplayServer.screen_get_size().y), 0.1, 1.0)\n'
    '\n'
    '    preferences.displayMode = 1\n'
    '    preferences.Save()\n'
    '    PlayClick()\n'
)

# _on_windowed_pressed
content = content.replace(
    'func _on_windowed_pressed() -> void :\n'
    '    var window = get_window()\n'
    '    window.set_mode(Window.MODE_WINDOWED)\n'
    '    sizes.disabled = false\n',
    'func _on_windowed_pressed() -> void :\n'
    '    var window = get_window()\n'
    '    window.set_mode(Window.MODE_WINDOWED)\n'
    '    get_viewport().scaling_3d_scale = 1.0\n'
    '    sizes.disabled = false\n'
)

# _on_sizes_item_selected: branch on fullscreen vs windowed
import re
content = re.sub(
    r'func _on_sizes_item_selected\(index: int\) -> void :\n'
    r'    var window = get_window\(\)\n'
    r'    window\.set_mode\(Window\.MODE_WINDOWED\)\n'
    r'    var option = sizes\.get_item_id\(index\)\n'
    r'\n'
    r'    if option == 0:\n'
    r'        window\.set_size\(Vector2i\(3840, 2160\)\)\n'
    r'    elif option == 1:\n'
    r'        window\.set_size\(Vector2i\(2560, 1440\)\)\n'
    r'    elif option == 2:\n'
    r'        window\.set_size\(Vector2i\(1920, 1080\)\)\n'
    r'    elif option == 3:\n'
    r'        window\.set_size\(Vector2i\(1600, 900\)\)\n'
    r'    elif option == 4:\n'
    r'        window\.set_size\(Vector2i\(1280, 720\)\)\n'
    r'    elif option == 5:\n'
    r'        window\.set_size\(Vector2i\(1024, 576\)\)\n'
    r'    CenterWindow\(\)\n',
    'func _on_sizes_item_selected(index: int) -> void :\n'
    '    var window = get_window()\n'
    '    var option = sizes.get_item_id(index)\n'
    '    var _fs_h = [2160.0, 1440.0, 1080.0, 900.0, 720.0, 576.0]\n'
    '    var _sz = [Vector2i(3840, 2160), Vector2i(2560, 1440), Vector2i(1920, 1080), Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1024, 576)]\n'
    '\n'
    '    if window.get_mode() == Window.MODE_FULLSCREEN:\n'
    '        get_viewport().scaling_3d_scale = clampf(_fs_h[option] / float(DisplayServer.screen_get_size().y), 0.1, 1.0)\n'
    '    else:\n'
    '        window.set_mode(Window.MODE_WINDOWED)\n'
    '        window.call_deferred("set_size", _sz[option])\n'
    '        CenterWindow()\n',
    content
)

with open('Scripts/Settings.gd', 'w') as f:
    f.write(content)
print("  [OK] Settings: fullscreen resolution via scaling_3d_scale enabled")
PYEOF

echo "Patches applied."

# Export Native Build
echo "Exporting macOS app... (compiling textures takes a while)"
mkdir -p "../../mac_build"

"$GODOT_EXE" --headless --export-release "macOS" "../../mac_build/RoadToVostok.app"

echo "Build complete! App is in mac_build"
