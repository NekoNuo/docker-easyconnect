#!/bin/bash
# VNC 轻量级性能监控脚本
# 专为低内存环境设计，最小化资源占用

set -euo pipefail

# 配置
VNC_DISPLAY="${VNC_DISPLAY:-:1}"
MONITOR_INTERVAL="${VNC_MONITOR_INTERVAL:-60}"  # 默认60秒，减少频率
LOG_FILE="${VNC_LOG_FILE:-/var/log/vnc-lite.log}"
MAX_LOG_SIZE=1048576  # 1MB 日志大小限制

# 轻量级日志函数（避免使用 tee）
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [VNC-LITE] $*" >> "$LOG_FILE"
    # 控制日志文件大小
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
        tail -n 100 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
}

# 轻量级 VNC 状态检查（避免使用 jq 和复杂命令）
check_vnc_lite() {
    local display="$1"
    local port=$((5900 + ${display#:}))
    
    # 检查 VNC 进程是否存在
    if ! pgrep -f "Xtigervnc.*$display" > /dev/null 2>&1; then
        echo "VNC_DOWN"
        return 1
    fi
    
    # 简单的连接数检查（避免使用 netstat）
    local connections=0
    if [ -f "/proc/net/tcp" ]; then
        # 将端口转换为十六进制
        local hex_port=$(printf "%04X" $port)
        connections=$(grep ":${hex_port} " /proc/net/tcp 2>/dev/null | grep -c " 01 " || echo "0")
    fi
    
    # 获取 VNC 进程的基本信息（避免复杂的 ps 命令）
    local vnc_pid=$(pgrep -f "Xtigervnc.*$display" | head -1)
    local mem_kb=0
    local cpu_percent=0
    
    if [ -n "$vnc_pid" ] && [ -f "/proc/$vnc_pid/status" ]; then
        mem_kb=$(grep "VmRSS:" "/proc/$vnc_pid/status" 2>/dev/null | awk '{print $2}' || echo "0")
        # 简化的 CPU 使用率检查（避免复杂计算）
        if [ -f "/proc/$vnc_pid/stat" ]; then
            cpu_percent=$(awk '{print int(($14+$15)/100)}' "/proc/$vnc_pid/stat" 2>/dev/null || echo "0")
        fi
    fi
    
    echo "VNC_OK:$connections:$mem_kb:$cpu_percent"
}

# 轻量级自动优化（只在必要时执行）
auto_optimize_lite() {
    local connections="$1"
    local mem_kb="$2"
    local cpu_percent="$3"
    
    # 只在资源使用过高时才优化
    local need_optimize=0
    
    # 内存使用超过 100MB 时优化
    if [ "$mem_kb" -gt 102400 ]; then
        need_optimize=1
        log_info "内存使用过高: ${mem_kb}KB，启动优化"
    fi
    
    # CPU 使用率超过 50% 时优化
    if [ "$cpu_percent" -gt 50 ]; then
        need_optimize=1
        log_info "CPU 使用过高: ${cpu_percent}%，启动优化"
    fi
    
    # 执行轻量级优化
    if [ "$need_optimize" = "1" ]; then
        # 清理系统缓存
        sync
        echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
        
        # 记录优化操作
        log_info "执行轻量级优化: 清理系统缓存"
        
        # 避免频繁优化
        touch /tmp/vnc-last-optimize
    fi
}

# 检查是否需要运行（避免重复实例）
check_running() {
    local pidfile="/tmp/vnc-monitor-lite.pid"
    
    if [ -f "$pidfile" ]; then
        local old_pid=$(cat "$pidfile")
        if kill -0 "$old_pid" 2>/dev/null; then
            echo "监控脚本已在运行 (PID: $old_pid)"
            exit 0
        fi
    fi
    
    echo $$ > "$pidfile"
    
    # 清理函数
    cleanup() {
        rm -f "$pidfile"
        exit 0
    }
    
    trap cleanup EXIT INT TERM
}

# 主监控循环（轻量级）
monitor_lite() {
    log_info "开始轻量级 VNC 监控 (间隔: ${MONITOR_INTERVAL}s)"
    
    local error_count=0
    local max_errors=5
    
    while true; do
        if result=$(check_vnc_lite "$VNC_DISPLAY" 2>&1); then
            case "$result" in
                VNC_DOWN)
                    log_info "VNC 服务未运行"
                    error_count=$((error_count + 1))
                    ;;
                VNC_OK:*)
                    # 解析结果
                    IFS=':' read -r status connections mem_kb cpu_percent <<< "$result"
                    
                    # 只在有连接或资源使用异常时记录
                    if [ "$connections" -gt 0 ] || [ "$mem_kb" -gt 51200 ] || [ "$cpu_percent" -gt 25 ]; then
                        log_info "VNC 状态: 连接=$connections, 内存=${mem_kb}KB, CPU=${cpu_percent}%"
                    fi
                    
                    # 自动优化
                    auto_optimize_lite "$connections" "$mem_kb" "$cpu_percent"
                    
                    error_count=0
                    ;;
            esac
        else
            log_info "监控检查失败: $result"
            error_count=$((error_count + 1))
        fi
        
        # 连续错误过多时退出
        if [ "$error_count" -ge "$max_errors" ]; then
            log_info "连续错误过多，退出监控"
            break
        fi
        
        sleep "$MONITOR_INTERVAL"
    done
}

# 显示状态（一次性检查）
show_status() {
    echo "=== VNC 轻量级状态 ==="
    
    if result=$(check_vnc_lite "$VNC_DISPLAY" 2>&1); then
        case "$result" in
            VNC_DOWN)
                echo "VNC 状态: 未运行"
                ;;
            VNC_OK:*)
                IFS=':' read -r status connections mem_kb cpu_percent <<< "$result"
                echo "VNC 状态: 运行中"
                echo "活动连接: $connections"
                echo "内存使用: ${mem_kb}KB ($(($mem_kb/1024))MB)"
                echo "CPU 使用: ${cpu_percent}%"
                ;;
        esac
    else
        echo "状态检查失败: $result"
    fi
    
    # 显示系统内存
    if [ -f "/proc/meminfo" ]; then
        local total_mem=$(grep "MemTotal:" /proc/meminfo | awk '{print int($2/1024)}')
        local free_mem=$(grep "MemAvailable:" /proc/meminfo | awk '{print int($2/1024)}')
        local used_mem=$((total_mem - free_mem))
        echo "系统内存: ${used_mem}MB / ${total_mem}MB"
    fi
}

# 主函数
main() {
    local action="${1:-monitor}"
    
    case "$action" in
        "monitor")
            check_running
            monitor_lite
            ;;
        "status")
            show_status
            ;;
        "stop")
            if [ -f "/tmp/vnc-monitor-lite.pid" ]; then
                local pid=$(cat "/tmp/vnc-monitor-lite.pid")
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid"
                    echo "轻量级监控已停止"
                else
                    echo "监控未运行"
                fi
                rm -f "/tmp/vnc-monitor-lite.pid"
            else
                echo "监控未运行"
            fi
            ;;
        *)
            echo "用法: $0 [monitor|status|stop]"
            echo "  monitor - 启动轻量级监控"
            echo "  status  - 显示当前状态"
            echo "  stop    - 停止监控"
            exit 1
            ;;
    esac
}

# 如果直接执行脚本
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
