#!/bin/bash
# VNC 性能监控脚本

set -euo pipefail

# 配置
VNC_DISPLAY="${VNC_DISPLAY:-:1}"
MONITOR_INTERVAL="${VNC_MONITOR_INTERVAL:-30}"
LOG_FILE="${VNC_LOG_FILE:-/var/log/vnc-performance.log}"
STATS_FILE="/tmp/vnc-stats.json"

# 日志函数
log_info() {
    echo "$(date -Iseconds) [INFO] $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "$(date -Iseconds) [WARN] $*" | tee -a "$LOG_FILE" >&2
}

# 获取 VNC 连接统计
get_vnc_stats() {
    local display="$1"
    local port=$((5900 + ${display#:}))
    
    # 检查 VNC 服务是否运行 (支持 TigerVNC)
    local vnc_pid=""
    if pgrep -f "Xtigervnc.*$display" > /dev/null; then
        vnc_pid=$(pgrep -f "Xtigervnc.*$display" | head -1)
    elif pgrep -f "Xvnc.*$display" > /dev/null; then
        vnc_pid=$(pgrep -f "Xvnc.*$display" | head -1)
    else
        echo "VNC 服务未运行在显示器 $display"
        return 1
    fi

    # 获取连接数
    local connections=$(netstat -an 2>/dev/null | grep ":$port " | grep ESTABLISHED | wc -l)
    local cpu_usage=0
    local mem_usage=0
    local uptime=0
    
    if [ -n "$vnc_pid" ]; then
        # CPU 使用率
        cpu_usage=$(ps -p "$vnc_pid" -o %cpu --no-headers | tr -d ' ' || echo "0")
        
        # 内存使用率 (KB)
        mem_usage=$(ps -p "$vnc_pid" -o rss --no-headers | tr -d ' ' || echo "0")
        
        # 运行时间 (秒)
        uptime=$(ps -p "$vnc_pid" -o etime --no-headers | tr -d ' ' | awk -F: '{
            if (NF==3) print $1*3600 + $2*60 + $3
            else if (NF==2) print $1*60 + $2
            else print $1
        }' || echo "0")
    fi
    
    # 网络统计
    local bytes_in=$(cat /proc/net/dev | grep -E "(eth0|ens)" | head -1 | awk '{print $2}' || echo "0")
    local bytes_out=$(cat /proc/net/dev | grep -E "(eth0|ens)" | head -1 | awk '{print $10}' || echo "0")
    
    # 生成 JSON 统计信息
    cat > "$STATS_FILE" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "display": "$display",
    "port": $port,
    "connections": $connections,
    "process": {
        "pid": ${vnc_pid:-0},
        "cpu_percent": $cpu_usage,
        "memory_kb": $mem_usage,
        "uptime_seconds": $uptime
    },
    "network": {
        "bytes_received": $bytes_in,
        "bytes_sent": $bytes_out
    },
    "performance": {
        "encoding": "${VNC_ENCODING:-tight}",
        "quality": ${VNC_QUALITY:-6},
        "compress": ${VNC_COMPRESS:-6},
        "framerate": ${VNC_FRAMERATE:-30},
        "depth": ${VNC_DEPTH:-24}
    }
}
EOF
    
    echo "连接数: $connections, CPU: ${cpu_usage}%, 内存: ${mem_usage}KB, 运行时间: ${uptime}s"
}

# 性能建议
suggest_optimizations() {
    local connections="$1"
    local cpu_usage="$2"
    local mem_usage="$3"
    
    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        log_warn "CPU 使用率过高 (${cpu_usage}%), 建议:"
        log_warn "  - 降低帧率: export VNC_FRAMERATE=15"
        log_warn "  - 使用更高压缩: export VNC_COMPRESS=9"
        log_warn "  - 降低色彩深度: export VNC_DEPTH=16"
    fi
    
    if (( mem_usage > 500000 )); then  # 500MB
        log_warn "内存使用过高 (${mem_usage}KB), 建议:"
        log_warn "  - 降低分辨率: export VNC_SIZE=800x600"
        log_warn "  - 降低色彩深度: export VNC_DEPTH=16"
    fi
    
    if (( connections > 3 )); then
        log_warn "连接数较多 ($connections), 建议:"
        log_warn "  - 限制并发连接数"
        log_warn "  - 使用负载均衡"
    fi
    
    if (( connections == 0 )); then
        log_info "当前无活动连接，可以考虑降低资源使用"
    fi
}

# 自动优化
auto_optimize() {
    local cpu_usage="$1"
    local connections="$2"
    
    if [ "$VNC_AUTO_OPTIMIZE" = "1" ]; then
        if (( $(echo "$cpu_usage > 90" | bc -l) )); then
            log_info "自动优化: CPU 使用率过高，调整参数"
            # 这里可以动态调整 VNC 参数
            # 注意：需要重启 VNC 服务才能生效
        fi
    fi
}

# 主监控循环
monitor_vnc() {
    log_info "开始 VNC 性能监控 (间隔: ${MONITOR_INTERVAL}s)"
    
    while true; do
        if stats_output=$(get_vnc_stats "$VNC_DISPLAY" 2>&1); then
            log_info "VNC 统计: $stats_output"
            
            # 读取统计数据
            if [ -f "$STATS_FILE" ]; then
                connections=$(jq -r '.connections' "$STATS_FILE" 2>/dev/null || echo "0")
                cpu_usage=$(jq -r '.process.cpu_percent' "$STATS_FILE" 2>/dev/null || echo "0")
                mem_usage=$(jq -r '.process.memory_kb' "$STATS_FILE" 2>/dev/null || echo "0")
                
                # 性能建议
                suggest_optimizations "$connections" "$cpu_usage" "$mem_usage"
                
                # 自动优化
                auto_optimize "$cpu_usage" "$connections"
            fi
        else
            log_warn "无法获取 VNC 统计信息: $stats_output"
        fi
        
        sleep "$MONITOR_INTERVAL"
    done
}

# 显示当前状态
show_status() {
    echo "=== VNC 性能状态 ==="
    get_vnc_stats "$VNC_DISPLAY" || echo "VNC 服务未运行"
    
    if [ -f "$STATS_FILE" ]; then
        echo ""
        echo "=== 详细统计 ==="
        jq . "$STATS_FILE" 2>/dev/null || cat "$STATS_FILE"
    fi
}

# 主函数
main() {
    case "${1:-monitor}" in
        "monitor")
            monitor_vnc
            ;;
        "status")
            show_status
            ;;
        "stats")
            get_vnc_stats "$VNC_DISPLAY"
            ;;
        *)
            echo "用法: $0 [monitor|status|stats]"
            echo "  monitor - 持续监控 VNC 性能"
            echo "  status  - 显示当前状态"
            echo "  stats   - 显示统计信息"
            exit 1
            ;;
    esac
}

# 确保必要的工具存在
command -v jq >/dev/null 2>&1 || {
    echo "警告: jq 未安装，JSON 功能将受限"
}

command -v bc >/dev/null 2>&1 || {
    echo "警告: bc 未安装，数值比较功能将受限"
}

main "$@"
