#!/bin/bash
set -euo pipefail

# --- Configuration ---
PKG_NAME="live-backgroundremoval-lite"
UPSTREAM_OWNER="kaito-tokyo"
UPSTREAM_REPO="live-backgroundremoval-lite"

REPO_ROOT="$(git rev-parse --show-toplevel)"

# 📁 ディレクトリ構造: arch/plugin/PKGBUILD (ユーザー様の好み)
ARCH_PKGBUILD_PATH="${REPO_ROOT}/arch/${PKG_NAME}/PKGBUILD"

# --- Main Script ---

echo "🚀 Checking for the latest version of ${PKG_NAME}..."

# 0. Setup GitHub API
CURL_ARGS=(-sL)
if [ -n "${GITHUB_TOKEN-}" ]; then
    CURL_ARGS+=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

# 1. Fetch latest tag
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

# 2. Check current version
if [ ! -f "${ARCH_PKGBUILD_PATH}" ]; then
    echo "❌ Error: PKGBUILD not found at ${ARCH_PKGBUILD_PATH}"
    echo "   Expected structure: arch/${PKG_NAME}/PKGBUILD"
    exit 1
fi

CURRENT_VERSION=$(grep "^pkgver=" "${ARCH_PKGBUILD_PATH}" | cut -d'=' -f2)

if [ "${CURRENT_VERSION}" == "${NEW_VERSION}" ]; then
    echo "✅ Package is already up to date (${CURRENT_VERSION}). No changes needed."
    exit 0
fi

echo "🔄 Update needed: ${CURRENT_VERSION} -> ${NEW_VERSION}"

# 3. Update PKGBUILD
echo "📦 Updating PKGBUILD..."

DOWNLOAD_URL="https://github.com/${UPSTREAM_OWNER}/${UPSTREAM_REPO}/archive/refs/tags/${LATEST_TAG}.tar.gz"
SHA256_SUM=$(curl -sL "${DOWNLOAD_URL}" | sha256sum | awk '{print $1}')

if [ -z "${SHA256_SUM}" ]; then
    echo "❌ Error: Failed to calculate SHA256 checksum."
    exit 1
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
    SED_CMD=(sed -i '')
else
    SED_CMD=(sed -i)
fi

"${SED_CMD[@]}" -e "s/^pkgver=.*/pkgver=${NEW_VERSION}/" "${ARCH_PKGBUILD_PATH}"
"${SED_CMD[@]}" -e "s/^pkgrel=.*/pkgrel=1/" "${ARCH_PKGBUILD_PATH}"
"${SED_CMD[@]}" -e "s/^sha256sums=('.*')/sha256sums=('${SHA256_SUM}')/" "${ARCH_PKGBUILD_PATH}"

echo "  ✅ PKGBUILD updated."

# --- 4. Git Operations ---

# 🏷️ タグ名: plugin/arch/ver (リスト表示での整理整頓を優先)
TAG_NAME="${PKG_NAME}/arch/${NEW_VERSION}-1"

echo "🚀 Executing Git operations..."

git add "${ARCH_PKGBUILD_PATH}"
git commit -m "feat(${PKG_NAME}): update to ${NEW_VERSION}"

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

echo "🎉 Successfully updated, committed, tagged, and pushed!"
