# Road to Vostok Mac Auto-Porter

An automated, zero-setup bash script to extract, recompile, and build a native macOS (Apple Silicon / ARM) port of Road to Vostok directly from the original game files.

⚠️ **You must own the game and/or have the game files!** ([Steam Store Page](https://store.steampowered.com/app/1963610/Road_to_Vostok/)) This script does not distribute any game assets. You must install the game on Windows (or via Steam via CrossOver/Whisky) and locate your `RTV.pck` file to use this script.

## What it does
1. Automatically downloads the correct macOS `GDRE Tools` release.
2. Extracts your `RTV.pck` file.
3. Scrapes the recovery logs to find the exact Godot Engine version used to build the game.
4. Downloads that exact Godot Engine and its macOS Export Templates (~1GB).
5. Injects the necessary macOS ETC2 texture compression settings.
6. Recompiles and exports a fully playable, native `RoadToVostok.app` to a `mac_build` folder.

## How to use

1. Place the `build_rtv_mac_arm_app.sh` script into the same directory next to your `RTV.pck` file.
2. Open your Terminal in that folder.
3. Run the script using `bash` (this automatically bypasses macOS Gatekeeper restrictions):
   ```bash
   bash build_rtv_mac_arm_app.sh
   ```
4. Wait for the process to finish. The initial extraction and texture compilation will take a few minutes depending on your Mac's speed.
5. You will find your app file `RoadToVostok.app` inside the newly created `mac_build` directory.
