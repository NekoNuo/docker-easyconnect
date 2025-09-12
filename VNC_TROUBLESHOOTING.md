# VNC 故障排除指南

## 问题描述
TigerVNC 服务器启动失败，显示错误：
```
Xvnc TigerVNC 1.12.0 - built 2023-01-06 16:01
(EE) Fatal server error:
(EE) Couldn't add screen
VNC: ❌ TigerVNC 服务器启动失败
```

## 已实施的修复

### 1. 启动脚本优化 (`start.sh`)
- **简化启动参数**：移除可能导致问题的复杂 X11 扩展参数
- **多级启动策略**：基本模式失败时自动尝试最简模式
- **修改默认分辨率**：从 `1110x620` 改为标准的 `1024x768`
- **增强 X11 环境初始化**：确保必要的目录和设备文件存在
- **添加故障排除**：启动失败时自动运行诊断脚本

### 2. TigerVNC 配置优化 (`vncserver-config-defaults`)
- **启用必要的 X11 扩展**
- **设置标准像素格式**：rgb888
- **配置 DPI**：96
- **安全设置**：VncAuth 认证

### 3. X11 环境初始化脚本 (`init-x11-simple.sh`)
- **简化依赖检查**：只检查必需的命令（Xtigervnc, flwm）
- **创建必要目录**：`/tmp/.X11-unix`, `/tmp/.ICE-unix`, `/tmp/.font-unix`
- **设置正确权限**：确保 X11 socket 目录可写
- **容错处理**：权限不足时不会失败，提供后备方案
- **环境变量设置**：`XDG_SESSION_TYPE`, `XDG_CURRENT_DESKTOP`

### 4. X11 配置文件 (`10-tigervnc.conf`)
- **定义屏幕布局**：支持多种分辨率和色彩深度
- **VNC 设备配置**：密码文件、端口、几何形状
- **模块加载**：必要的 X11 模块
- **扩展启用**：所有必要的 X11 扩展

### 5. 包依赖修复 (`Dockerfile`)
- **添加 x11-xserver-utils**：包含 `xset` 等 X11 工具
- **保留现有包**：`x11-utils`, `tigervnc-standalone-server` 等
- **简化依赖检查**：避免因缺少可选工具而失败

### 6. 故障排除脚本 (`vnc-troubleshoot.sh`)
- **系统信息检查**：内存、磁盘、进程
- **X11 环境检查**：包、目录、权限
- **VNC 配置检查**：密码文件、配置文件、端口
- **自动修复功能**：清理旧进程、创建目录、修复权限

## 使用方法

### 构建镜像
```bash
docker build -t easyconnect-fixed .
```

### 运行容器
```bash
docker-compose up -d
```

### 手动故障排除
如果仍有问题，可以手动运行故障排除脚本：
```bash
# 进入容器
docker exec -it <container_name> bash

# 运行诊断
/usr/local/bin/vnc-troubleshoot.sh check

# 自动修复
/usr/local/bin/vnc-troubleshoot.sh fix

# 完整检查和修复
/usr/local/bin/vnc-troubleshoot.sh full
```

### 环境变量配置
在 `docker-compose.yml` 中可以配置：
```yaml
environment:
  - VNC_SIZE=1024x768          # VNC 分辨率
  - VNC_DEPTH=24               # 色彩深度
  - VNC_ENCODING=tight         # 编码方式
  - PASSWORD=your_password     # VNC 密码
```

## 常见问题解决

### 1. 内存不足
如果系统内存不足，会自动启用低内存优化：
- 降低分辨率到 800x600
- 减少色彩深度到 8 位
- 降低帧率到 15fps

### 2. 端口冲突
如果 5901 端口被占用：
- 脚本会自动检测并清理旧进程
- 可以通过环境变量修改端口

### 3. 权限问题
确保容器有足够权限：
```yaml
cap_add:
  - NET_ADMIN
privileged: true  # 如果需要
```

## 技术细节

### 修复的核心问题
1. **缺少 X11 扩展**：TigerVNC 需要特定的 X11 扩展才能创建屏幕
2. **不兼容的分辨率**：某些分辨率可能不被支持
3. **环境初始化不完整**：缺少必要的目录和设备文件
4. **权限问题**：X11 socket 目录权限不正确

### 启动流程优化
1. **环境检查**：验证 X11 依赖和环境
2. **清理旧会话**：移除可能冲突的进程和文件
3. **初始化环境**：创建必要的目录和文件
4. **启动 VNC**：使用优化的参数启动 TigerVNC
5. **故障诊断**：启动失败时自动诊断问题

这些修复应该能解决大部分 "Couldn't add screen" 错误。如果问题仍然存在，请查看故障排除脚本的输出以获取更详细的诊断信息。
