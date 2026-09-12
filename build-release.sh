#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

REPO="Kaiyou-Digital/SafariSummarizer"
BINARY_NAME="safari-summary"

# --- Auto-version from conventional commits ---

LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
CURRENT_VERSION="${LATEST_TAG#v}"

IFS='.' read -r MAJOR MINOR PATCH <<< "${CURRENT_VERSION}"

COMMITS=$(git log "${LATEST_TAG}..HEAD" --pretty=format:"%s" 2>/dev/null || git log --pretty=format:"%s")

if [[ -z "${COMMITS}" ]]; then
    echo "No commits since ${LATEST_TAG}. Nothing to release."
    exit 1
fi

BUMP="patch"
while IFS= read -r msg; do
    if echo "$msg" | grep -qiE "^breaking[:(]|^[a-z]+!:"; then
        BUMP="major"
        break
    elif echo "$msg" | grep -qiE "^feat[:(]"; then
        BUMP="minor"
    fi
done <<< "$COMMITS"

case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
esac

VERSION="${MAJOR}.${MINOR}.${PATCH}"
echo "==> Version bump: ${CURRENT_VERSION} -> ${VERSION} (${BUMP})"

# --- Update Version.swift, commit and tag ---

sed -i '' "s/let safariSummaryVersion = \".*\"/let safariSummaryVersion = \"${VERSION}\"/" Sources/Version.swift

git add Sources/Version.swift
git commit -m "release: v${VERSION}"
git tag "v${VERSION}"

echo "==> Tagged v${VERSION}"

# --- Build and smoke-test ---

echo "==> Building release..."
swift build -c release

BINARY_PATH=".build/release/SafariSummary"
if [[ ! -x "${BINARY_PATH}" ]]; then
    echo "Error: build product not found at ${BINARY_PATH}"
    exit 1
fi

echo "==> Smoke-testing binary..."
BUILT_VERSION=$("${BINARY_PATH}" --version)
if [[ "${BUILT_VERSION}" != "${VERSION}" ]]; then
    echo "Error: built binary reports version ${BUILT_VERSION}, expected ${VERSION}"
    exit 1
fi

# --- Publish ---

echo "==> Pushing to origin..."
git push origin main --tags

echo "==> Creating GitHub release..."
gh release create "v${VERSION}" --repo "${REPO}" --title "v${VERSION}" --generate-notes

# --- Update Homebrew tap (source-build formula: version + sha256 of the tag archive) ---

TAP_REPO="${HOME}/Work/Kaiyou/Apps/homebrew-tap"
FORMULA="${TAP_REPO}/Formula/${BINARY_NAME}.rb"

if [[ -f "${FORMULA}" ]]; then
    ARCHIVE_URL="https://github.com/${REPO}/archive/refs/tags/v${VERSION}.tar.gz"
    echo "==> Fetching tag archive to compute sha256..."
    TMP_ARCHIVE=$(mktemp)
    curl -fsSL "${ARCHIVE_URL}" -o "${TMP_ARCHIVE}"
    SHA=$(shasum -a 256 "${TMP_ARCHIVE}" | awk '{print $1}')
    rm -f "${TMP_ARCHIVE}"

    echo "==> Updating Homebrew formula..."
    sed -i '' "s|url \".*\"|url \"${ARCHIVE_URL}\"|" "${FORMULA}"
    sed -i '' "s/sha256 \".*\"/sha256 \"${SHA}\"/" "${FORMULA}"
    sed -i '' "s/assert_match \".*\",/assert_match \"${VERSION}\",/" "${FORMULA}"

    git -C "${TAP_REPO}" add "Formula/${BINARY_NAME}.rb"
    git -C "${TAP_REPO}" commit -m "${BINARY_NAME} ${VERSION}"
    git -C "${TAP_REPO}" push origin main
    echo "==> Homebrew tap updated"
else
    echo "Warning: formula not found at ${FORMULA}, skipping"
fi

echo ""
echo "==> Released v${VERSION}"
