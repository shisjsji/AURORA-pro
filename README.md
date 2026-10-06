# AURORA-pro

基于设备原厂 Dolby XML 的双扬声器风格化调音模块，面向 Magisk / KernelSU。

> 作者：**凌乱的风**
> 当前版本：**v5.7.0 修复版**

AURORA-pro 以设备实际存在的 OEM XML 为基底，只对双扬声器路线做增量调音，并保留耳机、蓝牙、USB 等外接路线的原厂节点。项目名称和预设名称只表示听感灵感，不代表任何品牌的官方 EQ 或合作关系。

## 主要特性

- 动态识别设备 Dolby XML 与 Profile ID，优先使用 `/odm/etc/dolby/dax-default.xml`，`/vendor` 作为后备。
- 只修改双扬声器和选定 Profile 的 speaker endpoint，避免覆盖外接路线。
- 支持自然动态、影院包围、音乐饱满、人声清晰、哈曼暖声灵感、柏林自然灵感、北欧温暖、北欧明亮、动感冲击等听感预设。
- 修复布尔开关、低频上限、属性回退、事务锁、音频服务刷新和低功耗逻辑。
- WebUI 使用中文移动端分组界面，支持预设、十段 EQ、空间化、输出路线、安全模式和原厂对比。
- 应用前快照相关音频属性；安全模式和卸载时恢复原值。
- 运行时状态区分 `XML_BOUND`、`ACTIVE`、`STOCK`、`DEGRADED`，便于排查设备差异。

## 安装

1. 下载 [AURORA-pro v5.7.0 修复版](release/AURORA-pro_v5.7.0_修复版.zip)。
2. 在 Magisk 或 KernelSU 中安装 ZIP。
3. 重启设备。
4. 打开模块 WebUI，确认首页显示 `AURORA 正在工作`，并检查 XML、空间 XML、属性回读和音频服务刷新状态。
5. 用同一段熟悉的音乐切换预设，建议先从“平衡”或“明显”开始。

出现异常时，打开“原厂安全模式”或“原厂对比”，然后重启设备。卸载模块前建议先恢复原厂安全模式。

## 项目结构

```text
.
├── META-INF/              # Magisk/KernelSU ZIP 安装入口
├── webroot/               # 中文移动端 WebUI
├── aurora_core.sh         # 运行时调音、状态和回退逻辑
├── aurora_xml_patch.sh    # 原厂 Dolby XML 增量补丁
├── aurora.conf            # 用户配置
├── customize.sh           # 安装脚本
├── service.sh             # 服务启动脚本
├── post-fs-data.sh        # 文件系统阶段初始化
├── post-mount.sh          # 挂载后处理
├── uninstall.sh           # 卸载回退
├── docs/                  # 发布说明
└── release/               # 可直接安装的发布包和校验值
```

## v5.7.0 修复摘要

- 扬声器作用域改为增量调音，保留耳机、蓝牙、USB 和 unknown 路线。
- Profile 改为动态识别，不再假设设备使用固定编号。
- 修复 XML 布尔值写入、低频上限误切到 64、属性回退和相对输出路径问题。
- 引入共享事务锁，避免 WebUI 与磁盘配置脱节。
- 改进空间化 XML 生成、属性回读、音频服务刷新判断和低功耗逻辑。

完整记录见 [v5.7.0 修复说明](docs/RELEASE_NOTES_v5.7.0.md)。

## 验证与边界

离线验证已覆盖 Shell 语法、WebUI JavaScript 语法、补丁 XML 解析、模块结构、ZIP 完整性、布尔开关写入、optimizer 数量保持和非扬声器节点不变。

当前发布包未在真实目标手机上完成试听、温升、失真、bind mount 和 audioserver 读入验证。最终效果取决于设备厂商 XML、音频 HAL、扬声器硬件和系统实现，安装后请观察日志与温度。

## 校验

```text
SHA256: 12746A407A2EE5A2D6A3F8FBDA761897A3A9CC008EB6D595BBA5CE82AEE43B58
```

## 许可与免责声明

本仓库按作者实际发布内容提供。请在刷入前备份系统和音频配置，并自行确认设备兼容性。AURORA、预设中的品牌灵感名称以及相关描述不表示官方授权、官方调音或商业合作。
