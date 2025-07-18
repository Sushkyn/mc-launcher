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

mkdir -p "${GAME_DIR}" "${ASSETS_DIR}/objects" "${LIBRARIES_DIR}" "${VERSION_DIR}/natives"

MANIFEST_URL=$(curl -s https://piston-meta.mojang.com/mc/game/version_manifest.json | jq -r ".versions[] | select(.id == \"$VERSION\") | .url")
VERSION_META=$(curl -s "$MANIFEST_URL")

CLIENT_URL=$(echo "$VERSION_META" | jq -r ".downloads.client.url")
wget -q -O "${VERSION_DIR}/${VERSION}.jar" "$CLIENT_URL"

ASSET_INDEX_URL=$(echo "$VERSION_META" | jq -r ".assetIndex.url")
ASSET_INDEX_NAME=$(echo "$VERSION_META" | jq -r ".assetIndex.id")
mkdir -p "${ASSETS_DIR}/indexes"
curl -s "$ASSET_INDEX_URL" -o "${ASSETS_DIR}/indexes/${ASSET_INDEX_NAME}.json"
curl -s "$ASSET_INDEX_URL" | jq -r '.objects[].hash' | xargs -n1 sh -c 'printf "https://resources.download.minecraft.net/%.2s/%s\n\tout=%.2s/%s\n" "$0" "$0" "$0" "$0"' | aria2c -i- -x16 -c -d "${ASSETS_DIR}/objects"

echo "$VERSION_META" | jq -c '.libraries[]' | while read -r lib; do
    ARTIFACT_URL=$(echo "$lib" | jq -r '.downloads.artifact.url // empty')
    ARTIFACT_PATH=$(echo "$lib" | jq -r '.downloads.artifact.path // empty')

    if [ -n "$ARTIFACT_URL" ] && [ -n "$ARTIFACT_PATH" ]; then
        aria2c -x16 -c -d "${LIBRARIES_DIR}" -o "$ARTIFACT_PATH" "$ARTIFACT_URL"
    fi

    NATIVES_URL=$(echo "$lib" | jq -r '.downloads.classifiers."natives-linux".url // empty')
    NATIVES_PATH=$(echo "$lib" | jq -r '.downloads.classifiers."natives-linux".path // empty')

    if [ -n "$NATIVES_URL" ] && [ -n "$NATIVES_PATH" ]; then
        aria2c -x16 -c -d "${LIBRARIES_DIR}" -o "$NATIVES_PATH" "$NATIVES_URL"
        unzip -n "${LIBRARIES_DIR}/${NATIVES_PATH}" -d "${VERSION_DIR}/natives"
    fi
done

CLASS_PATH=$(echo "$VERSION_META" | jq -r '.libraries[].downloads.artifact.path // empty' | awk -v dir="${LIBRARIES_DIR}" '{print dir "/" $0}' | paste -sd:)
CLASS_PATH="${CLASS_PATH}:${VERSION_DIR}/${VERSION}.jar"
MAIN_CLASS=$(echo "$VERSION_META" | jq -r '.mainClass')
VERSION_TYPE=$(echo "$VERSION_META" | jq -r '.type')

java \
  -Xmx2G -Xss1M \
  -Dfile.encoding=UTF-8 \
  -Djava.library.path="${VERSION_DIR}/natives" \
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
