#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# --- Pre-flight Checks ---

# Check for required commands.
for cmd in jq xmlstarlet git curl; do
    if ! command -v $cmd &> /dev/null; then
        echo "⚠️ Error: '$cmd' is not installed."
        exit 1
    fi
done

# --- Variables ---

PKG_NAME="live-backgroundremoval-lite"
UPSTREAM_OWNER="kaito-tokyo"
UPSTREAM_REPO="live-backgroundremoval-lite"
FLATPAK_MODULE_NAME="live-backgroundremoval-lite"
FLATPAK_APP_ID="com.obsproject.Studio.Plugin.LiveBackgroundRemovalLite"

REPO_ROOT="$(git rev-parse --show-toplevel)"

# 📂 Path configuration: flathub/<AppID>/<AppID>.json
FLATPAK_DIR="${REPO_ROOT}/flathub/${FLATPAK_APP_ID}"
FLATPAK_JSON_PATH="${FLATPAK_DIR}/${FLATPAK_APP_ID}.json"
FLATPAK_METAINFO_PATH="${FLATPAK_DIR}/${FLATPAK_APP_ID}.metainfo.xml"

# --- Main Script ---

echo "🚀 Starting Flatpak update for ${PKG_NAME}..."
echo "   Target: ${FLATPAK_DIR}"
echo "--------------------------------------------------"

# 0. Setup GitHub API Request Headers
CURL_ARGS=(-sL)
if [ -n "${GITHUB_TOKEN-}" ]; then
    CURL_ARGS+=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

# 1. Fetch Latest Version & Date from GitHub API
echo "📡 Fetching latest release info from GitHub..."
API_URL="https://api.github.com/repos/${UPSTREAM_OWNER}/${UPSTREAM_REPO}/releases/latest"
LATEST_TAG_JSON=$(curl "${CURL_ARGS[@]}" "${API_URL}")

if echo "${LATEST_TAG_JSON}" | grep -q "API rate limit exceeded"; then
    echo "❌ Error: GitHub API rate limit exceeded."
    exit 1
fi

LATEST_TAG=$(echo "${LATEST_TAG_JSON}" | jq -r .tag_name)
PUBLISHED_AT=$(echo "${LATEST_TAG_JSON}" | jq -r .published_at)

if [ "${LATEST_TAG}" == "null" ] || [ -z "${LATEST_TAG}" ]; then
    echo "❌ Error: Failed to fetch the latest tag."
    exit 1
fi

NEW_VERSION="${LATEST_TAG#v}"
# Use date from API (fallback to current date if failed)
CURRENT_DATE=$(date -d "${PUBLISHED_AT}" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)

echo "ℹ️  Latest Version: ${NEW_VERSION}"
echo "ℹ️  Release Date:   ${CURRENT_DATE}"

# Check file existence
if [ ! -f "${FLATPAK_JSON_PATH}" ] || [ ! -f "${FLATPAK_METAINFO_PATH}" ]; then
    echo "❌ Error: Flatpak files not found."
    echo "   Expected JSON at: ${FLATPAK_JSON_PATH}"
    echo "   Expected XML at:  ${FLATPAK_METAINFO_PATH}"
    exit 1
fi

# 2. Get Commit Hash
echo "🔍 Fetching git commit hash for tag '${LATEST_TAG}'..."
REMOTE_URL="https://github.com/${UPSTREAM_OWNER}/${UPSTREAM_REPO}.git"

# Fetch hash considering both Annotated Tags and Lightweight Tags
COMMIT_HASH=$(git ls-remote "${REMOTE_URL}" "refs/tags/${LATEST_TAG}^{}" | awk '{print $1}')
if [ -z "${COMMIT_HASH}" ]; then
    COMMIT_HASH=$(git ls-remote "${REMOTE_URL}" "refs/tags/${LATEST_TAG}" | awk '{print $1}')
fi

if [ -z "${COMMIT_HASH}" ]; then
    echo "❌ Error: Git tag '${LATEST_TAG}' not found in upstream."
    exit 1
fi
echo "   Hash: ${COMMIT_HASH}"

# 3. Check current version in JSON (Optional check)
CURRENT_JSON_TAG=$(jq -r --arg name "$FLATPAK_MODULE_NAME" \
    '.modules[] | select(.name == $name).sources[] | select(.type == "git").tag' \
    "${FLATPAK_JSON_PATH}")

if [ "${CURRENT_JSON_TAG}" == "${LATEST_TAG}" ]; then
    echo "✅ Manifest is already up to date (${LATEST_TAG})."
    # exit 0  <-- Leave commented out to force execution even if up-to-date.
fi

echo "--------------------------------------------------"

# 4. Update Flatpak Manifests
echo "📦 Updating Flatpak JSON manifest..."

# Update JSON file using jq
jq --arg ver "$LATEST_TAG" --arg hash "$COMMIT_HASH" --arg name "$FLATPAK_MODULE_NAME" '
    (.modules[] | select(.name == $name).sources[] | select(.type == "git"))
    |= (.tag = $ver | .commit = $hash)
' "$FLATPAK_JSON_PATH" > "$FLATPAK_JSON_PATH.tmp"

if [ $? -ne 0 ]; then
    echo "❌ Error: jq failed to update the JSON manifest."
    rm -f "$FLATPAK_JSON_PATH.tmp"
    exit 1
fi
if [ ! -s "$FLATPAK_JSON_PATH.tmp" ]; then
    echo "❌ Error: jq produced an empty output file. Manifest not updated."
    rm -f "$FLATPAK_JSON_PATH.tmp"
    exit 1
fi
mv "$FLATPAK_JSON_PATH.tmp" "$FLATPAK_JSON_PATH"
echo "  ✅ JSON updated."

# Update metainfo.xml file
echo "📦 Updating Metainfo XML..."

# Add release only if not already present
if ! xmlstarlet sel -t -c "/component/releases/release[@version='${NEW_VERSION}']" "${FLATPAK_METAINFO_PATH}" | grep -q .; then
    xmlstarlet ed -L \
        -i "/component/releases/release[1]" -t elem -n "release" \
        -i "/component/releases/release[1]" -t attr -n "version" -v "${NEW_VERSION}" \
        -i "/component/releases/release[1]" -t attr -n "date" -v "${CURRENT_DATE}" \
        "${FLATPAK_METAINFO_PATH}"
    echo "  ✅ XML updated."
else
    echo "  ℹ️ metainfo.xml: release ${NEW_VERSION} already exists, not adding duplicate."
fi

echo "--------------------------------------------------"

# 5. Git Operations

# Tag format: <plugin-name>/flatpak/<version>-<rev>
TAG_NAME="${PKG_NAME}/flatpak/${NEW_VERSION}-1"

echo "🚀 Executing Git operations..."

git add "${FLATPAK_JSON_PATH}" "${FLATPAK_METAINFO_PATH}"

# Commit changes
git commit -m "feat(flatpak): update ${PKG_NAME} to ${NEW_VERSION}"

if git rev-parse "${TAG_NAME}" >/dev/null 2>&1; then
    echo "⚠️  Tag '${TAG_NAME}' already exists. Skipping tag creation."
else
    git tag "${TAG_NAME}"
    echo "  ✅ Tag '${TAG_NAME}' created."
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "  📤 Pushing changes to remote..."

git push origin "${CURRENT_BRANCH}"
git push origin "${TAG_NAME}"

echo "🎉 Flatpak manifests have been updated and pushed successfully!"
