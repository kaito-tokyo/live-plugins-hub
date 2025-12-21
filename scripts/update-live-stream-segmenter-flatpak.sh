#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# --- Path Resolution & Setup ---

# 1. Resolve the directory where this script is physically located.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 2. Find the repository root relative to the script location.
if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "❌ Error: This script must be located within a git repository."
    exit 1
fi

REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

# 3. Change the current working directory to the repository root.
cd "${REPO_ROOT}"

echo "📂 Working directory set to: ${REPO_ROOT}"

# --- Pre-flight Checks ---

# Check for required commands.
for cmd in jq xmlstarlet git curl; do
    if ! command -v $cmd &> /dev/null; then
        echo "⚠️ Error: '$cmd' is not installed."
        exit 1
    fi
done

# --- Variables ---

PKG_NAME="live-stream-segmenter"
UPSTREAM_OWNER="kaito-tokyo"
UPSTREAM_REPO="live-stream-segmenter"
FLATPAK_MODULE_NAME="live-stream-segmenter"
FLATPAK_APP_ID="com.obsproject.Studio.Plugin.LiveStreamSegmenter"
# Note: REPO_ROOT is already set in the "Path Resolution" section.

# 📂 Path configuration: flatpak/<AppID>/<AppID>.json
FLATPAK_DIR="${REPO_ROOT}/flatpak/${FLATPAK_APP_ID}"
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

# 1. Fetch Latest Tag from GitHub API
echo "📡 Fetching latest tag info from GitHub..."

# Changed from releases/latest to tags?per_page=1
API_URL="https://api.github.com/repos/${UPSTREAM_OWNER}/${UPSTREAM_REPO}/tags?per_page=1"
LATEST_TAG_JSON=$(curl "${CURL_ARGS[@]}" "${API_URL}")

if echo "${LATEST_TAG_JSON}" | grep -q "API rate limit exceeded"; then
    echo "❌ Error: GitHub API rate limit exceeded."
    exit 1
fi

# Parse the tag name from the array (.[0].name)
LATEST_TAG=$(echo "${LATEST_TAG_JSON}" | jq -r '.[0].name')

if [ "${LATEST_TAG}" == "null" ] || [ -z "${LATEST_TAG}" ]; then
    echo "❌ Error: Failed to fetch the latest tag."
    exit 1
fi

NEW_VERSION="${LATEST_TAG#v}"

# NOTE: The 'tags' API does not provide a 'published_at' date.
# We will use the current date for the metainfo.xml update.
CURRENT_DATE=$(date +%Y-%m-%d)

echo "ℹ️  Latest Version: ${NEW_VERSION}"
echo "ℹ️  Packaged Date:  ${CURRENT_DATE}"

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

# Commit changes (continue even if there are no changes to commit)
git commit -m "feat(flatpak): update ${PKG_NAME} to ${NEW_VERSION}" || echo "⚠️  Commit failed or nothing to commit. Continuing..."

# ▼▼▼ Abort if working tree is dirty ▼▼▼
if [ -n "$(git status --porcelain)" ]; then
    echo "❌ Error: Working tree is dirty (uncommitted changes present). Aborting."
    echo "   Please check the following files:"
    git status --short
    exit 1
fi
# ▲▲▲

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
