#!/bin/bash
# 快速 VNC 测试脚本

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
CONTAINER_NAME="${1:-atrust-vnc}"

echo -e "${BLUE}=== 快速 VNC 状态检查 ===${NC}"
echo "容器名称: $CONTAINER_NAME"
echo ""

# 1. 检查容器状态
log_info "检查容器状态..."
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "✅ 容器正在运行"
else
    log_error "❌ 容器未运行"
    exit 1
fi

# 2. 检查 aTrust 服务
log_info "检查 aTrust 服务..."
if docker exec "$CONTAINER_NAME" pgrep -f "aTrustAgent" >/dev/null 2>&1; then
    log_info "✅ aTrust 服务正在运行"
    
    # 显示 aTrust 进程信息
    echo "aTrust 进程:"
    docker exec "$CONTAINER_NAME" ps aux | grep -E "(aTrust|sapp)" | grep -v grep | head -3
else
    log_warn "⚠️  aTrust 服务可能未完全启动"
fi

echo ""

# 3. 检查 VNC 服务
log_info "检查 VNC 服务..."

# 检查 TigerVNC 进程
if docker exec "$CONTAINER_NAME" pgrep -f "Xtigervnc" >/dev/null 2>&1; then
    log_info "✅ TigerVNC 进程正在运行"
    
    # 显示 VNC 进程信息
    echo "VNC 进程:"
    docker exec "$CONTAINER_NAME" ps aux | grep -E "(tigervnc|Xtigervnc)" | grep -v grep
    
    # 检查 VNC 端口
    if docker exec "$CONTAINER_NAME" netstat -tlnp 2>/dev/null | grep ":5901" >/dev/null; then
        log_info "✅ VNC 端口 5901 正在监听"
    else
        log_error "❌ VNC 端口 5901 未监听"
    fi
    
else
    log_error "❌ TigerVNC 进程未运行"
    
    # 查看 VNC 日志
    log_info "查看 VNC 日志:"
    docker exec "$CONTAINER_NAME" find ~/.vnc -name "*.log" -exec echo "=== {} ===" \; -exec tail -10 {} \; 2>/dev/null || true
fi

echo ""

# 4. 检查端口映射
log_info "检查端口映射..."
VNC_PORT=$(docker port "$CONTAINER_NAME" 5901 2>/dev/null | cut -d':' -f2 || echo "")
if [ -n "$VNC_PORT" ]; then
    log_info "✅ VNC 端口映射: 127.0.0.1:$VNC_PORT"
    
    # 测试连接
    if nc -z 127.0.0.1 "$VNC_PORT" 2>/dev/null; then
        log_info "✅ VNC 端口可以连接"
    else
        log_error "❌ 无法连接到 VNC 端口"
    fi
else
    log_error "❌ VNC 端口未映射"
fi

# 5. 检查 Web VNC
log_info "检查 Web VNC..."
WEB_PORT=$(docker port "$CONTAINER_NAME" 8080 2>/dev/null | cut -d':' -f2 || echo "")
if [ -n "$WEB_PORT" ]; then
    log_info "✅ Web VNC 端口映射: 127.0.0.1:$WEB_PORT"
    
    if docker exec "$CONTAINER_NAME" netstat -tlnp 2>/dev/null | grep ":8080" >/dev/null; then
        log_info "✅ Web VNC 服务正在运行"
    else
        log_warn "⚠️  Web VNC 服务可能未启动"
    fi
else
    log_warn "⚠️  Web VNC 端口未映射"
fi

echo ""

# 6. 测试 VNC 性能监控
log_info "测试 VNC 性能监控..."
if docker exec "$CONTAINER_NAME" vnc-performance-monitor.sh status 2>/dev/null; then
    log_info "✅ VNC 性能监控正常"
else
    log_warn "⚠️  VNC 性能监控可能有问题"
fi

echo ""

# 7. 显示连接信息
echo -e "${BLUE}=== 连接信息 ===${NC}"
if [ -n "$VNC_PORT" ]; then
    echo -e "${GREEN}VNC 客户端连接:${NC}"
    echo "  地址: 127.0.0.1:$VNC_PORT"
    echo "  密码: 启动时设置的密码"
fi

if [ -n "$WEB_PORT" ]; then
    echo -e "${GREEN}Web VNC 连接:${NC}"
    echo "  地址: http://127.0.0.1:$WEB_PORT"
fi

ATRUST_PORT=$(docker port "$CONTAINER_NAME" 54631 2>/dev/null | cut -d':' -f2 || echo "")
if [ -n "$ATRUST_PORT" ]; then
    echo -e "${GREEN}aTrust Web 连接:${NC}"
    echo "  地址: https://127.0.0.1:$ATRUST_PORT"
fi

echo ""

# 8. 显示最近的容器日志
echo -e "${BLUE}=== 最近的容器日志 ===${NC}"
docker logs --tail 10 "$CONTAINER_NAME" | grep -E "(VNC|aTrust|ERROR|WARN)" || docker logs --tail 5 "$CONTAINER_NAME"

echo ""
echo -e "${BLUE}=== 检查完成 ===${NC}"

# 9. 提供建议
if docker exec "$CONTAINER_NAME" pgrep -f "Xtigervnc" >/dev/null 2>&1 && [ -n "$VNC_PORT" ]; then
    log_info "🎉 VNC 服务状态良好，可以尝试连接！"
else
    log_warn "⚠️  VNC 服务可能有问题，建议："
    echo "  1. 查看完整日志: docker logs $CONTAINER_NAME"
    echo "  2. 重启容器: docker restart $CONTAINER_NAME"
    echo "  3. 使用调试工具: ./vnc-debug.sh $CONTAINER_NAME fix"
fi
