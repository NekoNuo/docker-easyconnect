# 内存优化指南

## 问题分析

您的容器内存占用从 390MiB 增加到 464MiB，增加了约 74MiB。主要原因：

### 内存占用增加的原因
1. **VNC 性能监控脚本** - `vnc-performance-monitor.sh` 每30秒运行，使用 `jq`、`netstat`、`ps` 等命令
2. **智能优化守护进程** - `vnc-auto-optimizer.sh` 持续在后台运行
3. **复杂的统计收集** - JSON 格式的统计文件和复杂的数据处理
4. **频繁的系统调用** - 大量的进程检查和网络状态查询

## 解决方案

### 1. 轻量级模式 (推荐)

使用轻量级监控模式，大幅减少内存占用：

```bash
docker run --rm --device /dev/net/tun --cap-add NET_ADMIN -ti \
  -e PASSWORD=zxcvbnm \
  -e URLWIN=1 \
  -e PING_ADDR_URL=https://iama.haier.net/login \
  -e SOCKS_USER=gys \
  -e SOCKS_PASSWD=zxcvbnm \
  -e USE_NOVNC=1 \
  -e VNC_LITE_MODE=1 \
  -e VNC_SIZE=640x480 \
  -e VNC_DEPTH=16 \
  -e VNC_MEMORY_OPTIMIZE=1 \
  -v $HOME/.atrust-data:/root \
  -p 5901:5901 \
  -p 1080:1080 \
  -p 8080:8080 \
  --sysctl net.ipv4.conf.default.route_localnet=1 \
  hagb/docker-atrust
```

### 2. 完全禁用监控 (最低内存)

如果不需要任何监控功能：

```bash
docker run --rm --device /dev/net/tun --cap-add NET_ADMIN -ti \
  -e PASSWORD=zxcvbnm \
  -e URLWIN=1 \
  -e PING_ADDR_URL=https://iama.haier.net/login \
  -e SOCKS_USER=gys \
  -e SOCKS_PASSWD=zxcvbnm \
  -e USE_NOVNC=1 \
  -e VNC_AUTO_OPTIMIZE=0 \
  -e VNC_SMART_OPTIMIZE=0 \
  -e VNC_AUTO_LOWRES=0 \
  -e VNC_SIZE=640x480 \
  -e VNC_DEPTH=16 \
  -v $HOME/.atrust-data:/root \
  -p 5901:5901 \
  -p 1080:1080 \
  -p 8080:8080 \
  --sysctl net.ipv4.conf.default.route_localnet=1 \
  hagb/docker-atrust
```

## 环境变量说明

### 内存优化相关
- `VNC_LITE_MODE=1` - 启用轻量级监控 (节省 ~50MB)
- `VNC_MEMORY_OPTIMIZE=1` - 启用内存优化
- `VNC_AUTO_OPTIMIZE=0` - 禁用重量级优化 (节省 ~30MB)
- `VNC_SMART_OPTIMIZE=0` - 禁用智能优化 (节省 ~20MB)

### VNC 设置优化
- `VNC_SIZE=640x480` - 低分辨率 (节省 ~15MB)
- `VNC_DEPTH=16` - 16位色彩 (节省 ~10MB)
- `VNC_QUALITY=2` - 高压缩质量
- `VNC_COMPRESS=9` - 最高压缩级别
- `VNC_FRAMERATE=15` - 降低帧率
- `VNC_MONITOR_INTERVAL=120` - 降低监控频率

## 内存使用对比

| 配置模式 | 预估内存占用 | 节省内存 | 功能影响 |
|---------|-------------|---------|---------|
| 原版本 | ~390MB | - | 基础功能 |
| 当前完整版 | ~464MB | -74MB | 完整监控和优化 |
| 轻量级模式 | ~410MB | ~54MB | 基础监控 |
| 禁用监控 | ~395MB | ~69MB | 无监控 |

## 手动内存优化

### 运行时优化
```bash
# 进入容器
docker exec -it <container_name> bash

# 查看内存使用
memory-optimizer.sh report

# 自动优化内存
memory-optimizer.sh auto

# 停止重量级监控
memory-optimizer.sh stop-monitors

# 配置轻量级模式
memory-optimizer.sh lite-mode
source /tmp/vnc-lite-config
```

### 监控内存使用
```bash
# 查看轻量级监控状态
vnc-monitor-lite.sh status

# 停止轻量级监控
vnc-monitor-lite.sh stop

# 重启轻量级监控
vnc-monitor-lite.sh monitor &
```

## 性能影响说明

### 轻量级模式的影响
- ✅ 内存占用减少 50-70MB
- ✅ CPU 使用率降低
- ⚠️ 监控功能简化
- ⚠️ 自动优化频率降低

### 禁用监控的影响
- ✅ 最低内存占用
- ✅ 最低 CPU 使用
- ❌ 无性能监控
- ❌ 无自动优化

## 故障排除

### 如果内存仍然过高
1. 检查是否有旧的监控进程残留
2. 清理系统缓存
3. 降低 VNC 分辨率和色彩深度
4. 考虑增加容器内存限制

### 检查内存泄漏
```bash
# 生成内存报告
memory-optimizer.sh report

# 查看详细进程信息
ps aux --sort=-%mem | head -10

# 检查 VNC 进程内存
pmap $(pgrep Xtigervnc) | tail -1
```

## 推荐配置

对于您的使用场景，推荐使用轻量级模式：

```yaml
# docker-compose.yml
environment:
  - VNC_LITE_MODE=1
  - VNC_SIZE=640x480
  - VNC_DEPTH=16
  - VNC_MEMORY_OPTIMIZE=1
  - VNC_MONITOR_INTERVAL=120
```

这样可以在保持基本监控功能的同时，将内存占用控制在合理范围内。
