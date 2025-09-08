#!/bin/bash
# VNC 低配置服务器优化脚本

set -euo pipefail

# 配置
VNC_DISPLAY="${VNC_DISPLAY:-:1}"
CONFIG_FILE="/tmp/vnc-lowres-config"

# 日志函数
log_info() {
    echo "$(date -Iseconds) [INFO] $*"
}

log_warn() {
    echo "$(date -Iseconds) [WARN] $*" >&2
}

# 检测系统资源
detect_system_resources() {
    local mem_total mem_available mem_usage_percent
    local cpu_cores load_avg
    local disk_usage
    
    # 内存信息
    mem_total=$(free -m | awk 'NR==2{print $2}')
    mem_available=$(free -m | awk 'NR==2{print $7}')
    mem_usage_percent=$(echo "scale=0; (($mem_total - $mem_available) * 100) / $mem_total" | bc -l)
    
    # CPU 信息
    cpu_cores=$(nproc)
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
    
    # 磁盘使用率
    disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    echo "SYSTEM_RESOURCES:"
    echo "  内存总量: ${mem_total}MB"
    echo "  可用内存: ${mem_available}MB"
    echo "  内存使用率: ${mem_usage_percent}%"
    echo "  CPU 核心数: ${cpu_cores}"
    echo "  系统负载: ${load_avg}"
    echo "  磁盘使用率: ${disk_usage}%"
    
    # 返回资源等级
    local resource_level="normal"
    
    if [ "$mem_available" -lt 256 ] || [ "$cpu_cores" -eq 1 ] || [ "$(echo "$load_avg > 3" | bc -l)" -eq 1 ]; then
        resource_level="critical"
    elif [ "$mem_available" -lt 512 ] || [ "$(echo "$load_avg > 2" | bc -l)" -eq 1 ]; then
        resource_level="low"
    elif [ "$mem_available" -lt 1024 ] || [ "$(echo "$load_avg > 1" | bc -l)" -eq 1 ]; then
        resource_level="medium"
    fi
    
    echo "RESOURCE_LEVEL: $resource_level"
    echo "$resource_level"
}

# 生成低资源配置
generate_lowres_config() {
    local resource_level="$1"
    
    log_info "为 $resource_level 资源级别生成优化配置"
    
    local encoding quality compress framerate depth size defer_time
    local extra_args=""
    
    case "$resource_level" in
        "critical")
            # 极低资源配置 - 最大化节省资源
            encoding="tight"
            quality="0"
            compress="9"
            framerate="5"
            depth="8"
            size="640x480"
            defer_time="300"
            extra_args="-MaxIdleTime 300 -MaxConnectionTime 1800"
            log_info "使用极低资源配置 - 适合 <256MB 内存或单核 CPU"
            ;;
        "low")
            # 低资源配置
            encoding="tight"
            quality="1"
            compress="9"
            framerate="8"
            depth="8"
            size="800x600"
            defer_time="200"
            extra_args="-MaxIdleTime 600"
            log_info "使用低资源配置 - 适合 256-512MB 内存"
            ;;
        "medium")
            # 中等资源配置
            encoding="tight"
            quality="3"
            compress="8"
            framerate="15"
            depth="16"
            size="1024x768"
            defer_time="100"
            log_info "使用中等资源配置 - 适合 512MB-1GB 内存"
            ;;
        *)
            # 正常配置
            encoding="tight"
            quality="6"
            compress="6"
            framerate="30"
            depth="24"
            size="1110x620"
            defer_time="1"
            log_info "使用正常配置 - 适合 >1GB 内存"
            ;;
    esac
    
    # 生成配置文件
    cat > "$CONFIG_FILE" << EOF
# VNC 低资源优化配置
# 资源级别: $resource_level
# 生成时间: $(date -Iseconds)

export VNC_ENCODING="$encoding"
export VNC_QUALITY="$quality"
export VNC_COMPRESS="$compress"
export VNC_FRAMERATE="$framerate"
export VNC_DEPTH="$depth"
export VNC_SIZE="$size"
export VNC_DEFERTIME="$defer_time"
export VNC_EXTRA_ARGS="$extra_args"

# 系统优化设置
export VNC_LOWRES_MODE="1"
export VNC_RESOURCE_LEVEL="$resource_level"

# 应用配置函数
apply_lowres_config() {
    echo "应用低资源 VNC 配置:"
    echo "  资源级别: $resource_level"
    echo "  编码: $encoding"
    echo "  质量: $quality (0=最高压缩)"
    echo "  压缩: $compress"
    echo "  帧率: ${framerate}fps"
    echo "  深度: ${depth}bit"
    echo "  分辨率: $size"
    echo "  延迟: ${defer_time}ms"
    [ -n "$extra_args" ] && echo "  额外参数: $extra_args"
}
EOF
    
    log_info "低资源配置已生成: $CONFIG_FILE"
}

# 系统优化建议
suggest_system_optimizations() {
    local resource_level="$1"
    
    echo ""
    echo "=== 系统优化建议 ==="
    
    case "$resource_level" in
        "critical")
            echo "⚠️  极低资源环境，强烈建议："
            echo "   1. 关闭不必要的系统服务"
            echo "   2. 使用 swap 文件增加虚拟内存"
            echo "   3. 考虑升级硬件配置"
            echo "   4. 限制同时连接的 VNC 客户端数量"
            echo "   5. 使用文本模式而非图形界面（如可能）"
            ;;
        "low")
            echo "⚠️  低资源环境，建议："
            echo "   1. 监控内存使用情况"
            echo "   2. 定期清理临时文件"
            echo "   3. 限制后台进程"
            echo "   4. 使用轻量级窗口管理器"
            ;;
        "medium")
            echo "ℹ️  中等资源环境，建议："
            echo "   1. 定期监控系统性能"
            echo "   2. 根据需要调整 VNC 参数"
            echo "   3. 考虑使用缓存优化"
            ;;
        *)
            echo "✅ 资源充足，可以使用标准配置"
            ;;
    esac
    
    # 通用优化建议
    echo ""
    echo "=== 通用优化建议 ==="
    echo "1. 容器资源限制："
    echo "   docker run --memory=512m --cpus=1.0 ..."
    echo ""
    echo "2. 环境变量优化："
    echo "   -e VNC_AUTO_LOWRES=1"
    echo "   -e VNC_NETWORK_MODE=minimal"
    echo ""
    echo "3. 定期清理："
    echo "   docker exec <container> find /tmp -type f -mtime +1 -delete"
}

# 实时资源监控
monitor_resources() {
    local interval="${1:-10}"
    
    log_info "开始实时资源监控 (间隔: ${interval}s)"
    
    while true; do
        local current_level
        current_level=$(detect_system_resources | tail -1)
        
        local timestamp=$(date -Iseconds)
        local mem_usage=$(free -m | awk 'NR==2{printf "%.1f", ($2-$7)/$2*100}')
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
        local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
        
        echo "[$timestamp] 资源级别: $current_level | 内存: ${mem_usage}% | CPU: ${cpu_usage}% | 负载: ${load_avg}"
        
        # 如果资源级别发生变化，重新生成配置
        if [ -f "$CONFIG_FILE" ]; then
            local old_level=$(grep "资源级别:" "$CONFIG_FILE" | awk '{print $3}')
            if [ "$current_level" != "$old_level" ]; then
                log_warn "资源级别从 $old_level 变更为 $current_level，重新生成配置"
                generate_lowres_config "$current_level"
            fi
        fi
        
        sleep "$interval"
    done
}

# 主函数
main() {
    case "${1:-detect}" in
        "detect")
            echo "=== VNC 低资源优化检测 ==="
            local resource_level
            resource_level=$(detect_system_resources | tail -1)
            generate_lowres_config "$resource_level"
            suggest_system_optimizations "$resource_level"
            ;;
        "monitor")
            monitor_resources "${2:-10}"
            ;;
        "apply")
            if [ -f "$CONFIG_FILE" ]; then
                source "$CONFIG_FILE"
                apply_lowres_config
            else
                log_warn "配置文件不存在，请先运行 'detect' 命令"
                exit 1
            fi
            ;;
        "status")
            echo "=== 当前系统状态 ==="
            detect_system_resources
            
            if [ -f "$CONFIG_FILE" ]; then
                echo ""
                echo "=== 当前优化配置 ==="
                grep "export\|资源级别" "$CONFIG_FILE"
            fi
            ;;
        *)
            echo "用法: $0 [detect|monitor|apply|status]"
            echo "  detect  - 检测系统资源并生成优化配置"
            echo "  monitor - 实时监控系统资源"
            echo "  apply   - 应用优化配置"
            echo "  status  - 显示当前状态"
            exit 1
            ;;
    esac
}

# 确保必要工具存在
for cmd in bc free nproc uptime df; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_warn "工具 '$cmd' 未安装，某些功能可能受限"
    fi
done

main "$@"
