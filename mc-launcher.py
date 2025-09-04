import os
import sys
import json
import requests
import subprocess
from pathlib import Path
from zipfile import ZipFile

# -------------------------------
# Usage check
# -------------------------------
if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} VERSION NICKNAME")
    print(f"Example: {sys.argv[0]} 1.5.2 Steve")
    sys.exit(1)

VERSION = sys.argv[1]
NICKNAME = sys.argv[2]

# -------------------------------
# Directories
# -------------------------------
GAME_DIR = Path.home() / ".minecraft"
VERSION_DIR = GAME_DIR / "versions" / VERSION
ASSETS_DIR = GAME_DIR / "assets"
LIBRARIES_DIR = GAME_DIR / "libraries"

VERSION_DIR.mkdir(parents=True, exist_ok=True)
(ASSETS_DIR / "objects").mkdir(parents=True, exist_ok=True)
(LIBRARIES_DIR).mkdir(parents=True, exist_ok=True)
(VERSION_DIR / "natives").mkdir(parents=True, exist_ok=True)
(ASSETS_DIR / "indexes").mkdir(parents=True, exist_ok=True)

# -------------------------------
# Download version manifest
# -------------------------------
manifest_url = "https://piston-meta.mojang.com/mc/game/version_manifest.json"
manifest_data = requests.get(manifest_url).json()

version_info = next(v for v in manifest_data["versions"] if v["id"] == VERSION)
version_meta = requests.get(version_info["url"]).json()

# -------------------------------
# Download client jar
# -------------------------------
client_url = version_meta["downloads"]["client"]["url"]
client_path = VERSION_DIR / f"{VERSION}.jar"
with open(client_path, "wb") as f:
    f.write(requests.get(client_url).content)

# -------------------------------
# Download assets
# -------------------------------
asset_index_url = version_meta["assetIndex"]["url"]
asset_index_name = version_meta["assetIndex"]["id"]
asset_index_path = ASSETS_DIR / "indexes" / f"{asset_index_name}.json"
with open(asset_index_path, "wb") as f:
    f.write(requests.get(asset_index_url).content)

with open(asset_index_path) as f:
    assets = json.load(f)["objects"]

for asset_name, asset_info in assets.items():
    hash_val = asset_info["hash"]
    obj_dir = ASSETS_DIR / "objects" / hash_val[:2]
    obj_dir.mkdir(parents=True, exist_ok=True)
    obj_path = obj_dir / hash_val
    if not obj_path.exists():
        url = f"https://resources.download.minecraft.net/{hash_val[:2]}/{hash_val}"
        with open(obj_path, "wb") as f:
            f.write(requests.get(url).content)

# -------------------------------
# Download libraries
# -------------------------------
for lib in version_meta["libraries"]:
    artifact = lib.get("downloads", {}).get("artifact")
    if artifact:
        artifact_url = artifact["url"]
        artifact_path = LIBRARIES_DIR / artifact["path"]
        artifact_path.parent.mkdir(parents=True, exist_ok=True)
        if not artifact_path.exists():
            with open(artifact_path, "wb") as f:
                f.write(requests.get(artifact_url).content)
    # Handle natives
    natives = lib.get("downloads", {}).get("classifiers", {}).get("natives-windows")
    if natives:
        natives_url = natives["url"]
        natives_path = LIBRARIES_DIR / natives["path"]
        natives_path.parent.mkdir(parents=True, exist_ok=True)
        if not natives_path.exists():
            with open(natives_path, "wb") as f:
                f.write(requests.get(natives_url).content)
            # Unzip to natives folder
            with ZipFile(natives_path, "r") as zip_ref:
                zip_ref.extractall(VERSION_DIR / "natives")

# -------------------------------
# Construct classpath
# -------------------------------
class_paths = [
    str(LIBRARIES_DIR / lib.get("downloads", {}).get("artifact", {}).get("path"))
    for lib in version_meta["libraries"]
    if "downloads" in lib and "artifact" in lib["downloads"]
]
class_paths.append(str(client_path))
classpath = ";".join(filter(None, class_paths))  # Windows uses ; as separator

# -------------------------------
# Launch Minecraft
# -------------------------------
main_class = version_meta["mainClass"]
version_type = version_meta["type"]

java_cmd = [
    "java",
    "-Xmx2G",
    "-Xss1M",
    "-Dfile.encoding=UTF-8",
    f"-Djava.library.path={VERSION_DIR / 'natives'}",
    "-Dminecraft.launcher.brand=python-minecraft-launcher",
    "-Dminecraft.launcher.version=1.0",
    "-cp", classpath,
    main_class,
    NICKNAME,
    "--version", VERSION,
    "--gameDir", str(GAME_DIR),
    "--assetsDir", str(ASSETS_DIR),
    "--assetIndex", asset_index_name,
    "--uuid", "00000000-0000-0000-0000-000000000000",
    "--accessToken", "null",
    "--userType", "legacy",
    "--versionType", version_type
]

subprocess.run(java_cmd)
