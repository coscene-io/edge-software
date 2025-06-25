# edge-software

## 获取当前已安装的组件版本
```bash
./script/install.sh --version
```
   
如果系统内已经安装组件，会有以下输出：

```bash
# coScene Edge Software Package Versions
# Generated on: 2025-06-25 08:42:54 UTC

release_version: v1.0.0
assemblies:
  colink_version: 1.0.4
  cos_version: latest
  colistener_version: 2.0.0-0
  cobridge_version: 1.0.9-0
  trzsz_version: 1.1.6
```

   release_version： 整体版本号
   
   assemblies： 各个组件子版本号

如果未安装：
```bash
no version file was found.
```

## 安装 coscene 组件.

1. 下载repo中的 install.sh 文件，以及 [cos_binaries.tar.gz](/home/runner/work/edge-software/edge-software/cos_binaries.tar.gz) 软件包
2. 安装 coscene 组件
   ```bash
   ./install.sh --use_local=./cos_binaries.tar.gz \
       --mod="default" \
       --org_slug="coscene-lark" \
       --server_url="https://openapi.staging.coscene.cn" \
       --coLink_endpoint="https://coordinator.staging.coscene.cn/api" \
       --coLink_network="cf746e23-3210-4b8f-bdfa-fb771d1ac87c" \
       --sn_file="/home/just2004docker/Downloads/example.yaml" \
       --sn_field="serial_num" \
       --remove_config
   ```
   
   以上命令中的 parameter 可以在 coscene 网站的 “组织设置” -> “设备” 中获取。
   ![设备](./img/add-device.png)
   
   ![安装脚本](./img/install-cmd.png)
    
3. 使用安装命令进行安装
