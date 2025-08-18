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

ping_test_endpoint="openapi.coscene.cn"
upload_speed_test_endpoint="https://storage-cn-hangzhou.coscene.cn/v1/speed-test"
download_speed_test_endpoint="https://coscene-download.oss-cn-hangzhou.aliyuncs.com/cosbinary/tar/latest/cos_binaries.tar.gz"

if [ -f /etc/os-release ]; then
    source /etc/os-release
elif [ -f /usr/lib/os-release ]; then
    source /usr/lib/os-release
else
    NAME=unknown
    VERSION=unknown
fi

# 统一的ROS版本检测函数
get_ros_version() {
    if [[ -n "${ROS_DISTRO:-}" ]]; then
        echo "$ROS_DISTRO"
    elif [ -d /opt/ros ] && [ "$(find /opt/ros -maxdepth 1 -type d | wc -l)" -gt 1 ]; then
        echo $(ls -d /opt/ros/*/ | cut -d'/' -f4)
    else
        echo "未安装"
    fi
}

# 统一的Ubuntu发行版检测函数
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

# 统一的架构信息获取函数
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

# 格式化输出函数，确保对齐
print_info() {
    local label="$1"
    local value="$2"
    local width=12  # 标签宽度
    
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
    if command -v curl >/dev/null 2>&1; then
        # 使用 curl 进行上传并直接读取上传速率（bytes/s）
        local bytes_per_sec
        bytes_per_sec=$(curl -s -o /dev/null -w "%{speed_upload}" -X POST -F "file=@speedtest" "${upload_speed_test_endpoint}" 2>/dev/null || echo "")
        if [ -n "$bytes_per_sec" ] && [ "$bytes_per_sec" != "0" ]; then
            if awk -v s="$bytes_per_sec" 'BEGIN{exit !(s>=1048576)}'; then
                # >= 1 MiB/s -> 输出 M/s
                local mps
                mps=$(awk -v s="$bytes_per_sec" 'BEGIN{printf "%.1f", s/1048576}')
                echo "${mps}M/s"
            else
                # < 1 MiB/s -> 输出 K/s
                local kps
                kps=$(awk -v s="$bytes_per_sec" 'BEGIN{printf "%.1f", s/1024}')
                echo "${kps}K/s"
            fi
        fi
    elif command -v wget >/dev/null 2>&1; then
        # 作为降级方案尝试使用 wget，但 wget 不易获取上传速率，可能仍然无法解析
        wget --no-check-certificate --method=POST --body-file=speedtest "${upload_speed_test_endpoint}" -O /dev/null 2>&1 | grep -o "[0-9.]\+ [KM]*B/s"
    fi
    rm -f speedtest
    popd >/dev/null
}

download_speed_test() {
    # 使用 wget 下载文件并解析速度，支持多种输出格式
    local output=$(wget --progress=dot:mega -O /dev/null $download_speed_test_endpoint 2>&1)
    local speed=""
    
    # 尝试不同的解析方式
    # 方式1: 匹配 "100.5K/s" 格式
    speed=$(echo "$output" | grep -o "[0-9.]\+[KM]/s" | tail -1)
    if [ -n "$speed" ]; then
        echo "$speed"
        return
    fi
    
    # 方式2: 匹配 "100.5 KB/s" 格式  
    speed=$(echo "$output" | grep -o "[0-9.]\+ [KM]*B/s" | tail -1)
    if [ -n "$speed" ]; then
        echo "$speed"
        return
    fi
    
    # 方式3: 使用 curl 作为备选方案
    if command -v curl &> /dev/null; then
        speed=$(curl -o /dev/null -s -w "%{speed_download}" $download_speed_test_endpoint 2>/dev/null)
        if [ -n "$speed" ] && [ "$speed" != "0" ]; then
            # 转换 bytes/s 到 KB/s
            speed_kb=$(echo "$speed" | awk '{printf "%.1f", $1/1024}')
            echo "${speed_kb}K/s"
            return
        fi
    fi
    
    # 如果都失败了，返回默认值
    echo "0K/s"
}

speed_test_avg() {
    local num_tests=2  # 减少测试次数以提高速度
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
        
        # 检查是否获取到有效的速度值
        if [ -z "$speed_test" ] || [[ "$speed_test" == "0"* ]]; then
            continue
        fi
        
        local number=$(echo $speed_test | grep -o "[0-9.]\+" | head -1)
        local units=$(echo $speed_test | grep -o "[KM]*" | head -1)
        
        # 检查数值是否有效
        if [ -z "$number" ] || [ "$number" = "0" ]; then
            continue
        fi
        
        # 直接转换为 Mbit/s，避免中间转换误差
        local mbits=0
        if [[ "$units" = "M" ]]; then
            # MB/s 转 Mbit/s：乘以 8
            mbits=$(echo $number | awk '{printf "%.2f", $1 * 8}')
        else
            # KB/s 转 Mbit/s：除以 125 (因为 1000 KB/s ÷ 8 = 125 KB/s = 1 Mbit/s)
            mbits=$(echo $number | awk '{printf "%.2f", $1 / 125}')
        fi
        
        total=$(echo $mbits $total | awk '{print $1 + $2}')
        valid_tests=$((valid_tests + 1))
    done
    
    # 如果没有有效测试，返回默认值
    if [ $valid_tests -eq 0 ]; then
        echo "无法测量"
        return
    fi
    
    # 计算平均值
    local avg_mbits=$(echo $total $valid_tests | awk '{printf "%.1f", $1 / $2}')
    echo "${avg_mbits} Mbit/s"
}

# 检查网络连通性函数
check_network_connectivity() {
    # 方法1: 尝试ping通用DNS服务器
    if ping -c 1 -W 3 223.5.5.5 >/dev/null 2>&1; then
        return 0
    fi
    
    # 方法2: 尝试ping目标域名
    if ping -c 1 -W 3 "${ping_test_endpoint}" >/dev/null 2>&1; then
        return 0
    fi
    
    # 方法3: 尝试使用curl检查网络
    if command -v curl &> /dev/null; then
        if curl -s --max-time 5 --head "http://www.baidu.com" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    return 1
}

# 添加HTTPS支持检查函数
check_https_support() {
    local test_url="https://${ping_test_endpoint}"
    
    # 方法1: 使用curl检查HTTPS支持
    if command -v curl &> /dev/null; then
        if curl -s --max-time 10 --head "$test_url" >/dev/null 2>&1; then
            echo "支持"
            return
        fi
    fi
    
    # 方法2: 使用wget检查HTTPS支持
    if command -v wget &> /dev/null; then
        if wget --timeout=10 --spider --quiet "$test_url" >/dev/null 2>&1; then
            echo "支持"
            return
        fi
    fi
    
    # 方法3: 使用openssl检查SSL/TLS连接
    if command -v openssl &> /dev/null; then
        if echo | timeout 10 openssl s_client -connect "${ping_test_endpoint}:443" >/dev/null 2>&1; then
            echo "支持"
            return
        fi
    fi
    
    echo "不支持"
}

# 检查URL是否可访问的函数
check_url_availability() {
    local url="$1"
    local component_name="$2"
    
    # 使用 curl 检查 HTTP 状态码
    if command -v curl &> /dev/null; then
        local status_code=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 --head "$url" 2>/dev/null)
        if [ "$status_code" = "200" ]; then
            print_info "$component_name" "可安装"
            return 0
        elif [ "$status_code" = "404" ]; then
            print_info "$component_name" "不可用 (404)"
            return 1
        elif [ -n "$status_code" ] && [ "$status_code" != "000" ]; then
            print_info "$component_name" "异常 (HTTP $status_code)"
            return 1
        fi
    fi
    
    # 使用 wget 作为备选方案
    if command -v wget &> /dev/null; then
        if wget --timeout=10 --spider --quiet "$url" >/dev/null 2>&1; then
            print_info "$component_name" "可安装"
            return 0
        else
            print_info "$component_name" "不可用"
            return 1
        fi
    fi
    
    print_info "$component_name" "无法检测"
    return 1
}

echo "开始进行刻行时空设备客户端安装自检..."
echo "正在检查中..."

# 全局变量：检查网络连通性
NETWORK_AVAILABLE=false
if check_network_connectivity; then
    NETWORK_AVAILABLE=true
fi

# 网络检查
echo ""
echo "--------------------------------"
echo "网络检查"
echo "--------------------------------"

if [ "$NETWORK_AVAILABLE" = true ]; then
    echo "网络连接正常，开始网络性能测试..."

    echo "测试下载速度..." && network_download_speed=$(speed_test_avg download)
    print_info "下载速度" "$network_download_speed"

    echo "测试上传速度..." && network_upload_speed=$(speed_test_avg upload)
    print_info "上传速度" "$network_upload_speed"

    echo "测试 ping 延迟..." && network_ping=$(ping -c 4 "${ping_test_endpoint}" 2>/dev/null | tail -1 | awk '{print $4}' | cut -d '/' -f 2)
    if [ -z "$network_ping" ]; then
        network_ping="无法测量"
    fi
    print_info "ping 延迟" "$network_ping ms"

    echo "检查HTTPS支持..." && https_support=$(check_https_support)
    print_info "HTTPS支持" "$https_support"
else
    echo "检测到网络不可用，跳过网络性能测试"
    print_info "网络状态" "无网络连接"
    print_info "下载速度" "跳过"
    print_info "上传速度" "跳过"
    print_info "ping 延迟" "跳过"
    print_info "HTTPS支持" "跳过"
fi

# 收集系统信息
system_os_name=$NAME
system_os_version=$VERSION
system_os_kernel=$(uname -r)
system_arch=$(uname -m)
system_os_type=$(uname -s)
system_total_memory=$(awk '/MemTotal/ { printf "%.3f", $2/1024 }' /proc/meminfo 2>/dev/null || echo "Unknown")
system_cpu_name=$(lscpu 2>/dev/null | sed -nr '/Model name/ s/.*:\s*(.*) @ .*/\1/p' || echo "Unknown")
system_cpu_num_processors=$(nproc 2>/dev/null || echo "Unknown")
system_gpus=$(lspci 2>/dev/null | grep -i "VGA" | awk 'BEGIN{FS=": "} {print $2}' || echo "Unknown")

# 获取架构和ROS信息（一次性获取，避免重复）
arch_info=($(get_arch_info))
ARCH="${arch_info[0]}"
COLINK_ARCH="${arch_info[1]}"
ros_version=$(get_ros_version)
ubuntu_distro=$(get_ubuntu_distro)

echo ""
echo "--------------------------------"
echo "系统信息"
echo "--------------------------------"

print_info "系统类型" "$system_os_type"
print_info "操作系统" "$system_os_name $system_os_version"
print_info "硬件架构" "$system_arch"
print_info "系统内核" "$system_os_kernel"
print_info "内存大小" "$system_total_memory MB"
print_info "CPU型号" "$system_cpu_name"
print_info "CPU数量" "$system_cpu_num_processors"
print_info "GPU型号" "$system_gpus"

echo ""
echo "--------------------------------"
echo "软件环境"
echo "--------------------------------"

print_info "ROS 版本" "$ros_version"

# 从安装脚本同步的配置信息
ARTIFACT_BASE_URL="https://download.coscene.cn"
COLINK_VERSION="1.0.4"
COLISTENER_VERSION="2.2.0-0"
COBRIDGE_VERSION="1.1.2-0"

# 确定操作系统类型
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
echo "安装包可用性检查"
echo "--------------------------------"

# 如果无网络则跳过安装包检查
if [ "$NETWORK_AVAILABLE" = false ]; then
    echo "检测到网络不可用，跳过安装包可用性检查"
    print_info "coScout" "跳过检查"
    print_info "coLink" "跳过检查"
    print_info "coListener" "跳过检查"
    print_info "coBridge" "跳过检查"
    exit 0
fi

echo "网络连接正常，开始检查安装包可用性..."

# 检查各个组件的安装包可用性
if [ "$OS" = "linux" ] && [ "$ARCH" != "unsupported" ]; then
    # 1. 检查 coScout (cos)
    LATEST_COS_URL="${ARTIFACT_BASE_URL}/coscout/v2/latest/${OS}-${ARCH}.gz"
    
    check_url_availability "$LATEST_COS_URL" "coScout"
    
    # 2. 检查 coLink
    if [ -n "$COLINK_ARCH" ]; then
        COLINK_DOWNLOAD_URL="${ARTIFACT_BASE_URL}/colink/v${COLINK_VERSION}/colink-${COLINK_ARCH}"
        check_url_availability "$COLINK_DOWNLOAD_URL" "coLink"
    else
        print_info "coLink" "架构不支持"
    fi
    
    # 3. 检查 coListener 和 coBridge (需要ROS环境)
    if [ "$ros_version" != "unknown" ] && [ "$ros_version" != "未安装" ] && [ "$ubuntu_distro" != "unknown" ]; then
        # 检查 coListener
        COLISTENER_DEB_FILE="ros-${ros_version}-colistener_${COLISTENER_VERSION}${ubuntu_distro}_${ARCH}.deb"
        COLISTENER_DOWNLOAD_URL="https://apt.coscene.cn/dists/${ubuntu_distro}/main/binary-${ARCH}/${COLISTENER_DEB_FILE}"
        check_url_availability "$COLISTENER_DOWNLOAD_URL" "coListener"
        
        # 检查 coBridge
        COBRIDGE_DEB_FILE="ros-${ros_version}-cobridge_${COBRIDGE_VERSION}${ubuntu_distro}_${ARCH}.deb"
        COBRIDGE_DOWNLOAD_URL="https://apt.coscene.cn/dists/${ubuntu_distro}/main/binary-${ARCH}/${COBRIDGE_DEB_FILE}"
        check_url_availability "$COBRIDGE_DOWNLOAD_URL" "coBridge"
    else
        print_info "coListener" "需要ROS环境"
        print_info "coBridge" "需要ROS环境"
    fi
else
    print_info "coScout" "系统不支持"
    print_info "coLink" "系统不支持"
    print_info "coListener" "系统不支持"
    print_info "coBridge" "系统不支持"
fi
