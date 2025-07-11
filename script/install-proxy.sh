#!/usr/bin/env bash
# Copyright 2025 coScene
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -Eeuo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo_error() {
    echo -e "${RED}$*${NC}" >&2
}

echo_info() {
    echo -e "${GREEN}$*${NC}"
}

# Error handling function
error_handler() {
    local line_no=$1
    local error_msg=$2

    echo_error "⚠️ Error on line $line_no:"
    echo_error "⚠️ Error: $error_msg"

    exit 1
}

# Cleanup function
cleanup() {
    if [ ! -d "$TEMP_DIR" ]; then
        return
    fi
    echo "Cleaning up temp directory $TEMP_DIR"
    rm -rf "$TEMP_DIR"
}

# Set up traps
trap 'error_handler ${LINENO} "$BASH_COMMAND" "$?"' ERR
trap cleanup EXIT SIGINT SIGTERM

# check temp dir
TEMP_DIR=$(mktemp -d)
if [ ! -e "$TEMP_DIR" ]; then
  echo_error "Failed to create temp directory"
  exit 1
fi

# set os version
OS=$(uname -s)
case "$OS" in
Linux)
  OS="linux"
  ;;
Darwin)
  OS="darwin"
  ;;
FreeBSD)
  OS="freebsd"
  ;;
*)
  echo_error "Unsupported OS: $OS. Only Linux, Darwin, and FreeBSD are supported." >&2
  exit 1
  ;;
esac

# Set download ARCH based on system architecture
ARCH=$(uname -m)
case "$ARCH" in
x86_64)
  ARCH="amd64"
  ;;
arm64 | aarch64)
  ARCH="arm64"
  ;;
armv7l)
  ARCH="armv7"
  ;;
armv6l)
  ARCH="armv6"
  ;;
i?86)
  ARCH="386"
  ;;
*)
  echo_error "Unsupported architecture: $ARCH. Only x86_64, arm64, armv7, armv6, i386 are supported." >&2
  exit 1
  ;;
esac

# Check if tar installed
if ! command -v tar &>/dev/null; then
  echo_error "tar is required but not installed. Please install it using: 'sudo apt-get install -y tar'" >&2
  exit 1
fi

# Default values
GLIDER_VERSION="0.16.4"
LISTEN_PORT=""
DISABLE_SERVICE=0
CONFIG_FILE=""
LOG_LEVEL="info"
GITHUB_BASE_URL="https://github.com/nadoo/glider/releases/download"

help() {
  cat <<EOF
usage: $0 [OPTIONS]

    --help                  Show this message
    --listen_port           Port to listen on (required, e.g. 8080)
    --version               Glider version to install (default: ${GLIDER_VERSION})
    --config_file           Custom config file path (optional)
    --log_level             Log level: error, warn, info, debug (default: info)
    --disable_service       Disable systemd service installation
    --show_version          Show the version of the installed glider
EOF
}

error_exit() {
  echo_error "ERROR: $1" >&2
  exit 1
}

download_file() {
  local dest=$1
  local url=$2

  echo "Downloading from $url..."
  curl -SLo "$dest" "$url" || error_exit "Failed to download $url"
}

# Check if systemd is available
check_systemd() {
  if [[ "$(ps --no-headers -o comm 1 2>/dev/null)" == "systemd" ]]; then
    return 0
  else
    echo_error "This script requires systemd."
    return 1
  fi
}

# Parse command line arguments
while test $# -gt 0; do
  case $1 in
  --help)
    help
    exit 0
    ;;
  --listen_port=*)
    LISTEN_PORT="${1#*=}"
    shift
    ;;
  --version=*)
    GLIDER_VERSION="${1#*=}"
    shift
    ;;
  --config_file=*)
    CONFIG_FILE="${1#*=}"
    shift
    ;;
  --log_level=*)
    LOG_LEVEL="${1#*=}"
    shift
    ;;
  --disable_service)
    DISABLE_SERVICE=1
    shift
    ;;
  --show_version)
    if [ -e /usr/local/bin/glider ]; then
      /usr/local/bin/glider -version
    else
      echo "glider is not installed."
    fi
    exit 0
    ;;
  *)
    echo_error "unknown option: $1"
    help
    exit 1
    ;;
  esac
done

# Validate required parameters
if [[ -z "$LISTEN_PORT" ]]; then
  echo_error "ERROR: --listen_port is required. Please specify a port number."
  exit 1
fi

# Validate port number
if ! [[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] || [ "$LISTEN_PORT" -lt 1 ] || [ "$LISTEN_PORT" -gt 65535 ]; then
  echo_error "ERROR: Invalid port number: $LISTEN_PORT. Port must be between 1 and 65535."
  exit 1
fi

# Validate log level
case "$LOG_LEVEL" in
error|warn|info|debug)
  ;;
*)
  echo_error "ERROR: Invalid log level: $LOG_LEVEL. Valid levels are: error, warn, info, debug."
  exit 1
  ;;
esac

echo ""
echo_info "Installing glider proxy server..."
echo "Version:     ${GLIDER_VERSION}"
echo "OS:          ${OS}"
echo "Arch:        ${ARCH}"
echo "Listen Port: ${LISTEN_PORT}"
echo "Log Level:   ${LOG_LEVEL}"

# Construct download URL
GLIDER_FILENAME="glider_${GLIDER_VERSION}_${OS}_${ARCH}.tar.gz"
DOWNLOAD_URL="${GITHUB_BASE_URL}/v${GLIDER_VERSION}/${GLIDER_FILENAME}"

# Download glider
echo ""
echo "Downloading glider ${GLIDER_VERSION}..."
download_file "$TEMP_DIR/$GLIDER_FILENAME" "$DOWNLOAD_URL"

# Extract glider
echo "Extracting glider..."
tar -xzf "$TEMP_DIR/$GLIDER_FILENAME" -C "$TEMP_DIR" || error_exit "Failed to extract glider"

# Find the glider binary
GLIDER_BINARY=""
if [ -f "$TEMP_DIR/glider" ]; then
  GLIDER_BINARY="$TEMP_DIR/glider"
elif [ -f "$TEMP_DIR/glider_${GLIDER_VERSION}_${OS}_${ARCH}/glider" ]; then
  GLIDER_BINARY="$TEMP_DIR/glider_${GLIDER_VERSION}_${OS}_${ARCH}/glider"
else
  # Search for glider binary in extracted files
  GLIDER_BINARY=$(find "$TEMP_DIR" -name "glider" -type f | head -n1)
fi

if [[ -z "$GLIDER_BINARY" || ! -f "$GLIDER_BINARY" ]]; then
  error_exit "Failed to find glider binary in extracted files"
fi

# Install glider binary
echo "Installing glider binary..."
sudo install -m 755 "$GLIDER_BINARY" /usr/local/bin/glider

# Create configuration directory
CONFIG_DIR="/etc/glider"
sudo mkdir -p "$CONFIG_DIR"

# Create default configuration if not provided
if [[ -z "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$CONFIG_DIR/glider.conf"
  echo "Creating default configuration file at $CONFIG_FILE..."
  
  sudo tee "$CONFIG_FILE" >/dev/null <<EOF
# Glider configuration file
# Listen on all interfaces
listen=:${LISTEN_PORT}

# Log level
verbose=true
EOF
else
  if [[ ! -f "$CONFIG_FILE" ]]; then
    error_exit "Specified config file does not exist: $CONFIG_FILE"
  fi
  echo "Using custom configuration file: $CONFIG_FILE"
fi

# Create systemd service if not disabled
if [[ $DISABLE_SERVICE -eq 0 ]]; then
  if check_systemd; then
    echo ""
    echo "Creating systemd service..."
    
    sudo tee /etc/systemd/system/glider.service >/dev/null <<EOF
[Unit]
Description=Glider Proxy Server
Documentation=https://github.com/nadoo/glider
After=network.target iptables.service ip6tables.service

[Service]
Type=simple
DynamicUser=yes
Restart=always
LimitNOFILE=102400
ExecStart=/usr/local/bin/glider -config=${CONFIG_FILE}

[Install]
WantedBy=multi-user.target
EOF

    echo "Reloading systemd daemon..."
    sudo systemctl daemon-reload
    
    echo "Enabling glider service..."
    sudo systemctl enable glider
    
    echo "Starting glider service..."
    if sudo systemctl start glider; then
      echo_info "Glider service started successfully."
      
      # Show service status
      echo ""
      echo "Service status:"
      sudo systemctl status glider --no-pager
    else
      echo_error "Failed to start glider service."
      echo_error "Checking service logs..."
      sudo journalctl -xe -u glider --no-pager | tail -n 20
      exit 1
    fi
  else
    echo_error "This script requires systemd for service management."
    exit 1
  fi
else
  echo "Skipping systemd service installation..."
fi

echo ""
echo_info "🎉 Glider proxy server installation completed successfully!"
echo_info "Configuration file: $CONFIG_FILE"
echo_info "Listening on port: $LISTEN_PORT"

if [[ $DISABLE_SERVICE -eq 0 ]]; then
  echo_info "Service management commands:"
  echo_info "  - Check status: sudo systemctl status glider"
  echo_info "  - View logs:    sudo journalctl -f -u glider"
  echo_info "  - Stop service: sudo systemctl stop glider"
  echo_info "  - Start service: sudo systemctl start glider"
fi

echo_info "Test the proxy with: curl -x socks5://127.0.0.1:${LISTEN_PORT} https://www.google.com"

exit 0 
