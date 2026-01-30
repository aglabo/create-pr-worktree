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
VERSION="${VERSION:-0.14.0}"
TEMP_DIR="${TEMP_DIR:-${RUNNER_TEMP}/gitsign-install}"
INSTALL_DIR="${RUNNER_TEMP}/bin"
BASE_URL="https://github.com/sigstore/gitsign/releases/download"
ARCH_NAME="linux_amd64"
BINARY_NAME="gitsign_${VERSION#v}_${ARCH_NAME}"
CHECKSUM_FILE="checksums.txt"

echo "=== Installing gitsign ${VERSION} ==="
echo ""

# Create directories
mkdir -p "${TEMP_DIR}"
mkdir -p "${INSTALL_DIR}"

# Download gitsign binary
echo "Downloading gitsign binary..."
BINARY_URL="${BASE_URL}/v${VERSION#v}/${BINARY_NAME}"
echo "URL: ${BINARY_URL}"

if ! curl -fsSL -o "${TEMP_DIR}/gitsign" "${BINARY_URL}"; then
  echo "::error::Failed to download gitsign binary from ${BINARY_URL}"
  exit 1
fi
echo "✓ Binary downloaded"
echo ""

# Download checksums
echo "Downloading checksums..."
CHECKSUM_URL="${BASE_URL}/${VERSION}/${CHECKSUM_FILE}"
echo "URL: ${CHECKSUM_URL}"

if ! curl -fsSL -o "${TEMP_DIR}/checksums.txt" "${CHECKSUM_URL}"; then
  echo "::error::Failed to download checksums from ${CHECKSUM_URL}"
  exit 1
fi
echo "✓ Checksums downloaded"
echo ""

# Verify checksum
echo "Verifying checksum..."
cd "${TEMP_DIR}"

# Extract checksum for our binary
EXPECTED_CHECKSUM=$(awk -v binary="${BINARY_NAME}" '$2 == binary {print $1; exit}' checksums.txt)

if [ -z "${EXPECTED_CHECKSUM}" ]; then
  echo "::error::Could not find checksum for ${BINARY_NAME} in checksums.txt"
  exit 1
fi

# Calculate actual checksum
ACTUAL_CHECKSUM=$(sha256sum gitsign | awk '{print $1}')

if [ "${EXPECTED_CHECKSUM}" != "${ACTUAL_CHECKSUM}" ]; then
  echo "::error::Checksum verification failed!"
  echo "::error::Expected: ${EXPECTED_CHECKSUM}"
  echo "::error::Actual:   ${ACTUAL_CHECKSUM}"
  exit 1
fi

echo "✓ Checksum verified: ${EXPECTED_CHECKSUM}"
echo ""

# Install binary
echo "Installing gitsign to ${INSTALL_DIR}..."
mv gitsign "${INSTALL_DIR}/gitsign"
chmod +x "${INSTALL_DIR}/gitsign"
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
if ! "${INSTALL_DIR}/gitsign" version > /dev/null 2>&1; then
  echo "::error::gitsign installation verification failed"
  exit 1
fi

echo "=== gitsign installation complete ==="
exit 0
