#!/bin/bash
# VNC 智能自动优化守护进程
# 提供实时监控和智能优化功能

set -euo pipefail

# 配置
VNC_DISPLAY="${VNC_DISPLAY:-:1}"
MONITOR_INTERVAL="${VNC_MONITOR_INTERVAL:-15}"
LOG_FILE="${VNC_LOG_FILE:-/var/log/vnc-auto-optimizer.log}"
OPTIMIZATION_HISTORY="/tmp/vnc-optimization-history.log"
STATE_FILE="/tmp/vnc-optimizer-state.json"

# 优化配置
MIN_OPTIMIZE_INTERVAL=60    # 最小优化间隔（秒）
MAX_OPTIMIZE_LEVEL=3        # 最大优化级别
PRESSURE_THRESHOLD_LIGHT=15 # 轻度优化阈值
PRESSURE_THRESHOLD_MEDIUM=35 # 中度优化阈值
PRESSURE_THRESHOLD_HEAVY=55  # 重度优化阈值

# 滑动窗口配置
WINDOW_SIZE=5               # 滑动窗口大小
declare -a CPU_WINDOW=()
declare -a MEM_WINDOW=()
declare -a CONN_WINDOW=()

# 日志函数
log_info() {
    echo "$(date -Iseconds) [INFO] $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "$(date -Iseconds) [WARN] $*" | tee -a "$LOG_FILE" >&2
}

log_debug() {
    if [ "${VNC_DEBUG:-0}" = "1" ]; then
        echo "$(date -Iseconds) [DEBUG] $*" | tee -a "$LOG_FILE"
    fi
}

# 初始化状态文件
init_state() {
    cat > "$STATE_FILE" << EOF
{
    "current_level": 0,
    "last_optimize_time": 0,
    "optimization_count": 0,
    "pressure_history": [],
    "active_optimizations": {}
}
EOF
    log_info "优化器状态已初始化"
}

# 读取状态
read_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        init_state
        cat "$STATE_FILE"
    fi
}

# 更新状态
update_state() {
    local key="$1"
    local value="$2"
    
    if command -v jq >/dev/null 2>&1; then
        local temp_file=$(mktemp)
        jq ".$key = $value" "$STATE_FILE" > "$temp_file" && mv "$temp_file" "$STATE_FILE"
    else
        log_warn "jq 未安装，状态更新功能受限"
    fi
}

# 滑动窗口更新
update_window() {
    local -n window_ref=$1
    local new_value=$2
    
    # 添加新值
    window_ref+=("$new_value")
    
    # 保持窗口大小
    if [ ${#window_ref[@]} -gt $WINDOW_SIZE ]; then
        window_ref=("${window_ref[@]:1}")
    fi
}

# 计算滑动窗口平均值
calculate_window_average() {
    local -n window_ref=$1
    local sum=0
    local count=${#window_ref[@]}
    
    if [ $count -eq 0 ]; then
        echo "0"
        return
    fi
    
    for value in "${window_ref[@]}"; do
        sum=$(echo "$sum + $value" | bc -l)
    done
    
    echo "scale=2; $sum / $count" | bc -l
}

# 获取系统资源状态
get_system_resources() {
    local vnc_pid=""
    local port=$((5900 + ${VNC_DISPLAY#:}))
    
    # 查找 VNC 进程
    if pgrep -f "Xtigervnc.*$VNC_DISPLAY" > /dev/null; then
        vnc_pid=$(pgrep -f "Xtigervnc.*$VNC_DISPLAY" | head -1)
    elif pgrep -f "Xvnc.*$VNC_DISPLAY" > /dev/null; then
        vnc_pid=$(pgrep -f "Xvnc.*$VNC_DISPLAY" | head -1)
    fi
    
    # 获取连接数
    local connections=$(netstat -an 2>/dev/null | grep ":$port " | grep ESTABLISHED | wc -l)
    
    # 获取 VNC 进程资源使用
    local cpu_usage=0
    local mem_usage=0
    if [ -n "$vnc_pid" ]; then
        cpu_usage=$(ps -p "$vnc_pid" -o %cpu --no-headers | tr -d ' ' || echo "0")
        mem_usage=$(ps -p "$vnc_pid" -o rss --no-headers | tr -d ' ' || echo "0")
    fi
    
    # 获取系统整体资源
    local system_cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' || echo "0")
    local system_mem_percent=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
    
    # 输出 JSON 格式
    cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "vnc_process": {
        "pid": ${vnc_pid:-0},
        "cpu_percent": $cpu_usage,
        "memory_kb": $mem_usage
    },
    "system": {
        "cpu_percent": $system_cpu,
        "memory_percent": $system_mem_percent,
        "load_average": $load_avg
    },
    "connections": $connections
}
EOF
}

# 计算资源压力指数
calculate_pressure_score() {
    local cpu_avg="$1"
    local mem_avg="$2"
    local conn_avg="$3"
    local system_cpu="$4"
    local system_mem="$5"
    local load_avg="$6"
    
    local pressure_score=0
    local reasons=()
    
    # VNC 进程 CPU 压力
    if (( $(echo "$cpu_avg > 80" | bc -l) )); then
        pressure_score=$((pressure_score + 25))
        reasons+=("VNC_CPU:${cpu_avg}%")
    elif (( $(echo "$cpu_avg > 50" | bc -l) )); then
        pressure_score=$((pressure_score + 15))
        reasons+=("VNC_CPU:${cpu_avg}%")
    elif (( $(echo "$cpu_avg > 30" | bc -l) )); then
        pressure_score=$((pressure_score + 8))
        reasons+=("VNC_CPU:${cpu_avg}%")
    fi
    
    # 系统 CPU 压力
    if (( $(echo "$system_cpu > 90" | bc -l) )); then
        pressure_score=$((pressure_score + 20))
        reasons+=("SYS_CPU:${system_cpu}%")
    elif (( $(echo "$system_cpu > 70" | bc -l) )); then
        pressure_score=$((pressure_score + 12))
        reasons+=("SYS_CPU:${system_cpu}%")
    fi
    
    # 内存压力
    local mem_mb=$((${mem_avg%.*} / 1024))
    if (( mem_mb > 800 )); then
        pressure_score=$((pressure_score + 20))
        reasons+=("MEM:${mem_mb}MB")
    elif (( mem_mb > 500 )); then
        pressure_score=$((pressure_score + 12))
        reasons+=("MEM:${mem_mb}MB")
    elif (( mem_mb > 300 )); then
        pressure_score=$((pressure_score + 6))
        reasons+=("MEM:${mem_mb}MB")
    fi
    
    # 系统内存压力
    if (( $(echo "$system_mem > 85" | bc -l) )); then
        pressure_score=$((pressure_score + 15))
        reasons+=("SYS_MEM:${system_mem}%")
    elif (( $(echo "$system_mem > 70" | bc -l) )); then
        pressure_score=$((pressure_score + 8))
        reasons+=("SYS_MEM:${system_mem}%")
    fi
    
    # 连接数压力
    local conn_count=${conn_avg%.*}
    if (( conn_count > 5 )); then
        pressure_score=$((pressure_score + 12))
        reasons+=("CONN:${conn_count}")
    elif (( conn_count > 3 )); then
        pressure_score=$((pressure_score + 6))
        reasons+=("CONN:${conn_count}")
    fi
    
    # 系统负载压力
    if (( $(echo "$load_avg > 3" | bc -l) )); then
        pressure_score=$((pressure_score + 15))
        reasons+=("LOAD:${load_avg}")
    elif (( $(echo "$load_avg > 2" | bc -l) )); then
        pressure_score=$((pressure_score + 8))
        reasons+=("LOAD:${load_avg}")
    fi
    
    echo "$pressure_score|$(IFS=,; echo "${reasons[*]}")"
}

# 应用优化配置
apply_optimization() {
    local level="$1"
    local reason="$2"
    local current_time=$(date +%s)
    
    log_info "应用优化级别 $level - 原因: $reason"
    
    # 生成优化配置
    local config_file="/tmp/vnc-auto-config-$current_time"
    
    case "$level" in
        1) # 轻度优化
            cat > "$config_file" << EOF
export VNC_FRAMERATE=25
export VNC_QUALITY=5
export VNC_COMPRESS=7
export VNC_DEFERTIME=5
EOF
            ;;
        2) # 中度优化
            cat > "$config_file" << EOF
export VNC_FRAMERATE=18
export VNC_QUALITY=3
export VNC_COMPRESS=8
export VNC_DEFERTIME=25
export VNC_DEPTH=16
EOF
            ;;
        3) # 重度优化
            cat > "$config_file" << EOF
export VNC_FRAMERATE=10
export VNC_QUALITY=1
export VNC_COMPRESS=9
export VNC_DEFERTIME=80
export VNC_DEPTH=8
export VNC_SIZE=800x600
EOF
            ;;
    esac
    
    # 应用配置
    if [ -f "$config_file" ]; then
        source "$config_file"
        
        # 记录优化历史
        echo "$(date -Iseconds)|level_$level|$reason|$(cat $config_file | grep export | tr '\n' ';')" >> "$OPTIMIZATION_HISTORY"
        
        # 更新状态
        update_state "current_level" "$level"
        update_state "last_optimize_time" "$current_time"
        
        log_info "优化级别 $level 应用成功"
        rm -f "$config_file"
        return 0
    else
        log_warn "优化配置生成失败"
        return 1
    fi
}

# 智能优化决策
intelligent_decision() {
    local pressure_score="$1"
    local reasons="$2"
    local current_time=$(date +%s)

    # 读取当前状态
    local current_level=0
    local last_optimize_time=0

    if [ -f "$STATE_FILE" ] && command -v jq >/dev/null 2>&1; then
        current_level=$(jq -r '.current_level' "$STATE_FILE" 2>/dev/null || echo "0")
        last_optimize_time=$(jq -r '.last_optimize_time' "$STATE_FILE" 2>/dev/null || echo "0")
    fi

    local time_diff=$((current_time - last_optimize_time))

    # 检查最小间隔
    if [ "$time_diff" -lt "$MIN_OPTIMIZE_INTERVAL" ]; then
        log_debug "距离上次优化时间过短 (${time_diff}s < ${MIN_OPTIMIZE_INTERVAL}s)，跳过优化"
        return 0
    fi

    # 确定目标优化级别
    local target_level=0
    if (( pressure_score >= PRESSURE_THRESHOLD_HEAVY )); then
        target_level=3
    elif (( pressure_score >= PRESSURE_THRESHOLD_MEDIUM )); then
        target_level=2
    elif (( pressure_score >= PRESSURE_THRESHOLD_LIGHT )); then
        target_level=1
    fi

    log_debug "压力评分: $pressure_score, 当前级别: $current_level, 目标级别: $target_level"

    # 决策逻辑
    if [ "$target_level" -gt "$current_level" ]; then
        # 需要升级优化
        log_info "资源压力增加，升级优化级别: $current_level -> $target_level"
        apply_optimization "$target_level" "$reasons"
    elif [ "$target_level" -lt "$current_level" ] && [ "$pressure_score" -lt 5 ]; then
        # 可以降级优化（只有在压力很低时才降级）
        log_info "资源压力降低，降级优化级别: $current_level -> $target_level"
        if [ "$target_level" -eq 0 ]; then
            reset_optimization
        else
            apply_optimization "$target_level" "pressure_reduced"
        fi
    else
        log_debug "优化级别保持不变: $current_level"
    fi
}

# 重置优化配置
reset_optimization() {
    log_info "重置 VNC 优化配置到默认状态"

    # 恢复默认配置
    export VNC_FRAMERATE=30
    export VNC_QUALITY=6
    export VNC_COMPRESS=6
    export VNC_DEFERTIME=1
    export VNC_DEPTH=24
    export VNC_SIZE=1110x620

    # 更新状态
    update_state "current_level" "0"

    # 记录历史
    echo "$(date -Iseconds)|reset|pressure_low|restored_defaults" >> "$OPTIMIZATION_HISTORY"

    log_info "VNC 配置已重置为默认值"
}

# 主监控循环
monitor_and_optimize() {
    log_info "启动 VNC 智能优化守护进程 (间隔: ${MONITOR_INTERVAL}s)"

    # 初始化状态
    init_state

    while true; do
        # 获取系统资源
        local resources_json
        if ! resources_json=$(get_system_resources 2>&1); then
            log_warn "无法获取系统资源信息: $resources_json"
            sleep "$MONITOR_INTERVAL"
            continue
        fi

        # 解析资源数据
        local vnc_cpu=0 vnc_mem=0 connections=0
        local sys_cpu=0 sys_mem=0 load_avg=0

        if command -v jq >/dev/null 2>&1; then
            vnc_cpu=$(echo "$resources_json" | jq -r '.vnc_process.cpu_percent' 2>/dev/null || echo "0")
            vnc_mem=$(echo "$resources_json" | jq -r '.vnc_process.memory_kb' 2>/dev/null || echo "0")
            connections=$(echo "$resources_json" | jq -r '.connections' 2>/dev/null || echo "0")
            sys_cpu=$(echo "$resources_json" | jq -r '.system.cpu_percent' 2>/dev/null || echo "0")
            sys_mem=$(echo "$resources_json" | jq -r '.system.memory_percent' 2>/dev/null || echo "0")
            load_avg=$(echo "$resources_json" | jq -r '.system.load_average' 2>/dev/null || echo "0")
        else
            log_warn "jq 未安装，使用简化的资源解析"
            # 简化解析（不够精确但可用）
            vnc_cpu=$(echo "$resources_json" | grep -o '"cpu_percent": [0-9.]*' | head -1 | awk '{print $2}' || echo "0")
            connections=$(echo "$resources_json" | grep -o '"connections": [0-9]*' | awk '{print $2}' || echo "0")
        fi

        # 更新滑动窗口
        update_window CPU_WINDOW "$vnc_cpu"
        update_window MEM_WINDOW "$vnc_mem"
        update_window CONN_WINDOW "$connections"

        # 计算平均值
        local cpu_avg=$(calculate_window_average CPU_WINDOW)
        local mem_avg=$(calculate_window_average MEM_WINDOW)
        local conn_avg=$(calculate_window_average CONN_WINDOW)

        # 计算压力指数
        local pressure_result
        pressure_result=$(calculate_pressure_score "$cpu_avg" "$mem_avg" "$conn_avg" "$sys_cpu" "$sys_mem" "$load_avg")
        local pressure_score=$(echo "$pressure_result" | cut -d'|' -f1)
        local reasons=$(echo "$pressure_result" | cut -d'|' -f2)

        log_debug "资源状态 - CPU:${cpu_avg}% MEM:${mem_avg}KB CONN:${conn_avg} 压力:${pressure_score}"

        # 执行智能决策
        intelligent_decision "$pressure_score" "$reasons"

        sleep "$MONITOR_INTERVAL"
    done
}

# 显示状态
show_status() {
    echo "=== VNC 智能优化器状态 ==="

    if [ -f "$STATE_FILE" ] && command -v jq >/dev/null 2>&1; then
        echo "当前优化级别: $(jq -r '.current_level' "$STATE_FILE")"
        echo "上次优化时间: $(date -d @$(jq -r '.last_optimize_time' "$STATE_FILE") 2>/dev/null || echo "未知")"
        echo "优化次数: $(jq -r '.optimization_count' "$STATE_FILE")"
    else
        echo "状态文件不存在或 jq 未安装"
    fi

    echo ""
    echo "=== 滑动窗口状态 ==="
    echo "CPU 窗口: ${CPU_WINDOW[*]}"
    echo "内存窗口: ${MEM_WINDOW[*]}"
    echo "连接窗口: ${CONN_WINDOW[*]}"

    if [ -f "$OPTIMIZATION_HISTORY" ]; then
        echo ""
        echo "=== 最近优化历史 ==="
        tail -5 "$OPTIMIZATION_HISTORY" | while IFS='|' read -r timestamp level reason config; do
            echo "[$timestamp] $level - $reason"
        done
    fi
}

# 主函数
main() {
    case "${1:-monitor}" in
        "monitor")
            monitor_and_optimize
            ;;
        "status")
            show_status
            ;;
        "reset")
            reset_optimization
            ;;
        "test")
            echo "=== 测试系统资源获取 ==="
            get_system_resources | jq . 2>/dev/null || get_system_resources
            ;;
        *)
            echo "用法: $0 [monitor|status|reset|test]"
            echo "  monitor - 启动智能优化监控（默认）"
            echo "  status  - 显示当前状态"
            echo "  reset   - 重置优化配置"
            echo "  test    - 测试资源获取"
            exit 1
            ;;
    esac
}

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"

# 信号处理
trap 'log_info "收到退出信号，正在清理..."; exit 0' SIGTERM SIGINT

# 执行主函数
main "$@"
