#!/bin/bash
# 内存优化脚本
# 专门用于优化 docker-easyconnect 的内存使用

set -euo pipefail

# 配置
LOG_FILE="/var/log/memory-optimizer.log"
MEMORY_THRESHOLD_MB=400  # 内存使用超过400MB时触发优化

# 日志函数
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [MEM-OPT] $*" | tee -a "$LOG_FILE"
}

# 获取当前内存使用情况
get_memory_usage() {
    if [ -f "/proc/meminfo" ]; then
        local total_kb=$(grep "MemTotal:" /proc/meminfo | awk '{print $2}')
        local available_kb=$(grep "MemAvailable:" /proc/meminfo | awk '{print $2}')
        local used_kb=$((total_kb - available_kb))
        
        echo "$used_kb:$total_kb"
    else
        echo "0:0"
    fi
}

# 获取进程内存使用
get_process_memory() {
    local process_name="$1"
    local total_mem=0
    
    for pid in $(pgrep -f "$process_name" 2>/dev/null || true); do
        if [ -f "/proc/$pid/status" ]; then
            local mem_kb=$(grep "VmRSS:" "/proc/$pid/status" 2>/dev/null | awk '{print $2}' || echo "0")
            total_mem=$((total_mem + mem_kb))
        fi
    done
    
    echo "$total_mem"
}

# 清理系统缓存
cleanup_system_cache() {
    log_info "清理系统缓存..."
    
    # 同步文件系统
    sync
    
    # 清理页面缓存
    echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
    
    # 清理临时文件
    find /tmp -type f -name "*.tmp" -mtime +1 -delete 2>/dev/null || true
    find /tmp -type f -name "vnc-stats*" -mtime +0 -delete 2>/dev/null || true
    
    log_info "系统缓存清理完成"
}

# 优化 VNC 设置
optimize_vnc_settings() {
    log_info "优化 VNC 设置..."
    
    # 检查当前 VNC 内存使用
    local vnc_mem_kb=$(get_process_memory "Xtigervnc")
    local vnc_mem_mb=$((vnc_mem_kb / 1024))
    
    log_info "VNC 进程内存使用: ${vnc_mem_mb}MB"
    
    # 如果 VNC 内存使用过高，建议优化
    if [ "$vnc_mem_mb" -gt 100 ]; then
        log_info "VNC 内存使用过高，建议降低分辨率或色彩深度"
        
        # 创建优化建议文件
        cat > /tmp/vnc-memory-suggestions.txt << EOF
VNC 内存优化建议:
1. 降低分辨率: export VNC_SIZE=640x480
2. 降低色彩深度: export VNC_DEPTH=16
3. 禁用自动优化: export VNC_AUTO_OPTIMIZE=0
4. 使用轻量级监控: export VNC_LITE_MODE=1
EOF
    fi
}

# 停止不必要的进程
stop_unnecessary_processes() {
    log_info "检查并停止不必要的进程..."
    
    # 停止重量级监控进程
    for process in "vnc-performance-monitor" "vnc-auto-optimizer"; do
        local pids=$(pgrep -f "$process" 2>/dev/null || true)
        if [ -n "$pids" ]; then
            log_info "停止进程: $process"
            echo "$pids" | xargs kill -TERM 2>/dev/null || true
            sleep 2
            echo "$pids" | xargs kill -KILL 2>/dev/null || true
        fi
    done
    
    # 清理僵尸进程
    local zombie_count=$(ps aux | awk '$8 ~ /^Z/ { count++ } END { print count+0 }')
    if [ "$zombie_count" -gt 0 ]; then
        log_info "发现 $zombie_count 个僵尸进程"
    fi
}

# 内存压缩优化
optimize_memory_settings() {
    log_info "优化内存设置..."
    
    # 调整 swappiness（如果可能）
    if [ -w "/proc/sys/vm/swappiness" ]; then
        echo 10 > /proc/sys/vm/swappiness 2>/dev/null || true
        log_info "调整 swappiness 为 10"
    fi
    
    # 调整内存回收策略
    if [ -w "/proc/sys/vm/vfs_cache_pressure" ]; then
        echo 50 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null || true
        log_info "调整 vfs_cache_pressure 为 50"
    fi
}

# 生成内存报告
generate_memory_report() {
    log_info "生成内存使用报告..."
    
    local report_file="/tmp/memory-report.txt"
    
    cat > "$report_file" << EOF
=== 内存使用报告 ===
生成时间: $(date)

系统内存:
$(cat /proc/meminfo | grep -E "(MemTotal|MemAvailable|MemFree|Buffers|Cached)" || echo "无法获取内存信息")

主要进程内存使用:
EOF
    
    # 添加主要进程的内存使用
    for process in "Xtigervnc" "easyconnect" "sangfor" "flwm"; do
        local mem_kb=$(get_process_memory "$process")
        if [ "$mem_kb" -gt 0 ]; then
            local mem_mb=$((mem_kb / 1024))
            echo "$process: ${mem_mb}MB" >> "$report_file"
        fi
    done
    
    echo "" >> "$report_file"
    echo "详细进程列表:" >> "$report_file"
    ps aux --sort=-%mem | head -10 >> "$report_file" 2>/dev/null || echo "无法获取进程信息" >> "$report_file"
    
    log_info "内存报告已生成: $report_file"
}

# 自动优化
auto_optimize() {
    log_info "开始自动内存优化..."
    
    # 获取当前内存使用
    local mem_info=$(get_memory_usage)
    local used_kb=$(echo "$mem_info" | cut -d: -f1)
    local total_kb=$(echo "$mem_info" | cut -d: -f2)
    local used_mb=$((used_kb / 1024))
    local total_mb=$((total_kb / 1024))
    
    log_info "当前内存使用: ${used_mb}MB / ${total_mb}MB"
    
    # 如果内存使用超过阈值，执行优化
    if [ "$used_mb" -gt "$MEMORY_THRESHOLD_MB" ]; then
        log_info "内存使用超过阈值 (${MEMORY_THRESHOLD_MB}MB)，开始优化..."
        
        cleanup_system_cache
        stop_unnecessary_processes
        optimize_vnc_settings
        optimize_memory_settings
        
        # 等待一下再检查
        sleep 5
        
        local new_mem_info=$(get_memory_usage)
        local new_used_kb=$(echo "$new_mem_info" | cut -d: -f1)
        local new_used_mb=$((new_used_kb / 1024))
        local saved_mb=$((used_mb - new_used_mb))
        
        log_info "优化完成，节省内存: ${saved_mb}MB"
        log_info "优化后内存使用: ${new_used_mb}MB / ${total_mb}MB"
    else
        log_info "内存使用正常，无需优化"
    fi
}

# 轻量级模式配置
setup_lite_mode() {
    log_info "配置轻量级模式..."
    
    # 创建轻量级配置文件
    cat > /tmp/vnc-lite-config << EOF
# VNC 轻量级模式配置
export VNC_AUTO_OPTIMIZE=0
export VNC_SMART_OPTIMIZE=0
export VNC_LITE_MODE=1
export VNC_MONITOR_INTERVAL=120
export VNC_SIZE=640x480
export VNC_DEPTH=16
export VNC_QUALITY=2
export VNC_COMPRESS=9
export VNC_FRAMERATE=15
EOF
    
    log_info "轻量级模式配置已创建: /tmp/vnc-lite-config"
    log_info "使用方法: source /tmp/vnc-lite-config"
}

# 主函数
main() {
    local action="${1:-auto}"
    
    case "$action" in
        "auto")
            auto_optimize
            ;;
        "report")
            generate_memory_report
            ;;
        "cleanup")
            cleanup_system_cache
            ;;
        "stop-monitors")
            stop_unnecessary_processes
            ;;
        "lite-mode")
            setup_lite_mode
            ;;
        "optimize-vnc")
            optimize_vnc_settings
            ;;
        *)
            echo "用法: $0 [auto|report|cleanup|stop-monitors|lite-mode|optimize-vnc]"
            echo "  auto         - 自动内存优化"
            echo "  report       - 生成内存使用报告"
            echo "  cleanup      - 清理系统缓存"
            echo "  stop-monitors - 停止监控进程"
            echo "  lite-mode    - 配置轻量级模式"
            echo "  optimize-vnc - 优化 VNC 设置"
            exit 1
            ;;
    esac
}

# 如果直接执行脚本
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
