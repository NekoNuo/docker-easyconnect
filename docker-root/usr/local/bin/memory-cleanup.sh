#!/bin/bash
# 内存清理和优化脚本
# 用于定期清理内存泄露和临时文件

set -euo pipefail

# 配置
LOG_FILE="/var/log/memory-cleanup.log"
MAX_LOG_SIZE="50M"
TEMP_FILE_AGE="+1"  # 删除1天前的临时文件
VNC_LOG_AGE="+7"    # 删除7天前的VNC日志

# 日志函数
log_info() {
    echo "$(date -Iseconds) [INFO] $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "$(date -Iseconds) [WARN] $*" | tee -a "$LOG_FILE" >&2
}

# 清理日志文件
cleanup_logs() {
    log_info "开始清理日志文件..."
    
    # 清理 VNC 性能日志
    if [ -f "/var/log/vnc-performance.log" ]; then
        local size=$(stat -c%s "/var/log/vnc-performance.log" 2>/dev/null || echo 0)
        if [ "$size" -gt 52428800 ]; then  # 50MB
            log_warn "VNC 性能日志过大 (${size} bytes)，截断到最后1000行"
            tail -1000 "/var/log/vnc-performance.log" > "/tmp/vnc-perf.tmp"
            mv "/tmp/vnc-perf.tmp" "/var/log/vnc-performance.log"
        fi
    fi
    
    # 清理旧的 VNC 日志
    find ~/.vnc -name "*.log" -mtime $VNC_LOG_AGE -delete 2>/dev/null || true
    
    # 清理系统日志
    find /var/log -name "*.log" -size +$MAX_LOG_SIZE -exec truncate -s 10M {} \; 2>/dev/null || true
    
    log_info "日志清理完成"
}

# 清理临时文件
cleanup_temp_files() {
    log_info "开始清理临时文件..."
    
    # 清理 VNC 相关临时文件
    find /tmp -name "vnc-*.json" -mtime $TEMP_FILE_AGE -delete 2>/dev/null || true
    find /tmp -name "vnc-*.config" -mtime $TEMP_FILE_AGE -delete 2>/dev/null || true
    find /tmp -name "vnc-runtime-*" -mtime $TEMP_FILE_AGE -delete 2>/dev/null || true
    
    # 清理一般临时文件（保留重要的系统文件）
    find /tmp -type f -mtime $TEMP_FILE_AGE ! -path "/tmp/.X11-unix/*" ! -name "EXIT_LOCK" -delete 2>/dev/null || true
    
    # 清理空目录
    find /tmp -type d -empty -delete 2>/dev/null || true
    
    log_info "临时文件清理完成"
}

# 内存优化
optimize_memory() {
    log_info "开始内存优化..."
    
    # 清理页面缓存（谨慎使用）
    if [ -w /proc/sys/vm/drop_caches ]; then
        sync
        echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
        log_info "已清理页面缓存"
    fi
    
    # 检查内存使用情况
    local mem_info=$(free -m)
    local mem_used=$(echo "$mem_info" | awk 'NR==2{print $3}')
    local mem_total=$(echo "$mem_info" | awk 'NR==2{print $2}')
    local mem_percent=$((mem_used * 100 / mem_total))
    
    log_info "当前内存使用: ${mem_used}MB/${mem_total}MB (${mem_percent}%)"
    
    if [ "$mem_percent" -gt 80 ]; then
        log_warn "内存使用率过高 (${mem_percent}%)，建议检查进程"
        ps aux --sort=-%mem | head -10 | tee -a "$LOG_FILE"
    fi
}

# 进程清理
cleanup_processes() {
    log_info "检查僵尸进程..."
    
    # 查找僵尸进程
    local zombies=$(ps aux | awk '$8 ~ /^Z/ { print $2 }')
    if [ -n "$zombies" ]; then
        log_warn "发现僵尸进程: $zombies"
        # 尝试清理僵尸进程的父进程
        for pid in $zombies; do
            local ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
            if [ -n "$ppid" ] && [ "$ppid" != "1" ]; then
                log_info "尝试重启父进程 $ppid"
                kill -HUP "$ppid" 2>/dev/null || true
            fi
        done
    fi
    
    # 检查长时间运行的监控进程
    local monitor_procs=$(pgrep -af "vnc-performance-monitor|vnc-lowres-optimizer" | wc -l)
    if [ "$monitor_procs" -gt 2 ]; then
        log_warn "发现过多监控进程 ($monitor_procs 个)，可能存在进程泄露"
    fi
}

# 磁盘空间检查
check_disk_space() {
    log_info "检查磁盘空间..."
    
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    log_info "根分区使用率: ${disk_usage}%"
    
    if [ "$disk_usage" -gt 85 ]; then
        log_warn "磁盘空间不足 (${disk_usage}%)，开始紧急清理"
        
        # 紧急清理大文件
        find /var/log -name "*.log" -size +100M -exec truncate -s 50M {} \;
        find /tmp -type f -size +10M -mtime +0 -delete 2>/dev/null || true
        
        # 清理 VNC 日志
        find ~/.vnc -name "*.log" -size +10M -delete 2>/dev/null || true
    fi
}

# 生成系统报告
generate_report() {
    log_info "=== 系统状态报告 ==="
    
    # 内存信息
    log_info "内存使用情况:"
    free -h | tee -a "$LOG_FILE"
    
    # 磁盘信息
    log_info "磁盘使用情况:"
    df -h | tee -a "$LOG_FILE"
    
    # 进程信息
    log_info "内存占用最高的5个进程:"
    ps aux --sort=-%mem | head -6 | tee -a "$LOG_FILE"
    
    # 文件描述符
    local fd_count=$(lsof 2>/dev/null | wc -l)
    log_info "当前文件描述符数量: $fd_count"
    
    # 网络连接
    local conn_count=$(netstat -an 2>/dev/null | grep ESTABLISHED | wc -l)
    log_info "当前网络连接数: $conn_count"
}

# 主函数
main() {
    case "${1:-all}" in
        "logs")
            cleanup_logs
            ;;
        "temp")
            cleanup_temp_files
            ;;
        "memory")
            optimize_memory
            ;;
        "processes")
            cleanup_processes
            ;;
        "disk")
            check_disk_space
            ;;
        "report")
            generate_report
            ;;
        "all")
            log_info "开始完整的内存清理和优化..."
            cleanup_logs
            cleanup_temp_files
            cleanup_processes
            optimize_memory
            check_disk_space
            generate_report
            log_info "内存清理和优化完成"
            ;;
        *)
            echo "用法: $0 [logs|temp|memory|processes|disk|report|all]"
            echo "  logs      - 清理日志文件"
            echo "  temp      - 清理临时文件"
            echo "  memory    - 内存优化"
            echo "  processes - 进程清理"
            echo "  disk      - 磁盘空间检查"
            echo "  report    - 生成系统报告"
            echo "  all       - 执行所有清理操作（默认）"
            exit 1
            ;;
    esac
}

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"

# 执行主函数
main "$@"
