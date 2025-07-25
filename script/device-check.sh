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
upload_speed_test_endpoint=""
download_speed_test_endpoint="https://coscene-download.oss-cn-hangzhou.aliyuncs.com/cosbinary/tar/latest/cos_binaries.tar.gz"

if [ -f /etc/os-release ]; then
    source /etc/os-release
elif [ -f /usr/lib/os-release ]; then
    source /usr/lib/os-release
else
    NAME=unknown
    VERSION=unknown
fi

get_ros_version() {
    if [ -d /opt/ros ] && [ "$(find /opt/ros -maxdepth 1 -type d | wc -l)" -gt 1 ]; then
        echo $(ls -d /opt/ros/*/ | cut -d'/' -f4)
    else
        echo "Not found"
    fi
}

upload_speed_test() {
    pushd $(mktemp -d) >/dev/null
    local bs
    if [[ "$OSTYPE" == "darwin"* ]]; then
        bs=2m
    else
        bs=2M
    fi
    dd if=/dev/urandom of=speedtest bs=${bs} count=1 2>/dev/null
    wget --header="Content-type: multipart/form-data" --post-file speedtest ${upload_speed_test_endpoint} -O /dev/null 2>&1 | grep -o "[0-9.]\+ [KM]*B/s"
    rm speedtest
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
    local num_tests=3  # 减少测试次数以提高速度
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

echo "开始进行刻行时空设备客户端安装自检..."
echo "正在检查中..."

# 网络检查
echo ""
echo "--------------------------------"
echo "网络检查"
echo "--------------------------------"

echo "测试下载速度..." && network_download_speed=$(speed_test_avg download)
echo "下载速度  | $network_download_speed"

# echo "Measuring upload speed..." && network_upload_speed=$(speed_test_avg upload)
echo "测试 ping 延迟..." && network_ping=$(ping -c 4 "${ping_test_endpoint}" 2>/dev/null | tail -1 | awk '{print $4}' | cut -d '/' -f 2)
if [ -z "$network_ping" ]; then
    network_ping="无法测量"
fi
echo "ping 延迟 | $network_ping ms"

# System info
system_os_name=$NAME
system_os_version=$VERSION
system_os_kernel=$(uname -r)
system_arch=$(uname -m)
system_os_type=$(uname -s)
system_total_memory=$(awk '/MemTotal/ { printf "%.3f", $2/1024 }' /proc/meminfo 2>/dev/null || echo "Unknown") # mb
system_cpu_name=$(lscpu 2>/dev/null | sed -nr '/Model name/ s/.*:\s*(.*) @ .*/\1/p' || echo "Unknown")
system_cpu_num_processors=$(nproc 2>/dev/null || echo "Unknown")


# GPU info
system_gpus=$(lspci 2>/dev/null | grep -i "VGA" | awk 'BEGIN{FS=": "} {print $2}' || echo "Unknown")

echo ""
echo "--------------------------------"
echo "系统信息"
echo "--------------------------------"

echo "系统类型 | $system_os_type"
echo "操作系统 | $system_os_name $system_os_version"
echo "硬件架构 | $system_arch"
echo "系统内核 | $system_os_kernel"

echo "内存大小 | $system_total_memory mb"
echo "CPU型号  | $system_cpu_name"
echo "CPU数量  | $system_cpu_num_processors"
echo "GPU型号  | $system_gpus" 

ros_version=$(get_ros_version)

echo ""
echo "--------------------------------"
echo "软件环境"
echo "--------------------------------"

echo "ROS 版本 | $ros_version"
