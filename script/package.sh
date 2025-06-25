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
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Color definitions for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script metadata
SCRIPT_NAME=$(basename "$0")
SCRIPT_VERSION="1.0.0"

# Default values
COLINK_VERSION="1.0.4"
COS_VERSION="v1.1.5"
COLISTENER_VERSION="2.0.0-0"
COBRIDGE_VERSION="1.0.9-0"
TRZSZ_VERSION="1.1.6"
RELEASE_VERSION="unknown"
OUTPUT_DIR="${HOME}"
VERBOSE=false
DRY_RUN=false

# Function to display help message
help() {
  cat << EOF
${GREEN}${SCRIPT_NAME} v${SCRIPT_VERSION}${NC}
Download and package coScene edge software components

${YELLOW}Usage:${NC}
  ${SCRIPT_NAME} [OPTIONS]

${YELLOW}Options:${NC}
  --cos_version=VERSION        Set COS version (default: ${COS_VERSION})
  --colink_version=VERSION     Set Colink version (default: ${COLINK_VERSION})
  --colistener_version=VERSION Set Colistener version (default: ${COLISTENER_VERSION})
  --cobridge_version=VERSION   Set Cobridge version (default: ${COBRIDGE_VERSION})
  --trzsz_version=VERSION      Set Trzsz version (default: ${TRZSZ_VERSION})
  --release_version=TAG        Set repository tag (default: ${RELEASE_VERSION})
  --output_dir=PATH            Set output directory (default: ${OUTPUT_DIR})
  --verbose                    Enable verbose output
  --dry-run                    Show what would be downloaded without actually downloading
  -h, --help                   Show this help message
  -v, --version                Show version information

${YELLOW}Examples:${NC}
  ${SCRIPT_NAME} --cos_version=1.2.3
  ${SCRIPT_NAME} --colistener_version=1.0.2-0 --cobridge_version=1.0.9-0
  ${SCRIPT_NAME} --output_dir=/tmp/packages --verbose
  ${SCRIPT_NAME} --dry-run

EOF
}

# Function to print colored messages
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to show progress
show_progress() {
  local current=$1
  local total=$2
  local task=$3
  if [ "${total}" -eq 0 ]; then
    echo -e "${BLUE}[Progress]${NC} ${task}: ${current}/0 (N/A)"
    return
  fi
  local percent=$((current * 100 / total))
  echo -e "${BLUE}[Progress]${NC} ${task}: ${current}/${total} (${percent}%)"
}

# Cleanup function
cleanup() {
  if [ -n "${TEMP_DIR:-}" ] && [ -d "${TEMP_DIR}" ]; then
    log_info "Cleaning up temporary directory..."
    rm -rf "${TEMP_DIR}"
  fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Function to download file with error handling
# Usage: download_with_retry <url> <output_file> [continue_on_error]
# Returns: 0 on success, 1 on error
download_with_retry() {
  local url="$1"
  local output_file="$2"
  local continue_on_error="${3:-true}"  # Default to true if not specified
  
  if [ "${DRY_RUN}" = "true" ]; then
    log_info "[DRY-RUN] Would download: ${url}"
    return 0
  fi
  
  if [ "${VERBOSE}" = "true" ]; then
    log_info "Downloading ${url}"
  else
    echo "Downloading $(basename "${url}")..."
  fi
  
  local http_status=$(curl -L -s -o "${output_file}" -w "%{http_code}" "${url}")
  
  if [ "${http_status}" -eq 404 ]; then
    log_warning "Skipped: 404 Not Found - ${url}"
    rm -f "${output_file}"
    if [ "${continue_on_error}" = "true" ]; then
      return 1
    fi
  elif [ "${http_status}" -eq 200 ]; then
    log_success "Downloaded successfully: $(basename "${output_file}")"
    return 0
  else
    log_warning "Unexpected HTTP status ${http_status} for ${url}"
    rm -f "${output_file}"
    if [ "${continue_on_error}" = "true" ]; then
      return 1
    fi
  fi
}

# Support configurations
SUPPORT_OS=("linux")
SUPPORT_COS_ARCH=("amd64" "arm64" "arm")
SUPPORT_MESH_ARCH=("amd64" "aarch64")

SUPPORT_COLISTENER_ARCH=("amd64" "arm64" "armhf")
declare -A SUPPORT_ROS_DISTRO_MAP
SUPPORT_ROS_DISTRO_MAP["noetic"]="focal"
SUPPORT_ROS_DISTRO_MAP["foxy"]="focal"
SUPPORT_ROS_DISTRO_MAP["humble"]="jammy"
SUPPORT_ROS_DISTRO_MAP["melodic"]="bionic"
# SUPPORT_ROS_DISTRO_MAP["indigo"]="trusty"

MESH_BASE_URL=https://coscene-download.oss-cn-hangzhou.aliyuncs.com
COS_BASE_URL=https://coscene-download.oss-cn-hangzhou.aliyuncs.com/coscout/v2
COLISTENER_BASE_URL=https://coscene-apt.oss-cn-hangzhou.aliyuncs.com/dists

# get user input
while test $# -gt 0; do
  case $1 in
  --cos_version=*)
    COS_VERSION="${1#*=}"
    shift # past argument=value
    ;;
  --colink_version=*)
    COLINK_VERSION="${1#*=}"
    shift
    ;;
  --colistener_version=*)
    COLISTENER_VERSION="${1#*=}"
    shift
    ;;
  --cobridge_version=*)
    COBRIDGE_VERSION="${1#*=}"
    shift
    ;;
  --trzsz_version=*)
    TRZSZ_VERSION="${1#*=}"
    shift
    ;;
  --release_version=*)
    RELEASE_VERSION="${1#*=}"
    shift
    ;;
  --output_dir=*)
    OUTPUT_DIR="${1#*=}"
    shift
    ;;
  --verbose)
    VERBOSE=true
    shift
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  -h|--help)
    help
    exit 0
    ;;
  -v|--version)
    echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
    exit 0
    ;;
  *)
    log_error "Unknown option: $1"
    help
    exit 1
    ;;
  esac
done

# Validate output directory
if [ ! -d "${OUTPUT_DIR}" ]; then
  log_error "Output directory does not exist: ${OUTPUT_DIR}"
  exit 1
fi

# Show configuration
log_info "Configuration:"
log_info "  COS Version: ${COS_VERSION}"
log_info "  Colink Version: ${COLINK_VERSION}"
log_info "  Colistener Version: ${COLISTENER_VERSION}"
log_info "  Cobridge Version: ${COBRIDGE_VERSION}"
log_info "  Trzsz Version: ${TRZSZ_VERSION}"
log_info "  Repository Tag: ${RELEASE_VERSION}"
log_info "  Output Directory: ${OUTPUT_DIR}"
log_info "  Verbose: ${VERBOSE}"
log_info "  Dry Run: ${DRY_RUN}"

# Create temp directory
TEMP_DIR=$(mktemp -d)
if [ ! -e "$TEMP_DIR" ]; then
  log_error "Failed to create temp directory"
  exit 1
fi
log_info "Created temporary directory: ${TEMP_DIR}"

# Calculate total downloads for progress tracking
total_downloads=0
total_downloads=$((total_downloads + ${#SUPPORT_MESH_ARCH[@]} * 2))  # mesh + trzsz
total_downloads=$((total_downloads + ${#SUPPORT_OS[@]} * ${#SUPPORT_COS_ARCH[@]} * 2))  # cos + metadata
total_downloads=$((total_downloads + 3 * ${#SUPPORT_OS[@]}))  # cgroup files for arm
total_downloads=$((total_downloads + ${#SUPPORT_COLISTENER_ARCH[@]} * ${#SUPPORT_ROS_DISTRO_MAP[@]}))  # colistener
total_downloads=$((total_downloads + ${#SUPPORT_COLISTENER_ARCH[@]} * ${#SUPPORT_ROS_DISTRO_MAP[@]}))  # cobridge
current_download=0

# Debug information
if [ "${VERBOSE}" = "true" ]; then
  log_info "Total downloads calculated: ${total_downloads}"
  log_info "SUPPORT_MESH_ARCH: ${#SUPPORT_MESH_ARCH[@]} items"
  log_info "SUPPORT_OS: ${#SUPPORT_OS[@]} items"
  log_info "SUPPORT_COS_ARCH: ${#SUPPORT_COS_ARCH[@]} items"
  log_info "SUPPORT_COLISTENER_ARCH: ${#SUPPORT_COLISTENER_ARCH[@]} items"
  log_info "SUPPORT_ROS_VERSION: ${#SUPPORT_ROS_DISTRO_MAP[@]} items"
fi

# Download mesh and trzsz
log_info "Downloading colink and Trzsz binaries..."
for arch in "${SUPPORT_MESH_ARCH[@]}"; do
  mesh_folder="${TEMP_DIR}/colink"
  mkdir -p "${mesh_folder}"

  trzsz_folder="${TEMP_DIR}/trzsz_tar"
  mkdir -p "${trzsz_folder}"

  mesh_download_url=${MESH_BASE_URL}/colink/v${COLINK_VERSION}/colink-${arch}
  trzsz_download_url=${MESH_BASE_URL}/trzsz/v${TRZSZ_VERSION}/trzsz_${TRZSZ_VERSION}_linux_${arch}.tar.gz

  current_download=$((current_download + 1))
  show_progress ${current_download} ${total_downloads} "Downloading Colink"
  if ! download_with_retry "${mesh_download_url}" "${mesh_folder}/colink-${arch}"; then
    continue
  fi

  current_download=$((current_download + 1))
  show_progress ${current_download} ${total_downloads} "Downloading Trzsz"
  if ! download_with_retry "${trzsz_download_url}" "${trzsz_folder}/trzsz_${TRZSZ_VERSION}_linux_${arch}.tar.gz"; then
    continue
  fi
done

# Download COS binaries
log_info "Downloading coscout binaries..."
for os in "${SUPPORT_OS[@]}"; do
  for arch in "${SUPPORT_COS_ARCH[@]}"; do
    cos_folder="${TEMP_DIR}/cos/${arch}"
    mkdir -p "${cos_folder}"

    cos_download_url=${COS_BASE_URL}/versions/${COS_VERSION}/${os}-${arch}.gz
    cos_metadata_url=${COS_BASE_URL}/versions/${COS_VERSION}/${os}-${arch}.json

    current_download=$((current_download + 1))
    show_progress ${current_download} ${total_downloads} "Downloading COS"
    if ! download_with_retry "${cos_download_url}" "${cos_folder}/${os}-${arch}.gz"; then
      continue
    fi

    current_download=$((current_download + 1))
    show_progress ${current_download} ${total_downloads} "Downloading COS metadata"
    if ! download_with_retry "${cos_metadata_url}" "${cos_folder}/${os}-${arch}.json"; then
      continue
    fi

    # if arch is arm, download cgroup-bin
    if [ "${arch}" == "arm" ]; then
      log_info "Downloading cgroup binaries for ARM..."
      
      current_download=$((current_download + 1))
      show_progress ${current_download} ${total_downloads} "Downloading cgroup-bin"
      cgroup_bin_download_url=${MESH_BASE_URL}/cgroup_bin/${arch}/cgroup_bin.deb
      download_with_retry "${cgroup_bin_download_url}" "${cos_folder}/cgroup_bin.deb" "false"

      current_download=$((current_download + 1))
      show_progress ${current_download} ${total_downloads} "Downloading cgroup-lite"
      cgroup_lite_download_url=${MESH_BASE_URL}/cgroup_bin/${arch}/cgroup_lite.deb
      download_with_retry "${cgroup_lite_download_url}" "${cos_folder}/cgroup_lite.deb" "false"

      current_download=$((current_download + 1))
      show_progress ${current_download} ${total_downloads} "Downloading libcgroup"
      libcgroup_download_url=${MESH_BASE_URL}/cgroup_bin/${arch}/libcgroup1.deb
      download_with_retry "${libcgroup_download_url}" "${cos_folder}/libcgroup1.deb" "false"
    fi
  done
done

# Download Colistener packages
log_info "Downloading colistener packages..."
for arch in "${SUPPORT_COLISTENER_ARCH[@]}"; do
  if [ "${arch}" == "armhf" ]; then
    ubuntu_distro="trusty"
    colistener_folder="${TEMP_DIR}/colistener/${ubuntu_distro}/${arch}/indigo"
    mkdir -p "${colistener_folder}"
    colistener_download_url=${COLISTENER_BASE_URL}/${ubuntu_distro}/main/binary-${arch}/ros-indigo-colistener_${COLISTENER_VERSION}${ubuntu_distro}_${arch}.deb

    current_download=$((current_download + 1))
    show_progress ${current_download} ${total_downloads} "Downloading Colistener"
    if ! download_with_retry "${colistener_download_url}" "${colistener_folder}/ros-indigo-colistener_${ubuntu_distro}_${arch}.deb"; then
      continue
    fi
  else
    for ros_distro in "${!SUPPORT_ROS_DISTRO_MAP[@]}"; do
      ubuntu_distro=${SUPPORT_ROS_DISTRO_MAP[${ros_distro}]}
      colistener_folder="${TEMP_DIR}/colistener/${ubuntu_distro}/${arch}/${ros_distro}"
      mkdir -p "${colistener_folder}"
      colistener_download_url=${COLISTENER_BASE_URL}/${ubuntu_distro}/main/binary-${arch}/ros-${ros_distro}-colistener_${COLISTENER_VERSION}${ubuntu_distro}_${arch}.deb

      current_download=$((current_download + 1))
      show_progress ${current_download} ${total_downloads} "Downloading Colistener"
      if ! download_with_retry "${colistener_download_url}" "${colistener_folder}/ros-${ros_distro}-colistener_${ubuntu_distro}_${arch}.deb"; then
        continue
      fi
    done
  fi
done

# Download cobridge packages
log_info "Downloading cobridge packages..."
for arch in "${SUPPORT_COLISTENER_ARCH[@]}"; do
  if [ "${arch}" == "armhf" ]; then
    ubuntu_distro="trusty"
    cobridge_folder="${TEMP_DIR}/cobridge/${ubuntu_distro}/${arch}/indigo"
    mkdir -p "${cobridge_folder}"
    cobridge_download_url=${COLISTENER_BASE_URL}/${ubuntu_distro}/main/binary-${arch}/ros-indigo-cobridge_${COBRIDGE_VERSION}${ubuntu_distro}_${arch}.deb

    current_download=$((current_download + 1))
    show_progress ${current_download} ${total_downloads} "Downloading cobridge"
    if ! download_with_retry "${cobridge_download_url}" "${cobridge_folder}/ros-indigo-colistener_${ubuntu_distro}_${arch}.deb"; then
      continue
    fi
  else
    for ros_distro in "${!SUPPORT_ROS_DISTRO_MAP[@]}"; do
      ubuntu_distro=${SUPPORT_ROS_DISTRO_MAP[${ros_distro}]}
      cobridge_folder="${TEMP_DIR}/cobridge/${ubuntu_distro}/${arch}/${ros_distro}"
      mkdir -p "${cobridge_folder}"
      cobridge_download_url=${COLISTENER_BASE_URL}/${ubuntu_distro}/main/binary-${arch}/ros-${ros_distro}-cobridge_${COBRIDGE_VERSION}${ubuntu_distro}_${arch}.deb

      current_download=$((current_download + 1))
      show_progress ${current_download} ${total_downloads} "Downloading cobridge"
      if ! download_with_retry "${cobridge_download_url}" "${cobridge_folder}/ros-${ros_distro}-cobridge_${ubuntu_distro}_${arch}.deb"; then
        continue
      fi
    done
  fi
done

# Generate version.yaml file
log_info "Generating version.yaml file..."
VERSION_FILE="${TEMP_DIR}/version.yaml"

cat > "${VERSION_FILE}" << EOF
# coScene Edge Software Package Versions
# Generated on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

release_version: ${RELEASE_VERSION}
assemblies:
  colink_version: ${COLINK_VERSION}
  cos_version: ${COS_VERSION}
  colistener_version: ${COLISTENER_VERSION}
  cobridge_version: ${COBRIDGE_VERSION}
  trzsz_version: ${TRZSZ_VERSION}
EOF

log_success "Generated version.yaml file"

# Skip packaging if dry run
if [ "${DRY_RUN}" = "true" ]; then
  log_info "[DRY-RUN] Skipping packaging step"
  exit 0
fi

# Package all binaries
log_info "Creating package archives..."

# tar temp dir with all binaries
log_info "Creating complete package..."
tar -czf "${OUTPUT_DIR}/cos_binaries.tar.gz" -C "${TEMP_DIR}/" "."
log_success "Created: ${OUTPUT_DIR}/cos_binaries.tar.gz"

# Show final results
log_info "Package creation completed!"
log_info "Output directory contents:"
ls -lh "${OUTPUT_DIR}"/cos_binaries*.tar.gz 2>/dev/null || log_warning "No packages were created"

# Cleanup is handled by trap
