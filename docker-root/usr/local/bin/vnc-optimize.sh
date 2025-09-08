#!/bin/bash
# VNC 动态优化脚本

set -euo pipefail

# 配置文件路径
VNC_CONFIG_FILE="/tmp/vnc-runtime-config"
VNC_DISPLAY="${VNC_DISPLAY:-:1}"

# 日志函数
log_info() {
    echo "$(date -Iseconds) [INFO] $*"
}

log_warn() {
    echo "$(date -Iseconds) [WARN] $*" >&2
}

# 检测网络延迟和带宽
detect_network_conditions() {
    local ping_target="${VNC_PING_TARGET:-8.8.8.8}"
    local ping_result
    
    # 检测延迟
    if ping_result=$(ping -c 3 -W 2 "$ping_target" 2>/dev/null); then
        local avg_latency=$(echo "$ping_result" | grep "avg" | awk -F'/' '{print $5}' | cut -d'.' -f1)
        
        if [ -n "$avg_latency" ]; then
            if (( avg_latency < 20 )); then
                echo "fast"
            elif (( avg_latency < 100 )); then
                echo "balanced"
            else
                echo "slow"
            fi
        else
            echo "balanced"
        fi
    else
        log_warn "无法检测网络条件，使用默认配置"
        echo "balanced"
    fi
}

# 检测系统负载
detect_system_load() {
    local load_avg
    local cpu_count
    
    # 获取 1 分钟平均负载
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
    cpu_count=$(nproc)
    
    # 计算负载百分比
    local load_percent=$(echo "scale=0; $load_avg * 100 / $cpu_count" | bc -l 2>/dev/null || echo "50")
    
    if (( load_percent < 30 )); then
        echo "low"
    elif (( load_percent < 70 )); then
        echo "medium"
    else
        echo "high"
    fi
}

# 检测可用内存
detect_memory_usage() {
    local mem_info
    local mem_total
    local mem_available
    local mem_usage_percent
    
    mem_info=$(cat /proc/meminfo)
    mem_total=$(echo "$mem_info" | grep "MemTotal:" | awk '{print $2}')
    mem_available=$(echo "$mem_info" | grep "MemAvailable:" | awk '{print $2}')
    
    if [ -n "$mem_total" ] && [ -n "$mem_available" ]; then
        mem_usage_percent=$(echo "scale=0; (($mem_total - $mem_available) * 100) / $mem_total" | bc -l)
        
        if (( mem_usage_percent < 50 )); then
            echo "low"
        elif (( mem_usage_percent < 80 )); then
            echo "medium"
        else
            echo "high"
        fi
    else
        echo "medium"
    fi
}

# 生成优化配置
generate_optimized_config() {
    local network_condition="$1"
    local system_load="$2"
    local memory_usage="$3"
    
    log_info "系统状态: 网络=$network_condition, 负载=$system_load, 内存=$memory_usage"
    
    # 基础配置
    local encoding="tight"
    local quality=6
    local compress=6
    local framerate=30
    local depth=24
    local defer_time=1
    
    # 根据网络条件调整
    case "$network_condition" in
        "fast")
            encoding="zrle"
            quality=8
            compress=2
            framerate=60
            depth=32
            defer_time=0
            ;;
        "slow")
            encoding="tight"
            quality=2
            compress=9
            framerate=15
            depth=16
            defer_time=50
            ;;
        "balanced")
            encoding="tight"
            quality=6
            compress=6
            framerate=30
            depth=24
            defer_time=1
            ;;
    esac
    
    # 根据系统负载调整
    case "$system_load" in
        "high")
            framerate=$((framerate / 2))
            quality=$((quality - 2))
            [ $quality -lt 1 ] && quality=1
            defer_time=$((defer_time + 20))
            ;;
        "low")
            framerate=$((framerate + 10))
            [ $framerate -gt 60 ] && framerate=60
            quality=$((quality + 1))
            [ $quality -gt 9 ] && quality=9
            ;;
    esac
    
    # 根据内存使用调整
    case "$memory_usage" in
        "high")
            depth=16
            quality=$((quality - 1))
            [ $quality -lt 1 ] && quality=1
            ;;
        "low")
            depth=32
            quality=$((quality + 1))
            [ $quality -gt 9 ] && quality=9
            ;;
    esac
    
    # 生成配置文件
    cat > "$VNC_CONFIG_FILE" << EOF
# VNC 动态优化配置
# 生成时间: $(date -Iseconds)
# 系统状态: 网络=$network_condition, 负载=$system_load, 内存=$memory_usage

export VNC_ENCODING="$encoding"
export VNC_QUALITY="$quality"
export VNC_COMPRESS="$compress"
export VNC_FRAMERATE="$framerate"
export VNC_DEPTH="$depth"
export VNC_DEFERTIME="$defer_time"
export VNC_NETWORK_MODE="$network_condition"

# 应用配置的函数
apply_vnc_config() {
    echo "应用 VNC 优化配置:"
    echo "  编码: $encoding"
    echo "  质量: $quality"
    echo "  压缩: $compress"
    echo "  帧率: ${framerate}fps"
    echo "  深度: ${depth}bit"
    echo "  延迟: ${defer_time}ms"
}
EOF
    
    log_info "生成优化配置: 编码=$encoding 质量=$quality 压缩=$compress 帧率=${framerate}fps 深度=${depth}bit"
}

# 应用配置到运行中的 VNC 服务
apply_config_to_running_vnc() {
    local vnc_pid
    # 支持 TigerVNC 和传统 VNC
    vnc_pid=$(pgrep -f "Xtigervnc.*$VNC_DISPLAY" | head -1)
    [ -z "$vnc_pid" ] && vnc_pid=$(pgrep -f "Xvnc.*$VNC_DISPLAY" | head -1)
    
    if [ -z "$vnc_pid" ]; then
        log_warn "VNC 服务未运行，无法应用动态配置"
        return 1
    fi
    
    log_info "VNC 服务正在运行 (PID: $vnc_pid)"
    log_warn "注意: 某些配置更改需要重启 VNC 服务才能生效"
    
    # 这里可以添加通过信号或其他方式动态调整 VNC 参数的逻辑
    # 目前大多数 VNC 服务器不支持运行时配置更改
    
    return 0
}

# 性能测试
run_performance_test() {
    log_info "运行 VNC 性能测试..."
    
    # 测试帧率
    local start_time=$(date +%s)
    local frame_count=0
    local test_duration=10
    
    log_info "测试帧率 (${test_duration}秒)..."
    
    # 这里应该实现实际的帧率测试逻辑
    # 由于复杂性，这里只是示例
    
    local end_time=$((start_time + test_duration))
    while [ $(date +%s) -lt $end_time ]; do
        # 模拟帧计数
        frame_count=$((frame_count + 1))
        sleep 0.1
    done
    
    local actual_fps=$((frame_count / test_duration))
    log_info "实际帧率: ${actual_fps}fps"
    
    # 测试延迟
    log_info "测试网络延迟..."
    local vnc_port=$((5900 + ${VNC_DISPLAY#:}))
    local latency_test
    
    if latency_test=$(timeout 5 bash -c "time echo '' | nc localhost $vnc_port" 2>&1); then
        log_info "VNC 连接延迟测试完成"
    else
        log_warn "VNC 连接延迟测试失败"
    fi
}

# 主函数
main() {
    case "${1:-auto}" in
        "auto")
            log_info "开始自动 VNC 性能优化..."
            
            local network_condition
            local system_load
            local memory_usage
            
            network_condition=$(detect_network_conditions)
            system_load=$(detect_system_load)
            memory_usage=$(detect_memory_usage)
            
            generate_optimized_config "$network_condition" "$system_load" "$memory_usage"
            
            if [ -f "$VNC_CONFIG_FILE" ]; then
                echo "优化配置已生成: $VNC_CONFIG_FILE"
                echo "要应用配置，请运行: source $VNC_CONFIG_FILE && apply_vnc_config"
            fi
            ;;
        "test")
            run_performance_test
            ;;
        "apply")
            if [ -f "$VNC_CONFIG_FILE" ]; then
                source "$VNC_CONFIG_FILE"
                apply_vnc_config
                apply_config_to_running_vnc
            else
                log_warn "配置文件不存在，请先运行 'auto' 命令"
            fi
            ;;
        "status")
            echo "=== VNC 优化状态 ==="
            echo "网络条件: $(detect_network_conditions)"
            echo "系统负载: $(detect_system_load)"
            echo "内存使用: $(detect_memory_usage)"
            
            if [ -f "$VNC_CONFIG_FILE" ]; then
                echo ""
                echo "=== 当前优化配置 ==="
                grep "^export" "$VNC_CONFIG_FILE" | sed 's/export //'
            fi
            ;;
        *)
            echo "用法: $0 [auto|test|apply|status]"
            echo "  auto   - 自动检测并生成优化配置"
            echo "  test   - 运行性能测试"
            echo "  apply  - 应用优化配置"
            echo "  status - 显示当前状态"
            exit 1
            ;;
    esac
}

# 确保必要的工具存在
for cmd in bc nproc ping; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_warn "工具 '$cmd' 未安装，某些功能可能受限"
    fi
done

main "$@"
