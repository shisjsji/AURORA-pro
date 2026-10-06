# AURORA-pro v5.7.0 修复版

文件：`AURORA-pro_v5.7.0_修复版.zip`

## 这版做了什么

- 以设备 `/odm/etc/dolby/dax-default.xml` 为首选基底，`/vendor` 只作后备，不再静态覆盖 OEM 调音。
- 动态读取设备 XML 中的 Profile ID，不再假设所有手机都使用同一组编号。
- 只对双扬声器的 speaker tuning 和选定 Profile 的 speaker endpoint 增量调音；耳机、蓝牙、USB、unknown 路线保持原厂节点。
- 修复 `bass-enhancer-boost` 上限误切到 64、XML 布尔开关无法写入、相对输出路径失败、optimizer 数量变化未校验等问题。
- `空间化` 开关在开启和关闭时都会写入明确的 XML 状态，并验证 spatializer 文件的生成与挂载。
- 运行时先生成并绑定 XML，再写音频属性；任一步失败都会回退，不留下“属性已改但 XML 未生效”的半状态。
- 首次应用会快照 4 个相关属性，安全模式和卸载时恢复原值；外接路线映射默认保留，空映射只补双扬声器和听筒。
- `POWER_SAVE_MODE` 现在会真实降低非强烈模式的曲线偏移，智能刷新会结合 XML 基底、路由、Profile、EQ 和空间设置判断是否需要重启 audioserver。
- 状态页区分 `XML_BOUND`、`ACTIVE`、`STOCK`、`DEGRADED`，并显示路线置信度、空间 XML、属性回读和音频服务刷新结果。
- WebUI 改为中文移动端分组界面，预设采用自然动态、影院包围、音乐饱满、人声清晰、哈曼暖声灵感、柏林自然灵感、北欧温暖、北欧明亮、动感冲击等听感命名。品牌名称只表示听感灵感，不代表品牌官方 EQ。
- WebUI 配置通过共享锁下的 `stdin` 原子提交，应用期间锁定控件，避免页面状态与磁盘配置脱节。

## 使用

1. 在 Magisk 或 KernelSU 中安装 ZIP。
2. 重启设备。
3. 打开模块 WebUI，等待首页显示 `AURORA 正在工作`，并确认诊断里的 XML、空间 XML、属性状态均正常。
4. 用同一段熟悉的音乐切换不同预设，先从“平衡”或“明显”开始，再按需要调整 EQ。
5. 如果需要对照原厂，使用“原厂对比”或“安全回退”。出现异常时保持原厂安全模式并重启设备。

## 验证边界

当前电脑没有连接目标手机，无法在本机确认目标设备的实际 bind mount、audioserver 读入结果、温升、失真和最终听感。离线验证已覆盖 Shell 语法、ShellCheck、WebUI JavaScript 语法、补丁 XML 解析、optimizer 数量保持、非扬声器节点不变、布尔开关写入和模块 ZIP 结构。最终效果仍需在目标设备上试听并观察温度与日志。
