#!/usr/bin/env bash
# Copyright 2024 coScene
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

# 获取当前用户
CUR_USER=${USER:-$(whoami)}
if [ -z "$CUR_USER" ]; then
  echo "无法获取当前用户"
  exit 1
fi
echo "当前用户: $CUR_USER"
CUR_USER_HOME=$(getent passwd "$CUR_USER" | cut -d: -f6)
if [ -z "$CUR_USER_HOME" ]; then
  echo "无法获取用户 $CUR_USER 的主目录"
  exit 1
fi
echo "用户主目录: $CUR_USER_HOME"

# 卸载系统级的 coLink 服务
echo "检查并卸载 coLink 服务..."
if [[ "$(ps --no-headers -o comm 1 2>&1)" == "systemd" ]] && command -v systemctl 2>&1; then
    if systemctl is-active --quiet coLink 2>/dev/null; then
        echo "发现运行中的 coLink systemd 服务，正在停止..."
        sudo systemctl stop coLink || echo "停止 coLink 服务失败，继续执行..."
    fi
    if systemctl is-enabled --quiet coLink 2>/dev/null; then
        echo "正在禁用 coLink systemd 服务..."
        sudo systemctl disable coLink || echo "禁用 coLink 服务失败，继续执行..."
    fi
    if [ -f "/etc/systemd/system/coLink.service" ]; then
        echo "正在删除 coLink 服务文件..."
        sudo rm -f /etc/systemd/system/coLink.service
        sudo systemctl daemon-reload
    fi

    if systemctl is-active --quiet colink 2>/dev/null; then
        echo "发现运行中的 colink systemd 服务，正在停止..."
        sudo systemctl stop colink || echo "停止 colink 服务失败，继续执行..."
    fi
    if systemctl is-enabled --quiet colink 2>/dev/null; then
        echo "正在禁用 colink systemd 服务..."
        sudo systemctl disable colink || echo "禁用 colink 服务失败，继续执行..."
    fi
    if [ -f "/etc/systemd/system/colink.service" ]; then
        echo "正在删除 colink 服务文件..."
        sudo rm -f /etc/systemd/system/colink.service
        sudo systemctl daemon-reload
    fi
elif /sbin/init --version 2>&1 | grep -q upstart; then
    if initctl status coLink 2>/dev/null | grep -q "start/running"; then
        echo "发现运行中的 coLink upstart 服务，正在停止..."
        sudo initctl stop coLink || echo "停止 coLink 服务失败，继续执行..."
    fi
    if [ -f "/etc/init/coLink.conf" ]; then
        echo "正在删除 coLink upstart 配置..."
        sudo rm -f /etc/init/coLink.conf
    fi

    if initctl status colink 2>/dev/null | grep -q "start/running"; then
        echo "发现运行中的 colink upstart 服务，正在停止..."
        sudo initctl stop colink || echo "停止 colink 服务失败，继续执行..."
    fi
    if [ -f "/etc/init/colink.conf" ]; then
        echo "正在删除 colink upstart 配置..."
        sudo rm -f /etc/init/colink.conf
    fi
else
    echo "未发现 coLink 服务，跳过服务卸载..."
fi

# 删除 coLink 相关文件
echo "正在删除 coLink 二进制文件..."
[ -f "/usr/local/bin/coLink" ] && sudo rm -f /usr/local/bin/coLink
[ -f "/usr/local/bin/colink" ] && sudo rm -f /usr/local/bin/colink
[ -f "/usr/local/bin/trz" ] && sudo rm -f /usr/local/bin/trz
[ -f "/usr/local/bin/tsz" ] && sudo rm -f /usr/local/bin/tsz

# 删除 coLink 相关配置信息
echo "正在删除 coLink 配置文件..."
[ -f "/etc/virmesh.key" ] && sudo rm -f /etc/virmesh.key
[ -f "/etc/virmesh.pub" ] && sudo rm -f /etc/virmesh.pub
[ -f "/etc/colink.key" ] && sudo rm -f /etc/colink.key
[ -f "/etc/colink.pub" ] && sudo rm -f /etc/colink.pub

# 卸载系统级的 cos 服务（新的安装方式）
echo "检查并卸载系统级 cos 服务..."
if [[ "$(ps --no-headers -o comm 1 2>&1)" == "systemd" ]] && command -v systemctl 2>&1; then
    if systemctl is-active --quiet cos 2>/dev/null; then
        echo "发现运行中的系统级 cos systemd 服务，正在停止..."
        sudo systemctl stop cos || echo "停止系统级 cos 服务失败，继续执行..."
    fi
    if systemctl is-enabled --quiet cos 2>/dev/null; then
        echo "正在禁用系统级 cos systemd 服务..."
        sudo systemctl disable cos || echo "禁用系统级 cos 服务失败，继续执行..."
    fi
    if [ -f "/etc/systemd/system/cos.service" ]; then
        echo "正在删除系统级 cos 服务文件..."
        sudo rm -f /etc/systemd/system/cos.service
        sudo systemctl daemon-reload
    fi
elif /sbin/init --version 2>&1 | grep -q upstart; then
    if initctl status cos 2>/dev/null | grep -q "start/running"; then
        echo "发现运行中的系统级 cos upstart 服务，正在停止..."
        sudo initctl stop cos || echo "停止系统级 cos 服务失败，继续执行..."
    fi
    if [ -f "/etc/init/cos.conf" ]; then
        echo "正在删除系统级 cos upstart 配置..."
        sudo rm -f /etc/init/cos.conf
    fi
else
    echo "未发现系统级 cos 服务，跳过系统级服务卸载..."
fi

# 卸载用户态的 cos 服务（保持历史兼容性）
echo "检查并卸载用户级 cos 服务..."
if [[ "$(ps --no-headers -o comm 1 2>&1)" == "systemd" ]] && command -v systemctl 2>&1; then
    XDG_RUNTIME_DIR="/run/user/$(id -u "${CUR_USER}")"
    if sudo -u "$CUR_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user is-active --quiet cos 2>/dev/null; then
        echo "发现运行中的用户级 cos systemd 服务，正在停止..."
        sudo -u "$CUR_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user stop cos || echo "停止用户级 cos 服务失败，继续执行..."
    fi
    if sudo -u "$CUR_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user is-enabled --quiet cos 2>/dev/null; then
        echo "正在禁用用户级 cos systemd 服务..."
        sudo -u "$CUR_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user disable cos || echo "禁用用户级 cos 服务失败，继续执行..."
    fi
    if [ -f "$CUR_USER_HOME/.config/systemd/user/cos.service" ]; then
        echo "正在删除用户级 cos 服务文件..."
        sudo -u "$CUR_USER" rm -f "$CUR_USER_HOME/.config/systemd/user/cos.service"
        sudo -u "$CUR_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user daemon-reload
    fi
elif /sbin/init --version 2>&1 | grep -q upstart; then
    if initctl status cos 2>/dev/null | grep -q "start/running"; then
        echo "发现运行中的用户级 cos upstart 服务，正在停止..."
        sudo initctl stop cos || echo "停止用户级 cos 服务失败，继续执行..."
    fi
    if [ -f "/etc/init/cos.conf" ]; then
        echo "正在删除用户级 cos upstart 配置..."
        sudo rm -f /etc/init/cos.conf
    fi
else
    echo "未发现用户级 cos 服务，跳过用户级服务卸载..."
fi

# 删除 cos 相关文件和目录
echo "正在删除 cos 相关文件和目录..."
[ -d "$CUR_USER_HOME/.local/bin" ] && sudo -u "$CUR_USER" rm -rf "$CUR_USER_HOME/.local/bin/cos"
[ -d "$CUR_USER_HOME/.config/cos" ] && sudo -u "$CUR_USER" rm -rf "$CUR_USER_HOME/.config/cos"
[ -d "$CUR_USER_HOME/.local/state/cos" ] && sudo -u "$CUR_USER" rm -rf "$CUR_USER_HOME/.local/state/cos"
[ -d "$CUR_USER_HOME/.cache/coscene" ] && sudo -u "$CUR_USER" rm -rf "$CUR_USER_HOME/.cache/coscene"
[ -d "$CUR_USER_HOME/.cache/cos" ] && sudo -u "$CUR_USER" rm -rf "$CUR_USER_HOME/.cache/cos"

get_ros_distro() {
  if [[ -n "${ROS_DISTRO:-}" ]]; then
      echo "$ROS_DISTRO"
  else
      # Try to find ROS installation in /opt/ros
      for ros_path in /opt/ros/*; do
          if [[ -d "$ros_path" ]]; then
              echo "$(basename "$ros_path")"
              return 0
          fi
      done
      echo "unknown"
  fi
}

ROS_VERSION=$(get_ros_distro)

echo "正在检查 coBridge..."
if dpkg -l | grep "ros-${ROS_VERSION}-cobridge" > /dev/null; then
    echo "正在卸载 coBridge..."
    sudo dpkg -r ros-${ROS_VERSION}-cobridge >/dev/null 2>&1 || echo "卸载 coBridge 失败"
    echo "coBridge 卸载完成"
else
    echo "coBridge 未安装，跳过"
fi

echo "正在检查 coListener..."
if dpkg -l | grep "ros-${ROS_VERSION}-colistener" > /dev/null; then
    echo "正在卸载 coListener..."
    sudo dpkg -r ros-${ROS_VERSION}-colistener >/dev/null 2>&1 || echo "卸载 coListener 失败"
    echo "coListener 卸载完成"
else
    echo "coListener 未安装，跳过"
fi

echo "正在检查 coEncoder..."
if dpkg -l | grep "ros-${ROS_VERSION}-coencoder" > /dev/null; then
    echo "正在卸载 coEncoder..."
    sudo dpkg -r ros-${ROS_VERSION}-coencoder >/dev/null 2>&1 || echo "卸载 coEncoder 失败"
    echo "coEncoder 卸载完成"
else
    echo "coEncoder 未安装，跳过"
fi

echo "卸载完成 🎉"
exit 0
