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

# Get current user
CUR_USER=${USER:-$(whoami)}
if [ -z "$CUR_USER" ]; then
  echo "Unable to determine current user"
  exit 1
fi
echo "Current user: $CUR_USER"
CUR_USER_HOME=$(getent passwd "$CUR_USER" | cut -d: -f6)
if [ -z "$CUR_USER_HOME" ]; then
  echo "Unable to determine home directory for user $CUR_USER"
  exit 1
fi
echo "User home directory: $CUR_USER_HOME"

# Uninstall system-level coLink service
echo "Checking and uninstalling coLink service..."
if [[ "$(ps --no-headers -o comm 1 2>&1)" == "systemd" ]] && command -v systemctl 2>&1; then
    if systemctl is-active --quiet coLink 2>/dev/null; then
        echo "Found running coLink systemd service, stopping..."
        sudo systemctl stop coLink || echo "Failed to stop coLink service, continuing..."
    fi
    if systemctl is-enabled --quiet coLink 2>/dev/null; then
        echo "Disabling coLink systemd service..."
        sudo systemctl disable coLink || echo "Failed to disable coLink service, continuing..."
    fi
    if [ -f "/etc/systemd/system/coLink.service" ]; then
        echo "Removing coLink service file..."
        sudo rm -f /etc/systemd/system/coLink.service
        sudo systemctl daemon-reload
    fi

    if systemctl is-active --quiet colink 2>/dev/null; then
        echo "Found running colink systemd service, stopping..."
        sudo systemctl stop colink || echo "Failed to stop colink service, continuing..."
    fi
    if systemctl is-enabled --quiet colink 2>/dev/null; then
        echo "Disabling colink systemd service..."
        sudo systemctl disable colink || echo "Failed to disable colink service, continuing..."
    fi
    if [ -f "/etc/systemd/system/colink.service" ]; then
        echo "Removing colink service file..."
        sudo rm -f /etc/systemd/system/colink.service
        sudo systemctl daemon-reload
    fi
elif /sbin/init --version 2>&1 | grep -q upstart; then
    if initctl status coLink 2>/dev/null | grep -q "start/running"; then
        echo "Found running coLink upstart service, stopping..."
        sudo initctl stop coLink || echo "Failed to stop coLink service, continuing..."
    fi
    if [ -f "/etc/init/coLink.conf" ]; then
        echo "Removing coLink upstart config..."
        sudo rm -f /etc/init/coLink.conf
    fi

    if initctl status colink 2>/dev/null | grep -q "start/running"; then
        echo "Found running colink upstart service, stopping..."
        sudo initctl stop colink || echo "Failed to stop colink service, continuing..."
    fi
    if [ -f "/etc/init/colink.conf" ]; then
        echo "Removing colink upstart config..."
        sudo rm -f /etc/init/colink.conf
    fi
else
    echo "No coLink service found, skipping service uninstallation..."
fi

# Remove coLink related files
echo "Removing coLink binaries..."
[ -f "/usr/local/bin/coLink" ] && sudo rm -f /usr/local/bin/coLink
[ -f "/usr/local/bin/colink" ] && sudo rm -f /usr/local/bin/colink
[ -f "/usr/local/bin/trz" ] && sudo rm -f /usr/local/bin/trz
[ -f "/usr/local/bin/tsz" ] && sudo rm -f /usr/local/bin/tsz

# Remove coLink configuration files
echo "Removing coLink configuration files..."
[ -f "/etc/virmesh.key" ] && sudo rm -f /etc/virmesh.key
[ -f "/etc/virmesh.pub" ] && sudo rm -f /etc/virmesh.pub
[ -f "/etc/colink.key" ] && sudo rm -f /etc/colink.key
[ -f "/etc/colink.pub" ] && sudo rm -f /etc/colink.pub

# Uninstall system-level cos service (new installation method)
echo "Checking and uninstalling system-level cos service..."
if [[ "$(ps --no-headers -o comm 1 2>&1)" == "systemd" ]] && command -v systemctl 2>&1; then
    if systemctl is-active --quiet cos 2>/dev/null; then
        echo "Found running system-level cos systemd service, stopping..."
        sudo systemctl stop cos || echo "Failed to stop system-level cos service, continuing..."
    fi
    if systemctl is-enabled --quiet cos 2>/dev/null; then
        echo "Disabling system-level cos systemd service..."
        sudo systemctl disable cos || echo "Failed to disable system-level cos service, continuing..."
    fi
    if [ -f "/etc/systemd/system/cos.service" ]; then
        echo "Removing system-level cos service file..."
        sudo rm -f /etc/systemd/system/cos.service
        sudo systemctl daemon-reload
    fi
elif /sbin/init --version 2>&1 | grep -q upstart; then
    if initctl status cos 2>/dev/null | grep -q "start/running"; then
        echo "Found running system-level cos upstart service, stopping..."
        sudo initctl stop cos || echo "Failed to stop system-level cos service, continuing..."
    fi
    if [ -f "/etc/init/cos.conf" ]; then
        echo "Removing system-level cos upstart config..."
        sudo rm -f /etc/init/cos.conf
    fi
else
    echo "No system-level cos service found, skipping system-level service uninstallation..."
fi

# Uninstall system-level cos-slave service
echo "Checking and uninstalling system-level cos-slave service..."
if [[ "$(ps --no-headers -o comm 1 2>&1)" == "systemd" ]] && command -v systemctl 2>&1; then
    if systemctl is-active --quiet cos-slave 2>/dev/null; then
        echo "Found running system-level cos-slave systemd service, stopping..."
        sudo systemctl stop cos-slave || echo "Failed to stop system-level cos-slave service, continuing..."
    fi
    if systemctl is-enabled --quiet cos-slave 2>/dev/null; then
        echo "Disabling system-level cos-slave systemd service..."
        sudo systemctl disable cos-slave || echo "Failed to disable system-level cos-slave service, continuing..."
    fi
    if [ -f "/etc/systemd/system/cos-slave.service" ]; then
        echo "Removing system-level cos-slave service file..."
        sudo rm -f /etc/systemd/system/cos-slave.service
        sudo systemctl daemon-reload
    fi
else
    echo "No system-level cos-slave service found, skipping system-level service uninstallation..."
fi

# Uninstall user-level cos service (maintain backward compatibility)
echo "Checking and uninstalling user-level cos service..."
if [[ "$(ps --no-headers -o comm 1 2>&1)" == "systemd" ]] && command -v systemctl 2>&1; then
    XDG_RUNTIME_DIR="/run/user/$(id -u "${CUR_USER}")"
    if sudo -u "$CUR_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user is-active --quiet cos 2>/dev/null; then
        echo "Found running user-level cos systemd service, stopping..."
        sudo -u "$CUR_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user stop cos || echo "Failed to stop user-level cos service, continuing..."
    fi
    if sudo -u "$CUR_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user is-enabled --quiet cos 2>/dev/null; then
        echo "Disabling user-level cos systemd service..."
        sudo -u "$CUR_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user disable cos || echo "Failed to disable user-level cos service, continuing..."
    fi
    if [ -f "$CUR_USER_HOME/.config/systemd/user/cos.service" ]; then
        echo "Removing user-level cos service file..."
        sudo -u "$CUR_USER" rm -f "$CUR_USER_HOME/.config/systemd/user/cos.service"
        sudo -u "$CUR_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user daemon-reload
    fi
elif /sbin/init --version 2>&1 | grep -q upstart; then
    if initctl status cos 2>/dev/null | grep -q "start/running"; then
        echo "Found running user-level cos upstart service, stopping..."
        sudo initctl stop cos || echo "Failed to stop user-level cos service, continuing..."
    fi
    if [ -f "/etc/init/cos.conf" ]; then
        echo "Removing user-level cos upstart config..."
        sudo rm -f /etc/init/cos.conf
    fi
else
    echo "No user-level cos service found, skipping user-level service uninstallation..."
fi

# Remove cos related files and directories
echo "Removing cos related files and directories..."
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

echo "Checking coBridge..."
if dpkg -l | grep "ros-${ROS_VERSION}-cobridge" > /dev/null; then
    echo "Uninstalling coBridge..."
    sudo dpkg -r ros-${ROS_VERSION}-cobridge >/dev/null 2>&1 || echo "Failed to uninstall coBridge"
    echo "coBridge uninstalled"
else
    echo "coBridge not installed, skipping"
fi

echo "Checking coListener..."
if dpkg -l | grep "ros-${ROS_VERSION}-colistener" > /dev/null; then
    echo "Uninstalling coListener..."
    sudo dpkg -r ros-${ROS_VERSION}-colistener >/dev/null 2>&1 || echo "Failed to uninstall coListener"
    echo "coListener uninstalled"
else
    echo "coListener not installed, skipping"
fi

echo "Uninstallation completed 🎉"
exit 0


