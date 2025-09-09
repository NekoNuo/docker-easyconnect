#!/bin/bash
# 内存优化设置脚本
# 用于配置长期的内存管理和监控

set -euo pipefail

CONTAINER_NAME="${1:-easyconnect-optimized}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色定义
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $*"
}

# 检查 Docker 是否运行
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker 未运行或无权限访问"
        exit 1
    fi
    log_info "Docker 检查通过"
}

# 检查容器是否存在
check_container() {
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_warn "容器 $CONTAINER_NAME 不存在，将使用 docker-compose 启动"
        return 1
    fi
    log_info "容器 $CONTAINER_NAME 已存在"
    return 0
}

# 创建必要的目录
create_directories() {
    log_step "创建必要的目录..."
    
    mkdir -p logs monitoring scripts
    chmod 755 logs monitoring scripts
    
    log_info "目录创建完成"
}

# 设置 cron 任务
setup_cron_jobs() {
    log_step "设置定期清理任务..."
    
    # 创建 cron 脚本
    cat > scripts/memory-cleanup-cron.sh << 'EOF'
#!/bin/bash
# 定期内存清理脚本

CONTAINER_NAME="easyconnect-optimized"
LOG_FILE="/tmp/memory-cleanup-cron.log"

log_with_timestamp() {
    echo "$(date -Iseconds) $*" >> "$LOG_FILE"
}

# 检查容器是否运行
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_with_timestamp "容器 $CONTAINER_NAME 未运行，跳过清理"
    exit 0
fi

# 执行清理
case "${1:-temp}" in
    "temp")
        docker exec "$CONTAINER_NAME" /usr/local/bin/memory-cleanup.sh temp >> "$LOG_FILE" 2>&1
        ;;
    "logs")
        docker exec "$CONTAINER_NAME" /usr/local/bin/memory-cleanup.sh logs >> "$LOG_FILE" 2>&1
        ;;
    "all")
        docker exec "$CONTAINER_NAME" /usr/local/bin/memory-cleanup.sh all >> "$LOG_FILE" 2>&1
        ;;
    "restart")
        log_with_timestamp "重启容器 $CONTAINER_NAME"
        docker restart "$CONTAINER_NAME" >> "$LOG_FILE" 2>&1
        ;;
esac

# 清理旧日志
find /tmp -name "memory-cleanup-cron.log*" -mtime +7 -delete 2>/dev/null || true
EOF

    chmod +x scripts/memory-cleanup-cron.sh
    
    # 创建 crontab 条目
    cat > scripts/crontab-entries.txt << EOF
# EasyConnect 内存优化定期任务
# 每小时清理临时文件
0 * * * * $SCRIPT_DIR/scripts/memory-cleanup-cron.sh temp

# 每6小时清理日志
0 */6 * * * $SCRIPT_DIR/scripts/memory-cleanup-cron.sh logs

# 每天凌晨2点执行完整清理
0 2 * * * $SCRIPT_DIR/scripts/memory-cleanup-cron.sh all

# 每周日凌晨3点重启容器
0 3 * * 0 $SCRIPT_DIR/scripts/memory-cleanup-cron.sh restart
EOF

    log_info "Cron 脚本已创建在 scripts/ 目录"
    log_warn "请手动添加 cron 任务："
    echo -e "${YELLOW}crontab -e${NC}"
    echo "然后添加以下内容："
    cat scripts/crontab-entries.txt
}

# 创建监控脚本
create_monitoring_script() {
    log_step "创建内存监控脚本..."
    
    cat > scripts/monitor-memory.sh << 'EOF'
#!/bin/bash
# 实时内存监控脚本

CONTAINER_NAME="${1:-easyconnect-optimized}"
INTERVAL="${2:-60}"  # 监控间隔（秒）
LOG_FILE="monitoring/memory-monitor.log"

echo "开始监控容器 $CONTAINER_NAME 的内存使用情况..."
echo "监控间隔: ${INTERVAL}秒"
echo "日志文件: $LOG_FILE"
echo "按 Ctrl+C 停止监控"
echo

# 创建日志文件
mkdir -p monitoring
touch "$LOG_FILE"

# 监控循环
while true; do
    timestamp=$(date -Iseconds)
    
    # 检查容器是否运行
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "[$timestamp] 容器 $CONTAINER_NAME 未运行" | tee -a "$LOG_FILE"
        sleep "$INTERVAL"
        continue
    fi
    
    # 获取容器内存使用情况
    container_stats=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" "$CONTAINER_NAME" | tail -1)
    
    # 获取容器内部内存详情
    internal_memory=$(docker exec "$CONTAINER_NAME" free -h 2>/dev/null | head -2 | tail -1)
    
    # 获取进程信息
    top_processes=$(docker exec "$CONTAINER_NAME" ps aux --sort=-%mem 2>/dev/null | head -6 | tail -5)
    
    # 输出到控制台和日志
    {
        echo "=== $timestamp ==="
        echo "容器统计: $container_stats"
        echo "内部内存: $internal_memory"
        echo "内存占用最高的进程:"
        echo "$top_processes"
        echo
    } | tee -a "$LOG_FILE"
    
    # 检查内存使用率
    mem_percent=$(echo "$container_stats" | awk '{print $4}' | sed 's/%//')
    if (( $(echo "$mem_percent > 80" | bc -l) )); then
        echo "⚠️  警告: 内存使用率过高 (${mem_percent}%)" | tee -a "$LOG_FILE"
        
        # 自动执行清理
        echo "执行自动清理..." | tee -a "$LOG_FILE"
        docker exec "$CONTAINER_NAME" /usr/local/bin/memory-cleanup.sh memory >> "$LOG_FILE" 2>&1 || true
    fi
    
    sleep "$INTERVAL"
done
EOF

    chmod +x scripts/monitor-memory.sh
    log_info "内存监控脚本已创建: scripts/monitor-memory.sh"
}

# 创建快速诊断脚本
create_diagnostic_script() {
    log_step "创建快速诊断脚本..."
    
    cat > scripts/diagnose-memory.sh << 'EOF'
#!/bin/bash
# 快速内存诊断脚本

CONTAINER_NAME="${1:-easyconnect-optimized}"

echo "=== EasyConnect 内存诊断报告 ==="
echo "容器名称: $CONTAINER_NAME"
echo "诊断时间: $(date)"
echo

# 检查容器状态
echo "1. 容器状态:"
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "✅ 容器正在运行"
    
    # 容器资源使用
    echo
    echo "2. 容器资源使用:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" "$CONTAINER_NAME"
    
    # 容器内存详情
    echo
    echo "3. 容器内部内存详情:"
    docker exec "$CONTAINER_NAME" free -h
    
    # 进程内存使用
    echo
    echo "4. 内存占用最高的10个进程:"
    docker exec "$CONTAINER_NAME" ps aux --sort=-%mem | head -11
    
    # 磁盘使用
    echo
    echo "5. 磁盘使用情况:"
    docker exec "$CONTAINER_NAME" df -h
    
    # 日志文件大小
    echo
    echo "6. 日志文件大小:"
    docker exec "$CONTAINER_NAME" du -sh /var/log/ /tmp/ ~/.vnc/ 2>/dev/null || echo "无法获取日志文件大小"
    
    # 网络连接
    echo
    echo "7. 网络连接数:"
    docker exec "$CONTAINER_NAME" netstat -an 2>/dev/null | grep ESTABLISHED | wc -l || echo "无法获取网络连接数"
    
    # 文件描述符
    echo
    echo "8. 文件描述符使用:"
    docker exec "$CONTAINER_NAME" lsof 2>/dev/null | wc -l || echo "无法获取文件描述符数量"
    
    # 后台进程
    echo
    echo "9. 后台监控进程:"
    docker exec "$CONTAINER_NAME" pgrep -af "vnc-performance-monitor|vnc-lowres-optimizer|memory-cleanup" || echo "无后台监控进程"
    
else
    echo "❌ 容器未运行"
    echo
    echo "容器历史:"
    docker ps -a --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}"
fi

echo
echo "=== 诊断完成 ==="
EOF

    chmod +x scripts/diagnose-memory.sh
    log_info "快速诊断脚本已创建: scripts/diagnose-memory.sh"
}

# 优化 Docker 配置
optimize_docker_config() {
    log_step "检查 Docker 配置优化..."
    
    # 检查是否有 docker-compose.yml
    if [ -f "docker-compose.yml" ]; then
        log_warn "发现现有的 docker-compose.yml，建议备份后使用优化版本"
        cp docker-compose.yml docker-compose.yml.backup
        log_info "已备份为 docker-compose.yml.backup"
    fi
    
    if [ -f "docker-compose-optimized.yml" ]; then
        log_info "使用优化版 docker-compose 配置"
        ln -sf docker-compose-optimized.yml docker-compose.yml
    fi
}

# 启动优化版容器
start_optimized_container() {
    log_step "启动优化版容器..."
    
    if [ -f "docker-compose.yml" ]; then
        log_info "使用 docker-compose 启动..."
        docker-compose down 2>/dev/null || true
        docker-compose up -d
        
        # 等待容器启动
        sleep 10
        
        if docker ps --format '{{.Names}}' | grep -q "$CONTAINER_NAME"; then
            log_info "✅ 容器启动成功"
        else
            log_error "❌ 容器启动失败"
            docker-compose logs
            return 1
        fi
    else
        log_warn "未找到 docker-compose.yml，请手动启动容器"
    fi
}

# 验证优化效果
verify_optimization() {
    log_step "验证优化效果..."
    
    if ! check_container; then
        log_error "容器未运行，无法验证"
        return 1
    fi
    
    # 检查内存使用
    echo "当前内存使用情况:"
    docker exec "$CONTAINER_NAME" free -h
    
    echo
    echo "运行中的进程:"
    docker exec "$CONTAINER_NAME" ps aux --sort=-%mem | head -6
    
    echo
    echo "后台进程数量:"
    docker exec "$CONTAINER_NAME" ps aux | wc -l
    
    log_info "优化验证完成"
}

# 显示使用说明
show_usage() {
    cat << EOF

=== 内存优化设置完成 ===

📁 创建的文件和目录:
  - logs/                     # 日志目录
  - monitoring/               # 监控数据目录
  - scripts/                  # 脚本目录
  - docker-compose-optimized.yml  # 优化版配置

🔧 可用的脚本:
  - scripts/monitor-memory.sh     # 实时内存监控
  - scripts/diagnose-memory.sh    # 快速诊断
  - scripts/memory-cleanup-cron.sh # 定期清理

📋 使用方法:
  1. 实时监控内存: ./scripts/monitor-memory.sh
  2. 快速诊断: ./scripts/diagnose-memory.sh
  3. 手动清理: docker exec $CONTAINER_NAME /usr/local/bin/memory-cleanup.sh all

⏰ 定期任务:
  请手动添加 cron 任务，参考 scripts/crontab-entries.txt

🚀 启动优化版容器:
  docker-compose up -d

EOF
}

# 主函数
main() {
    echo -e "${BLUE}=== EasyConnect 内存优化设置 ===${NC}"
    echo
    
    check_docker
    create_directories
    setup_cron_jobs
    create_monitoring_script
    create_diagnostic_script
    optimize_docker_config
    
    # 询问是否启动容器
    read -p "是否现在启动优化版容器? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        start_optimized_container
        sleep 5
        verify_optimization
    fi
    
    show_usage
    
    log_info "内存优化设置完成！"
}

# 执行主函数
main "$@"
