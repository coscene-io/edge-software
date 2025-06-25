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

[参考链接](https://docs.coscene.cn/docs/device/create-device#%E4%BD%BF%E7%94%A8%E7%A6%BB%E7%BA%BF%E5%AE%89%E8%A3%85%E5%8C%85%E6%B7%BB%E5%8A%A0)


   