#!/bin/bash
set -euo pipefail

# --- Configuration ---
PKG_NAME="live-backgroundremoval-lite"
UPSTREAM_OWNER="kaito-tokyo"
UPSTREAM_REPO="live-backgroundremoval-lite"

REPO_ROOT="$(git rev-parse --show-toplevel)"

# 📂 Directory structure: arch/plugin/PKGBUILD
ARCH_PKGBUILD_PATH="${REPO_ROOT}/arch/${PKG_NAME}/PKGBUILD"

# --- Main Script ---

echo "🚀 Checking for the latest version of ${PKG_NAME}..."

# 0. Setup GitHub API Request Headers
CURL_ARGS=(-sL)
if [ -n "${GITHUB_TOKEN-}" ]; then
    CURL_ARGS+=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

# 1. Fetch latest tag from GitHub API
API_URL="https://api.github.com/repos/${UPSTREAM_OWNER}/${UPSTREAM_REPO}/releases/latest"
LATEST_TAG_JSON=$(curl "${CURL_ARGS[@]}" "${API_URL}")

if echo "${LATEST_TAG_JSON}" | grep -q "API rate limit exceeded"; then
    echo "❌ Error: GitHub API rate limit exceeded."
    exit 1
fi

LATEST_TAG=$(echo "${LATEST_TAG_JSON}" | jq -r .tag_name)

if [ "${LATEST_TAG}" == "null" ] || [ -z "${LATEST_TAG}" ]; then
    echo "❌ Error: Failed to fetch the latest tag."
    exit 1
fi

NEW_VERSION="${LATEST_TAG#v}"

# 2. Check current version in PKGBUILD
if [ ! -f "${ARCH_PKGBUILD_PATH}" ]; then
    echo "❌ Error: PKGBUILD not found at ${ARCH_PKGBUILD_PATH}"
    exit 1
fi

CURRENT_VERSION=$(grep "^pkgver=" "${ARCH_PKGBUILD_PATH}" | cut -d'=' -f2)

# If you want to force tagging/pushing even if versions match, comment out this check.
if [ "${CURRENT_VERSION}" == "${NEW_VERSION}" ]; then
    echo "✅ Package is already up to date (${CURRENT_VERSION})."
    # Comment out the line below if you want to continue without exiting.
    # exit 0
    echo "   Continuing process to ensure tags/commits..."
fi

echo "🔄 Update needed (or forced): ${CURRENT_VERSION} -> ${NEW_VERSION}"

# 3. Update PKGBUILD (Using awk)
echo "📦 Updating PKGBUILD..."

DOWNLOAD_URL="https://github.com/${UPSTREAM_OWNER}/${UPSTREAM_REPO}/archive/refs/tags/${LATEST_TAG}.tar.gz"
SHA256_SUM=$(curl -sL "${DOWNLOAD_URL}" | sha256sum | awk '{print $1}')

if [ -z "${SHA256_SUM}" ]; then
    echo "❌ Error: Failed to calculate SHA256 checksum."
    exit 1
fi

# Create a temporary file
TEMP_FILE=$(mktemp)

# Use awk to replace values and write to the temporary file
# Pass variables to awk using -v
awk -v new_ver="${NEW_VERSION}" \
    -v new_sum="${SHA256_SUM}" \
    '{
        # Find and replace the pkgver line
        if ($0 ~ /^pkgver=/) {
            print "pkgver=" new_ver
        }
        # Find the pkgrel line and reset it to 1
        else if ($0 ~ /^pkgrel=/) {
            print "pkgrel=1"
        }
        # Find and replace the sha256sums line
        else if ($0 ~ /^sha256sums=\(/) {
            # \x27 represents a single quote in hex.
            # Constructing the string "sha256sums=('" new_sum "')"
            print "sha256sums=(\x27" new_sum "\x27)"
        }
        # Print other lines as they are
        else {
            print $0
        }
    }' "${ARCH_PKGBUILD_PATH}" > "${TEMP_FILE}"

# Overwrite the original file upon success
mv "${TEMP_FILE}" "${ARCH_PKGBUILD_PATH}"

echo "  ✅ PKGBUILD updated."

# --- 4. Git Operations ---

# 🏷️ Tag format: plugin/arch/ver
TAG_NAME="${PKG_NAME}/arch/${NEW_VERSION}-1"

echo "🚀 Executing Git operations..."

git add "${ARCH_PKGBUILD_PATH}"

# Note: Continue even if commit fails
# By adding "|| echo ...", the script won't stop even if there are no changes (exit code 1).
git commit -m "feat(${PKG_NAME}): update to ${NEW_VERSION}" || echo "⚠️  Commit failed or nothing to commit. Continuing to push..."

if git rev-parse "${TAG_NAME}" >/dev/null 2>&1; then
    echo "⚠️  Tag '${TAG_NAME}' already exists. Skipping tag creation."
else
    git tag "${TAG_NAME}"
    echo "  ✅ Tag '${TAG_NAME}' created."
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "  📤 Pushing changes to remote (branch: ${CURRENT_BRANCH})..."

git push origin "${CURRENT_BRANCH}"
git push origin "${TAG_NAME}"

echo "🎉 Successfully updated, committed (if changes existed), tagged, and pushed!"
