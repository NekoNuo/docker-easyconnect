# VNC 修复指南

## 🔧 已修复的问题

### 1. TigerVNC 配置文件错误
**问题**: `Invalid pixelformat ! at /etc/tigervnc/vncserver-config-defaults line 7`

**修复**: 
- 移除了无效的 `$pixelformat = "";` 配置
- 简化配置文件，只保留必要设置
- 验证了 Perl 语法正确性

### 2. VNC 启动参数错误
**问题**: `-localhost no` 参数格式不正确

**修复**:
- 更改为 `-localhost=0` (正确的 TigerVNC 语法)
- 移除了服务器端不支持的编码参数
- 添加了启动前的清理和验证步骤

### 3. X11 显示环境问题
**修复**:
- 确保 VNC 目录存在
- 清理旧的 VNC 会话
- 添加启动后的状态检查

## 🚀 测试步骤

### 步骤 1: 重新构建镜像

```bash
# 使用构建参数文件构建
docker build \
  $(cat build-args/atrust-amd64.txt) \
  --build-arg BUILD_ENV=local \
  -t gys619/docker-easyconnect-atrust:atrust-amd64 \
  -f Dockerfile .
```

### 步骤 2: 最小化测试

```bash
# 停止旧容器
docker stop atrust-vnc 2>/dev/null || true
docker rm atrust-vnc 2>/dev/null || true

# 启动最小化测试容器
docker run -d \
  --name atrust-vnc \
  --device /dev/net/tun \
  --cap-add NET_ADMIN \
  -e PASSWORD=test123 \
  -e VNC_AUTO_LOWRES=0 \
  -e VNC_AUTO_OPTIMIZE=0 \
  -p 127.0.0.1:5901:5901 \
  gys619/docker-easyconnect-atrust:atrust-amd64
```

### 步骤 3: 检查容器状态

```bash
# 等待容器启动
sleep 10

# 检查容器是否运行
docker ps | grep atrust-vnc

# 查看启动日志
docker logs atrust-vnc | grep -i vnc
```

### 步骤 4: 验证 VNC 服务

```bash
# 检查 VNC 进程
docker exec atrust-vnc pgrep -f tigervnc

# 检查 VNC 端口
docker exec atrust-vnc netstat -tlnp | grep 5901

# 检查 VNC 日志
docker exec atrust-vnc find ~/.vnc -name "*.log" -exec tail -10 {} \;
```

### 步骤 5: 测试 VNC 连接

```bash
# 测试端口连通性
nc -z 127.0.0.1 5901

# 测试 VNC 协议握手
timeout 5 bash -c "echo | nc 127.0.0.1 5901" | head -1
# 应该看到类似 "RFB 003.008" 的输出
```

## 🔍 故障排除

### 如果 VNC 仍然无法启动

1. **查看详细日志**:
```bash
docker logs atrust-vnc | tail -50
```

2. **检查 VNC 配置**:
```bash
docker exec atrust-vnc cat /etc/tigervnc/vncserver-config-defaults
```

3. **手动启动 VNC**:
```bash
docker exec -it atrust-vnc bash
export DISPLAY=:1
mkdir -p ~/.vnc
echo "test123" | tigervncpasswd -f > ~/.vnc/passwd
tigervncserver :1 -geometry 1110x620 -localhost=0 -passwd ~/.vnc/passwd -xstartup flwm -depth 24
```

4. **检查系统资源**:
```bash
docker exec atrust-vnc free -h
docker exec atrust-vnc df -h
```

### 如果端口无法连接

1. **检查端口映射**:
```bash
docker port atrust-vnc
```

2. **检查防火墙**:
```bash
# 在宿主机上
netstat -tlnp | grep 5901
```

3. **使用调试脚本**:
```bash
./vnc-debug.sh atrust-vnc fix
```

## 🎯 完整功能测试

如果基础 VNC 工作正常，可以测试完整功能：

```bash
# 停止测试容器
docker stop atrust-vnc && docker rm atrust-vnc

# 启动完整功能容器
docker run -d \
  --name atrust-vnc \
  --device /dev/net/tun \
  --cap-add NET_ADMIN \
  --sysctl net.ipv4.conf.default.route_localnet=1 \
  -e PASSWORD=test123 \
  -e USE_NOVNC=1 \
  -e VNC_AUTO_LOWRES=1 \
  -e VNC_AUTO_OPTIMIZE=1 \
  -p 127.0.0.1:5901:5901 \
  -p 127.0.0.1:8080:8080 \
  -p 127.0.0.1:54631:54631 \
  -v atrust-data:/root \
  gys619/docker-easyconnect-atrust:atrust-amd64
```

## 🔗 连接测试

### VNC 客户端连接
- **地址**: `127.0.0.1:5901`
- **密码**: `test123`

### Web VNC 连接
- **地址**: `http://127.0.0.1:8080`
- **密码**: `test123`

### aTrust Web 界面
- **地址**: `https://127.0.0.1:54631`
- **注意**: 忽略证书警告

## 📊 性能监控

启动后可以使用以下命令监控性能：

```bash
# 查看 VNC 性能状态
docker exec atrust-vnc vnc-performance-monitor.sh status

# 获取优化建议
docker exec atrust-vnc vnc-performance-monitor.sh suggest

# 查看资源使用
docker stats atrust-vnc --no-stream
```

## ✅ 预期结果

修复后，您应该看到：

1. **容器启动日志**:
```
VNC: 启动 TigerVNC 服务器 (显示: :1)
VNC: TigerVNC 服务器启动成功
```

2. **VNC 进程运行**:
```bash
$ docker exec atrust-vnc pgrep -f tigervnc
1234
```

3. **端口正常监听**:
```bash
$ docker exec atrust-vnc netstat -tlnp | grep 5901
tcp 0 0 0.0.0.0:5901 0.0.0.0:* LISTEN 1234/Xtigervnc
```

4. **VNC 协议握手成功**:
```bash
$ timeout 5 bash -c "echo | nc 127.0.0.1 5901" | head -1
RFB 003.008
```

## 🎉 成功标志

如果看到以上所有结果，说明 VNC 修复成功！您现在可以：

- 使用 VNC 客户端连接到 `127.0.0.1:5901`
- 通过浏览器访问 `http://127.0.0.1:8080` 使用 Web VNC
- 访问 `https://127.0.0.1:54631` 使用 aTrust Web 界面

## 📝 注意事项

1. **首次启动**: 容器首次启动可能需要 30-60 秒来初始化所有服务
2. **资源要求**: 确保系统有足够的内存（建议 >1GB）
3. **网络配置**: 确保 Docker 网络配置正确，特别是 TUN 设备权限
4. **防火墙**: 检查本地防火墙是否阻止了端口访问

如果按照此指南操作后 VNC 仍有问题，请提供详细的错误日志以便进一步诊断。
