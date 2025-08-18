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

set -e

ping_test_endpoint="openapi.coscene.io"
upload_speed_test_endpoint="https://storage-us-central-1.coscene.io/v1/speed-test"
download_speed_test_endpoint="https://coscene-download.s3.us-east-1.amazonaws.com/cosbinary/tar/latest/cos_binaries.tar.gz"

if [ -f /etc/os-release ]; then
    source /etc/os-release
elif [ -f /usr/lib/os-release ]; then
    source /usr/lib/os-release
else
    NAME=unknown
    VERSION=unknown
fi

# Unified ROS version detection function
get_ros_version() {
    if [[ -n "${ROS_DISTRO:-}" ]]; then
        echo "$ROS_DISTRO"
    elif [ -d /opt/ros ] && [ "$(find /opt/ros -maxdepth 1 -type d | wc -l)" -gt 1 ]; then
        echo $(ls -d /opt/ros/*/ | cut -d'/' -f4)
    else
        echo "unknown"
    fi
}

# Unified Ubuntu codename detection function
get_ubuntu_distro() {
  # in keenon's ubuntu14.04, /etc/os-release file exists, but `VERSION_CODENAME` and `UBUNTU_CODENAME` not found.
  # so, check /etc/lsb-release first, if file not exists, fallback to /etc/os-release.
  if [[ -f /etc/lsb-release ]]; then
    source /etc/lsb-release
    echo "${DISTRIB_CODENAME:-unknown}"
  elif [[ -f /etc/os-release ]]; then
    source /etc/os-release
    if [[ -n "${VERSION_CODENAME:-}" ]]; then
      echo "$VERSION_CODENAME"
    elif [[ -n "${UBUNTU_CODENAME:-}" ]]; then
      echo "$UBUNTU_CODENAME"
    else
      echo "unknown"
    fi
  else
    echo "unknown"
  fi
}

# Unified architecture info function
get_arch_info() {
    local arch=$(uname -m)
    local colink_arch=""
    
    case "$arch" in
    x86_64)
        arch="amd64"
        colink_arch="amd64"
        ;;
    arm64 | aarch64)
        arch="arm64"
        colink_arch="aarch64"
        ;;
    armv7l)
        arch="arm"
        ;;
    *)
        arch="unsupported"
        ;;
    esac
    
    echo "$arch $colink_arch"
}

# Format output with aligned columns
print_info() {
    local label="$1"
    local value="$2"
    local width=12  # label width
    
    printf "%-${width}s | %s\n" "$label" "$value"
}

upload_speed_test() {
    pushd $(mktemp -d) >/dev/null
    local bs
    if [[ "$OSTYPE" == "darwin"* ]]; then
        bs=10m
    else
        bs=10M
    fi
    dd if=/dev/urandom of=speedtest bs=${bs} count=1 2>/dev/null
    # If upload speed test endpoint is not configured, return early for upper layer handling
    if [ -z "${upload_speed_test_endpoint}" ]; then
        rm -f speedtest
        popd >/dev/null
        return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        # Use curl to obtain upload speed (bytes/s)
        local bytes_per_sec
        bytes_per_sec=$(curl -s -o /dev/null -w "%{speed_upload}" -X POST -F "file=@speedtest" "${upload_speed_test_endpoint}" 2>/dev/null || echo "")
        if [ -n "$bytes_per_sec" ] && [ "$bytes_per_sec" != "0" ]; then
            if awk -v s="$bytes_per_sec" 'BEGIN{exit !(s>=1048576)}'; then
                local mps
                mps=$(awk -v s="$bytes_per_sec" 'BEGIN{printf "%.1f", s/1048576}')
                echo "${mps}M/s"
            else
                local kps
                kps=$(awk -v s="$bytes_per_sec" 'BEGIN{printf "%.1f", s/1024}')
                echo "${kps}K/s"
            fi
        fi
    elif command -v wget >/dev/null 2>&1; then
        # Fallback to wget (may not reliably parse speed)
        wget --method=POST --body-file=speedtest "${upload_speed_test_endpoint}" -O /dev/null 2>&1 | grep -o "[0-9.]\+ [KM]*B/s"
    fi
    rm -f speedtest
    popd >/dev/null
}

download_speed_test() {
    # Use wget to download and parse speed; support multiple output formats
    local output=$(wget --progress=dot:mega -O /dev/null $download_speed_test_endpoint 2>&1)
    local speed=""
    
    # Try multiple parsing patterns
    # Pattern 1: match "100.5K/s"
    speed=$(echo "$output" | grep -o "[0-9.]\+[KM]/s" | tail -1)
    if [ -n "$speed" ]; then
        echo "$speed"
        return
    fi
    
    # Pattern 2: match "100.5 KB/s"
    speed=$(echo "$output" | grep -o "[0-9.]\+ [KM]*B/s" | tail -1)
    if [ -n "$speed" ]; then
        echo "$speed"
        return
    fi
    
    # Pattern 3: use curl as fallback
    if command -v curl &> /dev/null; then
        speed=$(curl -o /dev/null -s -w "%{speed_download}" $download_speed_test_endpoint 2>/dev/null)
        if [ -n "$speed" ] && [ "$speed" != "0" ]; then
            # Convert bytes/s to KB/s
            speed_kb=$(echo "$speed" | awk '{printf "%.1f", $1/1024}')
            echo "${speed_kb}K/s"
            return
        fi
    fi
    
    # If all fail, return default
    echo "0K/s"
}

speed_test_avg() {
    local num_tests=2  # fewer tests for speed
    local total=0
    local valid_tests=0
    
    for ((i = 0; i < $num_tests; i++)); do
        if [[ "$1" = "upload" ]]; then
            local speed_test=$(upload_speed_test)
        elif [[ "$1" = "download" ]]; then
            local speed_test=$(download_speed_test)
        else
            return 1
        fi
        
        # Ensure valid speed value
        if [ -z "$speed_test" ] || [[ "$speed_test" == "0"* ]]; then
            continue
        fi
        
        local number=$(echo $speed_test | grep -o "[0-9.]\+" | head -1)
        local units=$(echo $speed_test | grep -o "[KM]*" | head -1)
        
        # Validate numeric value
        if [ -z "$number" ] || [ "$number" = "0" ]; then
            continue
        fi
        
        # Convert directly to Mbit/s to avoid rounding drift
        local mbits=0
        if [[ "$units" = "M" ]]; then
            # MB/s to Mbit/s: multiply by 8
            mbits=$(echo $number | awk '{printf "%.2f", $1 * 8}')
        else
            # KB/s to Mbit/s: divide by 125 (since 1000 KB/s ÷ 8 = 125 KB/s = 1 Mbit/s)
            mbits=$(echo $number | awk '{printf "%.2f", $1 / 125}')
        fi
        
        total=$(echo $mbits $total | awk '{print $1 + $2}')
        valid_tests=$((valid_tests + 1))
    done
    
    # If no valid test results, return default
    if [ $valid_tests -eq 0 ]; then
        echo "unable to measure"
        return
    fi
    
    # Compute average
    local avg_mbits=$(echo $total $valid_tests | awk '{printf "%.1f", $1 / $2}')
    echo "${avg_mbits} Mbit/s"
}

# Check network connectivity
check_network_connectivity() {
    # Method 1: ping public DNS
    if ping -c 1 -W 3 223.5.5.5 >/dev/null 2>&1; then
        return 0
    fi
    
    # Method 2: ping target domain
    if ping -c 1 -W 3 "${ping_test_endpoint}" >/dev/null 2>&1; then
        return 0
    fi
    
    # Method 3: use curl to check connectivity
    if command -v curl &> /dev/null; then
        if curl -s --max-time 5 --head "http://www.google.com" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    return 1
}

# HTTPS capability check
check_https_support() {
    local test_url="https://${ping_test_endpoint}"
    
    # Method 1: use curl to check HTTPS
    if command -v curl &> /dev/null; then
        if curl -s --max-time 10 --head "$test_url" >/dev/null 2>&1; then
            echo "Supported"
            return
        fi
    fi
    
    # Method 2: use wget to check HTTPS
    if command -v wget &> /dev/null; then
        if wget --timeout=10 --spider --quiet "$test_url" >/dev/null 2>&1; then
            echo "Supported"
            return
        fi
    fi
    
    # Method 3: use openssl to test SSL/TLS
    if command -v openssl &> /dev/null; then
        if echo | timeout 10 openssl s_client -connect "${ping_test_endpoint}:443" >/dev/null 2>&1; then
            echo "Supported"
            return
        fi
    fi
    
    echo "Unsupported"
}

# Check if a URL is reachable
check_url_availability() {
    local url="$1"
    local component_name="$2"
    
    # Use curl to get HTTP status code
    if command -v curl &> /dev/null; then
        local status_code=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 --head "$url" 2>/dev/null)
        if [ "$status_code" = "200" ]; then
            print_info "$component_name" "Installable"
            return 0
        elif [ "$status_code" = "404" ]; then
            print_info "$component_name" "Unavailable (404)"
            return 1
        elif [ -n "$status_code" ] && [ "$status_code" != "000" ]; then
            print_info "$component_name" "Exception (HTTP $status_code)"
            return 1
        fi
    fi
    
    # Use wget as a fallback
    if command -v wget &> /dev/null; then
        if wget --timeout=10 --spider --quiet "$url" >/dev/null 2>&1; then
            print_info "$component_name" "Installable"
            return 0
        else
            print_info "$component_name" "Unavailable"
            return 1
        fi
    fi
    
    print_info "$component_name" "Unable to detect"
    return 1
}

echo "Starting device client installation self-check..."
echo "Checking..."

# Global flag: network connectivity
NETWORK_AVAILABLE=false
if check_network_connectivity; then
    NETWORK_AVAILABLE=true
fi

# Network checks
echo ""
echo "--------------------------------"
echo "Network checks"
echo "--------------------------------"

if [ "$NETWORK_AVAILABLE" = true ]; then
    echo "Network connection is normal, starting network performance test..."

    echo "Testing download speed..." && network_download_speed=$(speed_test_avg download)
    print_info "Download speed" "$network_download_speed"

    echo "Testing upload speed..." && network_upload_speed=$(speed_test_avg upload)
    print_info "Upload speed" "$network_upload_speed"

    echo "Testing ping latency..." && network_ping=$(ping -c 4 "${ping_test_endpoint}" 2>/dev/null | tail -1 | awk '{print $4}' | cut -d '/' -f 2)
    if [ -z "$network_ping" ]; then
        network_ping="unable to measure"
    fi
    print_info "Ping latency" "$network_ping ms"

    echo "Checking HTTPS support..." && https_support=$(check_https_support)
    print_info "HTTPS support" "$https_support"
else
    echo "Network is not available, skipping network performance test"
    print_info "Network status" "No network connection"
    print_info "Download speed" "Skipped"
    print_info "Upload speed" "Skipped"
    print_info "Ping latency" "Skipped"
    print_info "HTTPS support" "Skipped"
fi

# Collect system information
system_os_name=$NAME
system_os_version=$VERSION
system_os_kernel=$(uname -r)
system_arch=$(uname -m)
system_os_type=$(uname -s)
system_total_memory=$(awk '/MemTotal/ { printf "%.3f", $2/1024 }' /proc/meminfo 2>/dev/null || echo "Unknown")
system_cpu_name=$(lscpu 2>/dev/null | sed -nr '/Model name/ s/.*:\s*(.*) @ .*/\1/p' || echo "Unknown")
system_cpu_num_processors=$(nproc 2>/dev/null || echo "Unknown")
system_gpus=$(lspci 2>/dev/null | grep -i "VGA" | awk 'BEGIN{FS=": "} {print $2}' || echo "Unknown")

# Get architecture and ROS info once to avoid duplication
arch_info=($(get_arch_info))
ARCH="${arch_info[0]}"
COLINK_ARCH="${arch_info[1]}"
ros_version=$(get_ros_version)
ubuntu_distro=$(get_ubuntu_distro)

echo ""
echo "--------------------------------"
echo "System information"
echo "--------------------------------"

print_info "System type" "$system_os_type"
print_info "Operating system" "$system_os_name $system_os_version"
print_info "Hardware architecture" "$system_arch"
print_info "System kernel" "$system_os_kernel"
print_info "Memory size" "$system_total_memory MB"
print_info "CPU model" "$system_cpu_name"
print_info "CPU number" "$system_cpu_num_processors"
print_info "GPU model" "$system_gpus"

echo ""
echo "--------------------------------"
echo "Software environment"
echo "--------------------------------"

print_info "ROS version" "$ros_version"

# Artifact configuration synced from installer script
ARTIFACT_BASE_URL="https://download.coscene.io"
COLINK_VERSION="1.0.4"
COLISTENER_VERSION="2.2.0-0"
COBRIDGE_VERSION="1.1.2-0"

# Determine OS type
OS=$(uname -s)
case "$OS" in
Linux)
  OS="linux"
  ;;
*)
  OS="unsupported"
  ;;
esac


echo ""
echo "--------------------------------"
echo "Installation package availability check"
echo "--------------------------------"

# Skip package checks if offline
if [ "$NETWORK_AVAILABLE" = false ]; then
    echo "Network is not available, skipping installation package availability check"
    print_info "coScout" "Skipped"
    print_info "coLink" "Skipped"
    print_info "coListener" "Skipped"
    print_info "coBridge" "Skipped"
    exit 0
fi

echo "Network connection is normal, starting installation package availability check..."

# Check availability of artifacts for each component
if [ "$OS" = "linux" ] && [ "$ARCH" != "unsupported" ]; then
    # 1. Check coScout (cos)
    LATEST_COS_URL="${ARTIFACT_BASE_URL}/coscout/v2/latest/${OS}-${ARCH}.gz"
    
    check_url_availability "$LATEST_COS_URL" "coScout"
    
    # 2. Check coLink
    if [ -n "$COLINK_ARCH" ]; then
        COLINK_DOWNLOAD_URL="${ARTIFACT_BASE_URL}/colink/v${COLINK_VERSION}/colink-${COLINK_ARCH}"
        check_url_availability "$COLINK_DOWNLOAD_URL" "coLink"
    else
        print_info "coLink" "Unsupported architecture"
    fi
    
    # 3. Check coListener and coBridge (requires ROS environment)
    if [ "$ros_version" != "unknown" ] && [ "$ros_version" != "unknown" ] && [ "$ubuntu_distro" != "unknown" ]; then
        # Check coListener
        COLISTENER_DEB_FILE="ros-${ros_version}-colistener_${COLISTENER_VERSION}${ubuntu_distro}_${ARCH}.deb"
        COLISTENER_DOWNLOAD_URL="https://apt.coscene.io/dists/${ubuntu_distro}/main/binary-${ARCH}/${COLISTENER_DEB_FILE}"
        check_url_availability "$COLISTENER_DOWNLOAD_URL" "coListener"
        
        # Check coBridge
        COBRIDGE_DEB_FILE="ros-${ros_version}-cobridge_${COBRIDGE_VERSION}${ubuntu_distro}_${ARCH}.deb"
        COBRIDGE_DOWNLOAD_URL="https://apt.coscene.io/dists/${ubuntu_distro}/main/binary-${ARCH}/${COBRIDGE_DEB_FILE}"
        check_url_availability "$COBRIDGE_DOWNLOAD_URL" "coBridge"
    else
        print_info "coListener" "Requires ROS environment"
        print_info "coBridge" "Requires ROS environment"
    fi
else
    print_info "coScout" "Unsupported system"
    print_info "coLink" "Unsupported system"
    print_info "coListener" "Unsupported system"
    print_info "coBridge" "Unsupported system"
fi

