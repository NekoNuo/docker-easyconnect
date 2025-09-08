#!/bin/bash
# VNC 修复测试脚本

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# 配置
CONTAINER_NAME="atrust-vnc-test"
IMAGE_NAME="gys619/docker-easyconnect-atrust:atrust-amd64"
VNC_PASSWORD="test123"

# 清理函数
cleanup() {
    log_info "清理测试环境..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
}

# 捕获退出信号
trap cleanup EXIT

echo -e "${BLUE}=== VNC 修复测试 ===${NC}"
echo ""

# 1. 清理旧容器
log_info "清理旧的测试容器..."
cleanup

# 2. 重新构建镜像
log_info "重新构建镜像..."
if ! docker build \
    $(cat build-args/atrust-amd64.txt 2>/dev/null || echo "--build-arg VPN_TYPE=ATRUST --build-arg EC_HOST=amd64") \
    --build-arg BUILD_ENV=local \
    -t "$IMAGE_NAME" \
    -f Dockerfile . ; then
    log_error "镜像构建失败"
    exit 1
fi

log_info "镜像构建成功"

# 3. 启动测试容器
log_info "启动测试容器..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --device /dev/net/tun \
    --cap-add NET_ADMIN \
    --sysctl net.ipv4.conf.default.route_localnet=1 \
    -e PASSWORD="$VNC_PASSWORD" \
    -e USE_NOVNC=1 \
    -e VNC_AUTO_LOWRES=0 \
    -e VNC_AUTO_OPTIMIZE=0 \
    -p 127.0.0.1:15901:5901 \
    -p 127.0.0.1:18080:8080 \
    -p 127.0.0.1:154631:54631 \
    "$IMAGE_NAME"

log_info "容器启动成功，等待服务初始化..."

# 4. 等待容器启动
sleep 10

# 5. 检查容器状态
log_info "检查容器状态..."
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_error "容器未运行"
    log_info "容器日志:"
    docker logs "$CONTAINER_NAME" | tail -20
    exit 1
fi

# 6. 检查 VNC 服务
log_info "检查 VNC 服务..."
sleep 5

# 检查 VNC 进程
if docker exec "$CONTAINER_NAME" pgrep -f "tigervnc" >/dev/null 2>&1; then
    log_info "✅ TigerVNC 进程正在运行"
else
    log_error "❌ TigerVNC 进程未运行"
    
    log_info "容器内进程列表:"
    docker exec "$CONTAINER_NAME" ps aux | grep -E "(vnc|tiger)" || true
    
    log_info "VNC 相关日志:"
    docker exec "$CONTAINER_NAME" find ~/.vnc -name "*.log" -exec cat {} \; 2>/dev/null || true
    
    log_info "容器启动日志:"
    docker logs "$CONTAINER_NAME" | grep -i vnc || true
    
    exit 1
fi

# 检查 VNC 端口
if docker exec "$CONTAINER_NAME" netstat -tlnp 2>/dev/null | grep ":5901" >/dev/null; then
    log_info "✅ VNC 端口 5901 正在监听"
else
    log_error "❌ VNC 端口 5901 未监听"
    
    log_info "容器内监听端口:"
    docker exec "$CONTAINER_NAME" netstat -tlnp 2>/dev/null || true
    
    exit 1
fi

# 7. 测试 VNC 连接
log_info "测试 VNC 连接..."
if nc -z 127.0.0.1 15901 2>/dev/null; then
    log_info "✅ VNC 端口可以连接"
else
    log_error "❌ 无法连接到 VNC 端口"
    exit 1
fi

# 8. 测试 VNC 协议
log_info "测试 VNC 协议握手..."
if timeout 5 bash -c "echo | nc 127.0.0.1 15901" 2>/dev/null | grep -q "RFB"; then
    log_info "✅ VNC 协议握手成功"
else
    log_warn "⚠️  VNC 协议握手测试不确定"
fi

# 9. 检查 Web VNC
log_info "检查 Web VNC..."
sleep 2
if docker exec "$CONTAINER_NAME" netstat -tlnp 2>/dev/null | grep ":8080" >/dev/null; then
    log_info "✅ Web VNC 端口 8080 正在监听"
    
    if nc -z 127.0.0.1 18080 2>/dev/null; then
        log_info "✅ Web VNC 端口可以连接"
    else
        log_warn "⚠️  Web VNC 端口映射可能有问题"
    fi
else
    log_warn "⚠️  Web VNC 端口未监听"
fi

# 10. 显示连接信息
echo ""
echo -e "${BLUE}=== 测试结果 ===${NC}"
log_info "🎉 VNC 修复测试成功！"
echo ""
echo -e "${GREEN}连接信息:${NC}"
echo "  VNC 客户端: 127.0.0.1:15901"
echo "  密码: $VNC_PASSWORD"
echo "  Web VNC: http://127.0.0.1:18080"
echo "  aTrust Web: https://127.0.0.1:154631"
echo ""
echo -e "${GREEN}测试命令:${NC}"
echo "  查看日志: docker logs $CONTAINER_NAME"
echo "  进入容器: docker exec -it $CONTAINER_NAME bash"
echo "  VNC 状态: docker exec $CONTAINER_NAME ps aux | grep vnc"
echo ""

# 11. 保持容器运行一段时间供测试
log_info "容器将保持运行 60 秒供您测试连接..."
log_info "按 Ctrl+C 可以提前结束测试"

# 显示实时日志
echo ""
echo -e "${BLUE}=== 容器日志 (最后 10 行) ===${NC}"
docker logs --tail 10 "$CONTAINER_NAME"

# 等待用户测试
sleep 60

log_info "测试完成"
