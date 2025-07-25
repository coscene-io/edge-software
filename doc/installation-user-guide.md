# 安装脚本用户识别指南

## 概述

本文档详细说明了 coScene Edge Software 安装脚本在不同执行方式下的用户识别机制和行为表现。我们的安装脚本采用了智能的 **sudo 感知模式**，能够正确识别真实用户，确保软件安装到正确的位置。

## 脚本概述

项目提供两个主要的安装脚本：

- **`script/install.sh`** - 适用于 systemd 系统（现代 Linux 发行版）
- **`script/install-initd.sh`** - 适用于 upstart/initd 系统（传统 Linux 系统）

两个脚本都实现了相同的用户识别逻辑，确保一致的安装体验。

## 用户识别逻辑

脚本使用以下逻辑来识别目标用户：

```bash
# 脚本中的用户识别逻辑
if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  CUR_USER="$SUDO_USER"  # 使用 sudo 前的真实用户
  echo "Detected SUDO_USER: $CUR_USER, using it as target user"
else
  CUR_USER=${USER:-$(whoami)}  # 使用当前用户
fi
```

这种设计的优势：
- ✅ 即使通过 `sudo` 运行，也能识别真实用户
- ✅ 避免软件错误安装到 root 用户目录
- ✅ 提供更好的用户体验和容错性

## 执行方式对比表

| 执行方式 | 当前登录用户 | 执行权限 | 脚本识别用户 | 软件安装目录 | 配置文件位置 | 服务运行用户 | 推荐度 | 说明 |
|---------|-------------|----------|-------------|-------------|-------------|-------------|--------|------|
| `./install.sh` | alice | alice | alice | `/home/alice/.local` | `/home/alice/.config/cos` | alice | ⚠️ | 可能因权限不足失败 |
| `sudo ./install.sh` | alice | root | alice | `/home/alice/.local` | `/home/alice/.config/cos` | alice | ✅ **推荐** | 最佳使用方式 |
| `sudo su`<br/>`./install.sh` | alice→root | root | root | `/root/.local` | `/root/.config/cos` | root | ❌ | 软件安装到 root 用户 |
| `su -`<br/>`./install.sh` | alice→root | root | root | `/root/.local` | `/root/.config/cos` | root | ❌ | 软件安装到 root 用户 |
| root 直接运行<br/>`./install.sh` | root | root | root | `/root/.local` | `/root/.config/cos` | root | ⚠️ | 仅在真正需要时使用 |

### 图例说明

- ✅ **推荐** - 最佳实践，推荐使用
- ⚠️ **谨慎** - 可能遇到问题，需要注意
- ❌ **不推荐** - 会导致问题，应避免

## 详细场景分析

### ✅ 推荐方式：`sudo ./install.sh`

这是 **最佳实践** 和 **推荐使用方式**：

```bash
# 用户 alice 执行
alice@server:~$ sudo ./install.sh --org_slug=myorg --serial_num=123456

# 脚本输出
Detected SUDO_USER: alice, using it as target user
Current user: alice
User home directory: /home/alice

# 安装结果
✅ 软件安装到：/home/alice/.local/bin/cos
✅ 配置文件在：/home/alice/.config/cos/
✅ 日志文件在：/home/alice/.local/state/cos/logs/
✅ 服务运行用户：alice（通过 systemd 的 User= 指定）
```

**优势：**
- 脚本有足够权限执行系统级操作（安装二进制文件、创建服务等）
- 软件安装到正确的用户目录
- 用户可以正常使用安装的软件

### ⚠️ 直接运行（权限不足）

```bash
# 用户 alice 执行（权限不足）
alice@server:~$ ./install.sh --org_slug=myorg --serial_num=123456

# 可能的错误
❌ Permission denied: cannot write to /usr/local/bin/
❌ Permission denied: cannot create systemd service
❌ Permission denied: cannot install system packages
```

**问题：**
- 无法安装二进制文件到系统目录
- 无法创建系统级服务
- 无法安装系统依赖包

### ❌ 不推荐：切换到 root 用户后执行

```bash
# 错误示例 1：sudo su
alice@server:~$ sudo su
root@server:~# ./install.sh --org_slug=myorg --serial_num=123456

# 错误示例 2：su -
alice@server:~$ su -
root@server:~# ./install.sh --org_slug=myorg --serial_num=123456

# 问题结果
❌ SUDO_USER 变量为空或为 root
❌ 软件安装到 /root/ 目录
❌ alice 用户无法访问和使用软件
❌ 配置文件在 /root/.config/cos/
```

**为什么不推荐：**
- 丢失了原始用户信息
- 软件安装到 root 用户目录，普通用户无法使用
- 违背了最小权限原则

## 系统服务行为对比

### systemd 系统 (`install.sh`)

| 执行方式 | 服务类型 | 服务文件位置 | 服务运行用户 | 启动方式 | 自动启动 |
|---------|----------|-------------|-------------|----------|----------|
| `sudo ./install.sh` | 系统级服务 | `/etc/systemd/system/cos.service` | alice | `systemctl start cos` | ✅ |
| root 用户执行 | 系统级服务 | `/etc/systemd/system/cos.service` | root | `systemctl start cos` | ✅ |

**systemd 服务配置示例：**
```ini
[Unit]
Description=coScout: Data Collector by coScene
Documentation=https://github.com/coscene-io/coScout

[Service]
Type=simple
User=alice
Group=alice
WorkingDirectory=/home/alice/.local/state/cos
ExecStart=/home/alice/.local/bin/cos daemon --config-path=/home/alice/.config/cos/config.yaml

[Install]
WantedBy=multi-user.target
```

### upstart 系统 (`install-initd.sh`)

| 执行方式 | 服务类型 | 服务文件位置 | 服务运行用户 | 启动方式 | 自动启动 |
|---------|----------|-------------|-------------|----------|----------|
| `sudo ./install-initd.sh` | 系统级服务 | `/etc/init/cos.conf` | alice | `initctl start cos` | ✅ |
| root 用户执行 | 系统级服务 | `/etc/init/cos.conf` | root | `initctl start cos` | ✅ |

## 可选组件安装

脚本支持可选组件的灵活安装：

```bash
# 安装包含所有组件
sudo ./install.sh \
  --org_slug=myorg \
  --serial_num=123456 \
  --install_cobridge \
  --install_colistener

# 只安装特定组件
sudo ./install.sh \
  --org_slug=myorg \
  --serial_num=123456 \
  --install_cobridge

# 基础安装（不安装可选组件）
sudo ./install.sh \
  --org_slug=myorg \
  --serial_num=123456
```

## 自动系统检测和错误处理

脚本会自动检测系统类型并给出正确的使用建议：

### systemd 系统检测

```bash
# 在 systemd 系统上运行 upstart 脚本
alice@server:~$ sudo ./install-initd.sh
❌ ERROR: This script is designed for initd/upstart systems only.
❌ ERROR: For systemd systems, please use install.sh instead.
```

### upstart 系统检测

```bash
# 在 upstart 系统上运行 systemd 脚本  
alice@server:~$ sudo ./install.sh
❌ ERROR: This script requires systemd. For upstart systems, please use install-initd.sh instead.
```

## 环境变量说明

脚本依赖以下环境变量进行用户识别：

| 变量 | 说明 | 来源 | 示例 |
|------|------|------|------|
| `SUDO_USER` | sudo 执行前的原始用户 | sudo 命令自动设置 | `alice` |
| `USER` | 当前用户环境变量 | 系统环境 | `alice` 或 `root` |
| `whoami` | 当前有效用户 | 系统命令 | `alice` 或 `root` |

## 故障排查

### 常见问题及解决方案

#### 1. 软件安装到了 root 用户目录

**症状：**
```bash
alice@server:~$ cos --version
bash: cos: command not found
```

**原因：** 使用了 `sudo su` 或 `su -` 切换到 root 后执行安装

**解决方案：**
```bash
# 重新以正确方式安装
alice@server:~$ sudo ./install.sh --org_slug=myorg --serial_num=123456
```

#### 2. 权限被拒绝错误

**症状：**
```bash
alice@server:~$ ./install.sh
Permission denied: cannot write to /usr/local/bin/
```

**原因：** 直接运行脚本而没有使用 sudo

**解决方案：**
```bash
# 使用 sudo 运行
alice@server:~$ sudo ./install.sh --org_slug=myorg --serial_num=123456
```

#### 3. 系统类型检测错误

**症状：**
```bash
ERROR: This script requires systemd. For upstart systems, please use install-initd.sh instead.
```

**解决方案：** 使用正确的脚本文件

## 最佳实践建议

### ✅ 推荐做法

1. **始终使用 `sudo ./install.sh`** - 这是最安全和正确的方式
2. **让脚本自动检测系统类型** - 会自动提示使用正确的脚本
3. **使用具体的参数** - 明确指定组织、序列号等必要信息
4. **验证安装结果** - 检查软件是否安装到正确位置

### ❌ 避免做法

1. **不要切换到 root 用户后运行** - 会导致软件安装到错误位置
2. **不要忽略权限错误** - 直接运行可能导致部分安装失败
3. **不要混用不同系统的脚本** - 可能导致服务无法正常工作

### 🔍 验证安装

安装完成后，可以通过以下方式验证：

```bash
# 检查软件是否正确安装
alice@server:~$ cos --version

# 检查配置文件
alice@server:~$ ls -la ~/.config/cos/

# 检查服务状态（systemd）
alice@server:~$ systemctl status cos

# 检查服务状态（upstart）
alice@server:~$ sudo initctl status cos

# 检查日志
alice@server:~$ tail -f ~/.local/state/cos/logs/cos.log
```

## 总结

通过采用 sudo 感知的用户识别机制，我们的安装脚本能够：

- ✅ **智能识别真实用户** - 即使通过 sudo 运行也能正确识别
- ✅ **避免常见错误** - 防止软件安装到错误位置
- ✅ **提供一致体验** - 不同系统使用相同的逻辑
- ✅ **自动错误检测** - 提供清晰的错误提示和解决建议

**记住：始终使用 `sudo ./install.sh` 是最佳实践！** 