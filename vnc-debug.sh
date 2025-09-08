#!/bin/bash
# VNC 连接调试脚本

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $*"
}

# 检查容器是否运行
check_container() {
    local container_name="${1:-atrust-vnc}"
    
    log_info "检查容器状态..."
    
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        log_error "容器 $container_name 未运行"
        
        # 检查是否存在但已停止
        if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
            log_warn "容器存在但已停止，尝试启动..."
            docker start "$container_name"
            sleep 5
        else
            log_error "容器不存在，请先创建并启动容器"
            return 1
        fi
    fi
    
    log_info "容器 $container_name 正在运行"
    return 0
}

# 检查 VNC 服务状态
check_vnc_service() {
    local container_name="${1:-atrust-vnc}"
    
    log_info "检查 VNC 服务状态..."
    
    # 检查 VNC 进程
    if docker exec "$container_name" pgrep -f "tigervnc" >/dev/null 2>&1; then
        log_info "TigerVNC 服务正在运行"
        
        # 显示 VNC 进程信息
        log_debug "VNC 进程信息:"
        docker exec "$container_name" ps aux | grep -E "(tigervnc|vnc)" | grep -v grep || true
    else
        log_error "TigerVNC 服务未运行"
        
        # 检查启动日志
        log_debug "检查容器启动日志:"
        docker logs --tail 50 "$container_name" | grep -i vnc || true
        
        return 1
    fi
    
    # 检查 VNC 端口
    log_info "检查 VNC 端口..."
    if docker exec "$container_name" netstat -tlnp 2>/dev/null | grep ":5901" >/dev/null; then
        log_info "VNC 端口 5901 正在监听"
        docker exec "$container_name" netstat -tlnp | grep ":5901"
    else
        log_error "VNC 端口 5901 未监听"
        
        # 显示所有监听端口
        log_debug "容器内所有监听端口:"
        docker exec "$container_name" netstat -tlnp 2>/dev/null || true
        
        return 1
    fi
}

# 检查端口映射
check_port_mapping() {
    local container_name="${1:-atrust-vnc}"
    
    log_info "检查端口映射..."
    
    # 检查 Docker 端口映射
    local port_mapping=$(docker port "$container_name" 5901 2>/dev/null || echo "")
    
    if [ -n "$port_mapping" ]; then
        log_info "VNC 端口映射: $port_mapping"
    else
        log_error "VNC 端口 5901 未映射到主机"
        
        # 显示所有端口映射
        log_debug "容器所有端口映射:"
        docker port "$container_name" || true
        
        return 1
    fi
}

# 测试 VNC 连接
test_vnc_connection() {
    local container_name="${1:-atrust-vnc}"
    
    log_info "测试 VNC 连接..."
    
    # 获取端口映射
    local vnc_port=$(docker port "$container_name" 5901 2>/dev/null | cut -d':' -f2 || echo "5901")
    
    # 测试本地连接
    if command -v nc >/dev/null 2>&1; then
        if nc -z 127.0.0.1 "$vnc_port" 2>/dev/null; then
            log_info "VNC 端口 $vnc_port 可以连接"
        else
            log_error "无法连接到 VNC 端口 $vnc_port"
            return 1
        fi
    else
        log_warn "nc 命令不可用，跳过连接测试"
    fi
    
    # 测试 VNC 协议握手
    if command -v timeout >/dev/null 2>&1; then
        log_debug "测试 VNC 协议握手..."
        if timeout 5 bash -c "echo | nc 127.0.0.1 $vnc_port" 2>/dev/null | grep -q "RFB"; then
            log_info "VNC 协议握手成功"
        else
            log_warn "VNC 协议握手可能有问题"
        fi
    fi
}

# 检查 VNC 配置
check_vnc_config() {
    local container_name="${1:-atrust-vnc}"
    
    log_info "检查 VNC 配置..."
    
    # 检查 VNC 密码文件
    if docker exec "$container_name" test -f ~/.vnc/passwd 2>/dev/null; then
        log_info "VNC 密码文件存在"
    else
        log_error "VNC 密码文件不存在"
        return 1
    fi
    
    # 检查 X11 显示
    if docker exec "$container_name" test -n "$DISPLAY" 2>/dev/null; then
        local display=$(docker exec "$container_name" echo "$DISPLAY" 2>/dev/null)
        log_info "X11 DISPLAY 设置为: $display"
    else
        log_error "X11 DISPLAY 未设置"
        return 1
    fi
    
    # 检查 VNC 日志
    log_debug "VNC 相关日志:"
    docker exec "$container_name" find ~/.vnc -name "*.log" -exec tail -10 {} \; 2>/dev/null || true
}

# 检查 Web VNC
check_web_vnc() {
    local container_name="${1:-atrust-vnc}"
    
    log_info "检查 Web VNC (noVNC)..."
    
    # 检查 noVNC 进程
    if docker exec "$container_name" pgrep -f "websockify\|easy-novnc" >/dev/null 2>&1; then
        log_info "Web VNC 服务正在运行"
        
        # 检查 Web VNC 端口
        if docker exec "$container_name" netstat -tlnp 2>/dev/null | grep ":8080" >/dev/null; then
            log_info "Web VNC 端口 8080 正在监听"
            
            # 获取端口映射
            local web_port=$(docker port "$container_name" 8080 2>/dev/null | cut -d':' -f2 || echo "8080")
            log_info "Web VNC 访问地址: http://127.0.0.1:$web_port"
        else
            log_warn "Web VNC 端口 8080 未监听"
        fi
    else
        log_warn "Web VNC 服务未运行 (可能未启用 USE_NOVNC)"
    fi
}

# 显示连接信息
show_connection_info() {
    local container_name="${1:-atrust-vnc}"
    
    echo ""
    echo -e "${BLUE}=== VNC 连接信息 ===${NC}"
    
    # VNC 客户端连接
    local vnc_port=$(docker port "$container_name" 5901 2>/dev/null | cut -d':' -f2 || echo "5901")
    echo -e "${GREEN}VNC 客户端连接:${NC}"
    echo "  地址: 127.0.0.1:$vnc_port"
    echo "  密码: 启动时设置的密码"
    
    # Web VNC 连接
    local web_port=$(docker port "$container_name" 8080 2>/dev/null | cut -d':' -f2 || echo "8080")
    echo -e "${GREEN}Web VNC 连接:${NC}"
    echo "  地址: http://127.0.0.1:$web_port"
    
    # aTrust Web 连接
    local atrust_port=$(docker port "$container_name" 54631 2>/dev/null | cut -d':' -f2 || echo "54631")
    echo -e "${GREEN}aTrust Web 连接:${NC}"
    echo "  地址: https://127.0.0.1:$atrust_port"
    
    echo ""
}

# 修复常见问题
fix_common_issues() {
    local container_name="${1:-atrust-vnc}"
    
    log_info "尝试修复常见 VNC 问题..."
    
    # 重启 VNC 服务
    log_info "重启 VNC 服务..."
    docker exec "$container_name" bash -c "
        pkill -f tigervnc || true
        sleep 2
        export DISPLAY=:1
        tigervncserver \$DISPLAY -geometry 1110x620 -localhost=0 -passwd ~/.vnc/passwd -xstartup flwm -depth 24
    " || log_warn "VNC 服务重启失败"
    
    sleep 3
    
    # 检查修复结果
    if docker exec "$container_name" pgrep -f "tigervnc" >/dev/null 2>&1; then
        log_info "VNC 服务重启成功"
        return 0
    else
        log_error "VNC 服务重启失败"
        return 1
    fi
}

# 主函数
main() {
    local container_name="${1:-atrust-vnc}"
    local fix_mode="${2:-}"
    
    echo -e "${BLUE}VNC 连接调试工具${NC}"
    echo "容器名称: $container_name"
    echo ""
    
    # 基础检查
    if ! check_container "$container_name"; then
        exit 1
    fi
    
    # VNC 服务检查
    local vnc_ok=true
    check_vnc_service "$container_name" || vnc_ok=false
    check_port_mapping "$container_name" || vnc_ok=false
    check_vnc_config "$container_name" || vnc_ok=false
    
    # 连接测试
    if [ "$vnc_ok" = true ]; then
        test_vnc_connection "$container_name" || vnc_ok=false
    fi
    
    # Web VNC 检查
    check_web_vnc "$container_name"
    
    # 显示连接信息
    show_connection_info "$container_name"
    
    # 修复模式
    if [ "$fix_mode" = "fix" ] && [ "$vnc_ok" = false ]; then
        echo ""
        log_warn "检测到 VNC 问题，尝试自动修复..."
        if fix_common_issues "$container_name"; then
            log_info "修复完成，请重新测试连接"
        else
            log_error "自动修复失败，请检查容器日志"
        fi
    fi
    
    # 总结
    echo ""
    if [ "$vnc_ok" = true ]; then
        log_info "VNC 服务状态正常，可以尝试连接"
    else
        log_error "VNC 服务存在问题，请检查上述错误信息"
        echo ""
        echo "建议的解决步骤:"
        echo "1. 检查容器日志: docker logs $container_name"
        echo "2. 尝试自动修复: $0 $container_name fix"
        echo "3. 重启容器: docker restart $container_name"
        echo "4. 检查启动参数是否正确"
    fi
}

# 显示帮助
show_help() {
    echo "VNC 连接调试工具"
    echo ""
    echo "用法: $0 [容器名称] [fix]"
    echo ""
    echo "参数:"
    echo "  容器名称    要检查的容器名称 (默认: atrust-vnc)"
    echo "  fix         尝试自动修复 VNC 问题"
    echo ""
    echo "示例:"
    echo "  $0                    # 检查默认容器"
    echo "  $0 my-container       # 检查指定容器"
    echo "  $0 atrust-vnc fix     # 检查并尝试修复"
}

# 参数处理
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    show_help
    exit 0
fi

# 运行主函数
main "$@"
