#!/bin/bash
# VNC 故障排除脚本
# 诊断和解决 TigerVNC "Couldn't add screen" 等问题

set -euo pipefail

# 配置
DISPLAY="${DISPLAY:-:1}"
LOG_FILE="/var/log/vnc-troubleshoot.log"

# 日志函数
log_info() {
    echo "$(date -Iseconds) [VNC-TROUBLESHOOT] $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "$(date -Iseconds) [VNC-TROUBLESHOOT] WARN: $*" | tee -a "$LOG_FILE" >&2
}

log_error() {
    echo "$(date -Iseconds) [VNC-TROUBLESHOOT] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# 系统信息检查
check_system_info() {
    log_info "=== 系统信息检查 ==="
    
    log_info "操作系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    log_info "内核版本: $(uname -r)"
    log_info "架构: $(uname -m)"
    
    # 内存信息
    local mem_info=$(free -h | grep "Mem:")
    log_info "内存信息: $mem_info"
    
    # 磁盘空间
    local disk_info=$(df -h / | tail -1)
    log_info "磁盘空间: $disk_info"
    
    # 进程信息
    local process_count=$(ps aux | wc -l)
    log_info "运行进程数: $process_count"
}

# X11 环境检查
check_x11_environment() {
    log_info "=== X11 环境检查 ==="
    
    # 检查 X11 相关包
    local x11_packages=(
        "tigervnc-standalone-server"
        "tigervnc-tools"
        "libx11-xcb1"
        "x11-utils"
        "x11-xserver-utils"
        "flwm"
    )
    
    for pkg in "${x11_packages[@]}"; do
        if dpkg -l | grep -q "$pkg"; then
            log_info "✅ $pkg 已安装"
        else
            log_warn "❌ $pkg 未安装"
        fi
    done
    
    # 检查 X11 目录
    local x11_dirs=(
        "/tmp/.X11-unix"
        "/tmp/.ICE-unix"
        "/usr/share/X11"
        "/etc/X11"
    )
    
    for dir in "${x11_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_info "✅ 目录存在: $dir (权限: $(stat -c %a "$dir"))"
        else
            log_warn "❌ 目录不存在: $dir"
        fi
    done
    
    # 检查环境变量
    log_info "DISPLAY: ${DISPLAY:-未设置}"
    log_info "XAUTHORITY: ${XAUTHORITY:-未设置}"
    log_info "XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR:-未设置}"
}

# VNC 配置检查
check_vnc_configuration() {
    log_info "=== VNC 配置检查 ==="
    
    # 检查 VNC 密码文件
    if [ -f ~/.vnc/passwd ]; then
        local passwd_size=$(stat -c%s ~/.vnc/passwd)
        local passwd_perms=$(stat -c%a ~/.vnc/passwd)
        log_info "✅ VNC 密码文件存在 (大小: ${passwd_size}字节, 权限: $passwd_perms)"
    else
        log_warn "❌ VNC 密码文件不存在"
    fi
    
    # 检查 VNC 配置文件
    local vnc_configs=(
        "/etc/tigervnc/vncserver-config-defaults"
        "~/.vnc/xstartup"
    )
    
    for config in "${vnc_configs[@]}"; do
        local expanded_config=$(eval echo "$config")
        if [ -f "$expanded_config" ]; then
            log_info "✅ 配置文件存在: $expanded_config"
        else
            log_warn "❌ 配置文件不存在: $expanded_config"
        fi
    done
    
    # 检查端口占用
    local display_num="${DISPLAY#:}"
    local vnc_port=$((5900 + display_num))
    
    if netstat -ln | grep -q ":$vnc_port "; then
        log_warn "⚠️  端口 $vnc_port 已被占用"
        netstat -lnp | grep ":$vnc_port " | while read line; do
            log_info "端口占用详情: $line"
        done
    else
        log_info "✅ 端口 $vnc_port 可用"
    fi
}

# 进程检查
check_processes() {
    log_info "=== 进程检查 ==="
    
    # 检查 VNC 相关进程
    local vnc_processes=$(pgrep -f "tigervnc\|Xtigervnc\|Xvnc" || true)
    if [ -n "$vnc_processes" ]; then
        log_info "发现 VNC 进程:"
        echo "$vnc_processes" | while read pid; do
            local cmd=$(ps -p "$pid" -o cmd --no-headers 2>/dev/null || echo "进程已退出")
            log_info "  PID $pid: $cmd"
        done
    else
        log_info "未发现运行中的 VNC 进程"
    fi
    
    # 检查窗口管理器进程
    local wm_processes=$(pgrep -f "flwm" || true)
    if [ -n "$wm_processes" ]; then
        log_info "发现窗口管理器进程: $wm_processes"
    else
        log_info "未发现窗口管理器进程"
    fi
}

# 日志检查
check_logs() {
    log_info "=== 日志检查 ==="
    
    # 检查 VNC 日志
    local vnc_logs=(
        "~/.vnc/*${DISPLAY}.log"
        "~/.vnc/$(hostname)${DISPLAY}.log"
        "/var/log/vnc-performance.log"
    )
    
    for log_pattern in "${vnc_logs[@]}"; do
        local expanded_pattern=$(eval echo "$log_pattern")
        for log_file in $expanded_pattern; do
            if [ -f "$log_file" ]; then
                log_info "发现日志文件: $log_file"
                log_info "最近10行日志:"
                tail -10 "$log_file" | while read line; do
                    log_info "  $line"
                done
            fi
        done
    done
}

# 网络检查
check_network() {
    log_info "=== 网络检查 ==="
    
    # 检查监听端口
    log_info "当前监听的端口:"
    netstat -ln | grep -E ":(590[0-9]|5901)" | while read line; do
        log_info "  $line"
    done
    
    # 检查网络连接
    local display_num="${DISPLAY#:}"
    local vnc_port=$((5900 + display_num))
    
    if timeout 3 bash -c "echo '' | nc localhost $vnc_port" 2>/dev/null; then
        log_info "✅ VNC 端口 $vnc_port 可连接"
    else
        log_warn "❌ VNC 端口 $vnc_port 不可连接"
    fi
}

# 修复建议
suggest_fixes() {
    log_info "=== 修复建议 ==="
    
    # 检查常见问题并提供建议
    if [ ! -d "/tmp/.X11-unix" ]; then
        log_info "建议: 创建 X11 socket 目录"
        log_info "  mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix"
    fi
    
    if [ ! -f ~/.vnc/passwd ]; then
        log_info "建议: 创建 VNC 密码文件"
        log_info "  echo 'password' | tigervncpasswd -f > ~/.vnc/passwd && chmod 600 ~/.vnc/passwd"
    fi
    
    local display_num="${DISPLAY#:}"
    local vnc_port=$((5900 + display_num))
    
    if netstat -ln | grep -q ":$vnc_port "; then
        log_info "建议: 清理占用的端口"
        log_info "  pkill -f 'Xtigervnc.*${DISPLAY}' && sleep 2"
    fi
    
    # 内存检查
    local available_mem=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    if [ "$available_mem" -lt 256 ]; then
        log_info "建议: 系统内存不足 (${available_mem}MB)，考虑:"
        log_info "  - 降低 VNC 分辨率: export VNC_SIZE=800x600"
        log_info "  - 降低色彩深度: export VNC_DEPTH=16"
        log_info "  - 启用内存清理: export VNC_AUTO_OPTIMIZE=1"
    fi
}

# 自动修复
auto_fix() {
    log_info "=== 自动修复 ==="
    
    local fixes_applied=0
    
    # 创建必要目录
    if [ ! -d "/tmp/.X11-unix" ]; then
        log_info "创建 X11 socket 目录..."
        mkdir -p /tmp/.X11-unix
        chmod 1777 /tmp/.X11-unix
        fixes_applied=$((fixes_applied + 1))
    fi
    
    # 清理旧进程
    local display_num="${DISPLAY#:}"
    if pgrep -f "Xtigervnc.*${DISPLAY}" >/dev/null; then
        log_info "清理旧的 VNC 进程..."
        pkill -f "Xtigervnc.*${DISPLAY}" || true
        sleep 2
        fixes_applied=$((fixes_applied + 1))
    fi
    
    # 清理 socket 文件
    if [ -e "/tmp/.X11-unix/X${display_num}" ]; then
        log_info "清理旧的 socket 文件..."
        rm -f "/tmp/.X11-unix/X${display_num}"
        fixes_applied=$((fixes_applied + 1))
    fi
    
    log_info "自动修复完成，应用了 $fixes_applied 个修复"
}

# 主函数
main() {
    local action="${1:-check}"
    
    log_info "开始 VNC 故障排除 (操作: $action)"
    
    case "$action" in
        "check"|"diagnose")
            check_system_info
            check_x11_environment
            check_vnc_configuration
            check_processes
            check_logs
            check_network
            suggest_fixes
            ;;
        "fix"|"repair")
            auto_fix
            ;;
        "full")
            check_system_info
            check_x11_environment
            check_vnc_configuration
            check_processes
            check_logs
            check_network
            suggest_fixes
            auto_fix
            ;;
        *)
            echo "用法: $0 [check|fix|full]"
            echo "  check  - 仅检查和诊断问题"
            echo "  fix    - 自动修复常见问题"
            echo "  full   - 完整检查和修复"
            exit 1
            ;;
    esac
    
    log_info "VNC 故障排除完成"
}

# 如果直接执行脚本
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
