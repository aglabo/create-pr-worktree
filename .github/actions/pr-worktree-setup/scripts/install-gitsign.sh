#!/usr/bin/env bash
# src: ./.github/actions/pr-worktree-initialize/scripts/install-gitsign.sh
# @(#) : Install gitsign for keyless signing with Sigstore
#
# Copyright (c) 2026- aglabo <https://github.com/aglabo>
#
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT
#
# @file install-gitsign.sh
# @brief Install gitsign binary for keyless signing with Sigstore
# @description
#   Downloads and installs gitsign from the official Sigstore releases.
#   Performs checksum verification and adds gitsign to PATH.
#
#   **Required Environment Variables:**
#   - RUNNER_TEMP: GitHub Actions runner temp directory
#
#   **Optional Parameters:**
#   - VERSION: gitsign version to install (default: v0.14.0)
#   - TEMP_DIR: temporary directory for downloads (default: $RUNNER_TEMP/gitsign-install)
#
#   **Installation Steps:**
#   1. Download gitsign binary for Linux AMD64
#   2. Download and verify SHA256 checksum
#   3. Install to $RUNNER_TEMP/gitsign/bin
#   4. Add to $GITHUB_PATH
#   5. Verify installation
#
# @example
#   VERSION=v0.14.0 ./install-gitsign.sh
#
# @exitcode 0 Installation successful
# @exitcode 1 Installation failed
#
# @author   atsushifx
# @version  1.0.0
# @license  MIT

set -euo pipefail

# Configuration
VERSION="${VERSION:-v0.14.0}"
TAG="${VERSION}"
TEMP_DIR="${TEMP_DIR:-${RUNNER_TEMP}/gitsign-install}"
INSTALL_DIR="${RUNNER_TEMP}/bin"
BASE_URL="https://github.com/sigstore/gitsign/releases/download"
ARCH_NAME="linux_amd64"  # Note: This script is designed for Linux AMD64 only
BINARY_NAME="gitsign_${TAG#v}_${ARCH_NAME}"
CHECKSUM_FILE="checksums.txt"

echo "=== Installing gitsign ${TAG} ==="
echo ""

# Create directories
mkdir -p "${TEMP_DIR}"
mkdir -p "${INSTALL_DIR}"

# Download gitsign binary
echo "Downloading gitsign binary..."
BINARY_URL="${BASE_URL}/${TAG}/${BINARY_NAME}"
echo "URL: ${BINARY_URL}"

curl -fsSL -o "${TEMP_DIR}/gitsign" "${BINARY_URL}" || {
  echo "::error::Failed to download gitsign binary from ${BINARY_URL}"
  echo "status=error" >> $GITHUB_OUTPUT
  echo "message=Failed to download gitsign binary" >> $GITHUB_OUTPUT
  exit 1
}
echo "✓ Binary downloaded"
echo ""

# Download checksums
echo "Downloading checksums..."
CHECKSUM_URL="${BASE_URL}/${TAG}/${CHECKSUM_FILE}"
echo "URL: ${CHECKSUM_URL}"

curl -fsSL -o "${TEMP_DIR}/checksums.txt" "${CHECKSUM_URL}" || {
  echo "::error::Failed to download checksums from ${CHECKSUM_URL}"
  echo "status=error" >> $GITHUB_OUTPUT
  echo "message=Failed to download checksums" >> $GITHUB_OUTPUT
  exit 1
}
echo "✓ Checksums downloaded"
echo ""

# Verify checksum
echo "Verifying checksum..."
pushd "${TEMP_DIR}" > /dev/null

# Extract checksum for our binary
EXPECTED_CHECKSUM=$(awk -v binary="${BINARY_NAME}" '$2 == binary {print $1; exit}' checksums.txt)

if [ -z "${EXPECTED_CHECKSUM}" ]; then
  echo "::error::Could not find checksum for ${BINARY_NAME} in checksums.txt"
  echo "status=error" >> $GITHUB_OUTPUT
  echo "message=Could not find checksum for ${BINARY_NAME} in checksums.txt" >> $GITHUB_OUTPUT
  popd > /dev/null
  exit 1
fi

# Calculate actual checksum
ACTUAL_CHECKSUM=$(sha256sum gitsign | awk '{print $1}')

if [ "${EXPECTED_CHECKSUM}" != "${ACTUAL_CHECKSUM}" ]; then
  echo "::error::Checksum verification failed!"
  echo "::error::Expected: ${EXPECTED_CHECKSUM}"
  echo "::error::Actual:   ${ACTUAL_CHECKSUM}"
  echo "status=error" >> $GITHUB_OUTPUT
  echo "message=Checksum verification failed" >> $GITHUB_OUTPUT
  popd > /dev/null
  exit 1
fi

echo "✓ Checksum verified: ${EXPECTED_CHECKSUM}"
popd > /dev/null
echo ""

# Install binary
echo "Installing gitsign to ${INSTALL_DIR}..."
install -m 755 "${TEMP_DIR}/gitsign" "${INSTALL_DIR}/gitsign" || {
  echo "::error::Failed to install gitsign to ${INSTALL_DIR}"
  echo "status=error" >> $GITHUB_OUTPUT
  echo "message=Failed to install gitsign" >> $GITHUB_OUTPUT
  exit 1
}
echo "✓ Binary installed"
echo ""

# Add to PATH
export PATH="${INSTALL_DIR}:${PATH}"
echo "Adding to PATH..."
echo "${INSTALL_DIR}" >> "${GITHUB_PATH}"
echo "✓ Added to PATH"
echo ""

# Verify installation
echo "Verifying installation..."
GITSIGN_VERSION=$("${INSTALL_DIR}/gitsign" version 2>&1 | head -3) || {
  echo "::error::gitsign installation verification failed"
  echo "status=error" >> $GITHUB_OUTPUT
  echo "message=gitsign installation verification failed" >> $GITHUB_OUTPUT
  exit 1
}

echo "${GITSIGN_VERSION}"
echo "✓ Installation verified"
echo ""

echo "=== gitsign installation complete ==="

# Output installation results
GITSIGN_FULL_PATH="${INSTALL_DIR}/gitsign"
echo "status=success" >> $GITHUB_OUTPUT
echo "message=gitsign installed successfully" >> $GITHUB_OUTPUT
echo "gitsign-path=${GITSIGN_FULL_PATH}" >> $GITHUB_OUTPUT
exit 0
