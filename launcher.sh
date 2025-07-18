#!/bin/bash

command -v aria2c > /dev/null 2>&1 || { echo >&2 "I require aria2 but it's not installed. Install it. Aborting."; exit 1; }
command -v java > /dev/null 2>&1 || { echo >&2 "I require jre8-openjdk but it's not installed. Install it. Aborting."; exit 1; }
command -v jq > /dev/null 2>&1 || { echo >&2 "I require jq but it's not installed. Install it. Aborting."; exit 1; }

usage() {
    echo "Usage: $0 VERSION NICKNAME"
    echo "Example: $0 1.5.2 Steve"
    exit 1
}

if [ "$#" -ne 2 ]; then
    usage
fi

VERSION="$1"
NICKNAME="$2"
GAME_DIR="/opt/.minecraft"
VERSION_DIR="${GAME_DIR}/versions/${VERSION}"
ASSETS_DIR="${GAME_DIR}/assets"
LIBRARIES_DIR="${GAME_DIR}/libraries"

mkdir -p "${GAME_DIR}"

if [ ! -d "${VERSION_DIR}" ]; then
    mkdir -p "${VERSION_DIR}"
    mkdir -p "${ASSETS_DIR}/objects"
    mkdir -p "${LIBRARIES_DIR}"
    mkdir -p "${VERSION_DIR}/natives"

    MANIFEST_URL=$(curl -s https://piston-meta.mojang.com/mc/game/version_manifest.json | jq -r ".versions[] | select(.id == \"${VERSION}\") | select(.type == \"release\") | .url")

    curl -s "$MANIFEST_URL" | jq -r ".downloads.client.url" | wget -i - -O "${VERSION_DIR}/${VERSION}.jar"

    ASSET_INDEX_URL=$(curl -s "$MANIFEST_URL" | jq -r ".assetIndex.url")
    ASSET_INDEX_NAME=$(curl -s "$MANIFEST_URL" | jq -r ".assetIndex.id")

    curl -s "$ASSET_INDEX_URL" | jq -r ".objects[].hash" | xargs -n1 sh -c 'printf "https://resources.download.minecraft.net/%.2s/%s\n\tout=%.2s/%s\n" "$0" "$0" "$0" "$0"' | aria2c -i- -x16 -c -d "${ASSETS_DIR}/objects"

    mkdir -p "${ASSETS_DIR}/indexes"
    curl -s "$ASSET_INDEX_URL" -o "${ASSETS_DIR}/indexes/${ASSET_INDEX_NAME}.json"

    curl -s "$MANIFEST_URL" | jq -r '.libraries[].downloads | if has("natives-linux") then ."natives-linux" else if has("artifact") then .artifact else empty end end | [.path, .url] | @tsv' | while IFS=$'\t' read -r path url; do
        if [ -n "$path" ] && [ -n "$url" ]; then
            aria2c -x16 -c -d "${LIBRARIES_DIR}" -o "$path" "$url"
        fi
    done

    curl -s "$MANIFEST_URL" | jq -r '.libraries[].downloads.classifiers."natives-linux".path // empty' | xargs -I% unzip -n "${LIBRARIES_DIR}/%" -d "${VERSION_DIR}/natives"
fi

MANIFEST_URL=$(curl -s https://piston-meta.mojang.com/mc/game/version_manifest.json | jq -r ".versions[] | select(.id == \"${VERSION}\") | select(.type == \"release\") | .url")
VERSION_META=$(curl -s "$MANIFEST_URL")
VERSION_TYPE=$(echo "$VERSION_META" | jq -r '.type')
ASSET_INDEX_NAME=$(echo "$VERSION_META" | jq -r '.assetIndex.id')
NATIVES_DIR="${VERSION_DIR}/natives"
CLASS_PATH=$(echo "$VERSION_META" | jq -r '.libraries[].downloads | if has("artifact") then .artifact.path else empty end' | awk -v lib_dir="${LIBRARIES_DIR}" '{print lib_dir "/" $0}' | paste -sd:)
CLASS_PATH="${CLASS_PATH}:${VERSION_DIR}/${VERSION}.jar"
MAIN_CLASS=$(echo "$VERSION_META" | jq -r '.mainClass')

java \
    -Xmx2G -Xss1M \
    -Dfile.encoding=UTF-8 \
    -Djava.library.path="${NATIVES_DIR}" \
    -Dminecraft.launcher.brand='java-minecraft-launcher' \
    -Dminecraft.launcher.version='1.6.84-j' \
    -cp "${CLASS_PATH}" "${MAIN_CLASS}" \
    "${NICKNAME}" \
    --version "${VERSION}" \
    --gameDir "${GAME_DIR}" \
    --assetsDir "${ASSETS_DIR}" \
    --assetIndex "${ASSET_INDEX_NAME}" \
    --uuid '00000000-0000-0000-0000-000000000000' \
    --accessToken 'null' \
    --userType 'legacy' \
    --versionType "${VERSION_TYPE}"
