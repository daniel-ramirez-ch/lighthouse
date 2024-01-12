#!/usr/bin/env bash

# Install Lighthouse's latest released version. OS is picked automatically using uname

# Default install path
INSTALL_PATH="./"

# Required commands check
for cmd in curl tar uname; do
  command -v "$cmd" >/dev/null 2>&1 || { echo >&2 "This script requires $cmd but it's not installed. Aborting."; exit 1; }
done

# Fetch the latest release version of Lighthouse.
# This tends to fail in CI, so 5 attempts are given.
for attempt in {1..5}; do
    VERSION=$(curl -s https://api.github.com/repos/sigp/lighthouse/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')

    # If successful, break out of the loop
    if [ -n "$VERSION" ]; then
        echo "Fetched latest version of Lighthouse: $VERSION"
        break
    else
        echo "Attempt $attempt failed. Retrying..."
        sleep 1 # Optional: wait before retrying
    fi

    # If all attempts fail, print an error message and exit
    if [ $attempt -eq 5 ]; then
        echo "Failed to fetch the latest version of Lighthouse."
        exit 1
    fi
done

# Check OS and set BIN_NAME accordingly
OS=$(uname -s)
case "$OS" in
  Linux) BIN_NAME="lighthouse-${VERSION}-x86_64-unknown-linux-gnu.tar.gz" ;;
  Darwin) BIN_NAME="lighthouse-${VERSION}-x86_64-apple-darwin.tar.gz" ;;
  *) echo "Unsupported OS: $OS"; exit 1 ;;
esac

# Get options
while getopts "p:h" flag; do
  case "${flag}" in
    p) INSTALL_PATH=${OPTARG};;
    h)
      echo "Install Lighthouse's latest released version. OS is picked automatically using uname"
      echo
      echo "usage: $0 <Options> "
      echo
      echo "Options:"
      echo "   -p: INSTALL_PATH, specify the installation path, default './'"
      echo "   -h: this help"
      exit
      ;;
  esac
done

# Download and extract the release
echo "Downloading ${BIN_NAME}"
if ! curl -LO "https://github.com/sigp/lighthouse/releases/download/${VERSION}/${BIN_NAME}"; then
  echo "Failed to download ${BIN_NAME}"
  exit 1
fi

if ! tar -xzf "${BIN_NAME}"; then
  echo "Failed to extract ${BIN_NAME}"
  exit 1
fi

# Remove the tarball
echo "Removing downloaded tarball ${BIN_NAME}"
rm "${BIN_NAME}"

# Check if a binary already exists and back it up
if [ -f "${INSTALL_PATH}" ]; then
  echo "Existing binary found at ${INSTALL_PATH}. Backing up..."
  mv "${INSTALL_PATH}" "${INSTALL_PATH}_backup_$(date +%Y%m%d%H%M%S)"
fi

# Move the binary only if INSTALL_PATH is different from current directory
if [ "${INSTALL_PATH}" != "./" ]; then
  echo "Installing Lighthouse to ${INSTALL_PATH}"
  if ! mv lighthouse "${INSTALL_PATH}"; then
    echo "Failed to move Lighthouse to ${INSTALL_PATH}"
    exit 1
  fi
else
  echo "Lighthouse binary is already in the current directory."
fi

echo "Lighthouse ${VERSION} installed successfully at ${INSTALL_PATH}."

