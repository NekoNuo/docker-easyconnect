#!/bin/bash
# X11 环境初始化脚本
# 解决 TigerVNC "Couldn't add screen" 问题

set -euo pipefail

# 日志函数
log_info() {
    echo "$(date -Iseconds) [X11-INIT] $*"
}

log_warn() {
    echo "$(date -Iseconds) [X11-INIT] WARN: $*" >&2
}

log_error() {
    echo "$(date -Iseconds) [X11-INIT] ERROR: $*" >&2
}

# 初始化 X11 环境
init_x11_environment() {
    log_info "初始化 X11 环境..."
    
    # 创建必要的目录
    mkdir -p /tmp/.X11-unix
    mkdir -p /tmp/.ICE-unix
    mkdir -p /tmp/.font-unix
    mkdir -p /var/lib/xkb
    mkdir -p /usr/share/X11/xkb
    mkdir -p /etc/X11/xorg.conf.d
    
    # 设置正确的权限
    chmod 1777 /tmp/.X11-unix
    chmod 1777 /tmp/.ICE-unix
    chmod 1777 /tmp/.font-unix
    
    # 创建必要的设备文件
    create_device_files
    
    # 设置环境变量
    export DISPLAY="${DISPLAY:-:1}"
    export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
    export XDG_SESSION_TYPE="x11"
    export XDG_CURRENT_DESKTOP="FLWM"
    
    # 创建 X11 认证文件
    touch "$XAUTHORITY"
    chmod 600 "$XAUTHORITY"
    
    log_info "X11 环境初始化完成"
}

# 创建设备文件
create_device_files() {
    log_info "检查并创建必要的设备文件..."
    
    local devices=(
        "/dev/null:c:1:3"
        "/dev/zero:c:1:5"
        "/dev/random:c:1:8"
        "/dev/urandom:c:1:9"
        "/dev/tty:c:5:0"
    )
    
    for device_info in "${devices[@]}"; do
        IFS=':' read -r device_path device_type major minor <<< "$device_info"
        
        if [ ! -e "$device_path" ]; then
            log_info "创建设备文件: $device_path"
            mknod "$device_path" "$device_type" "$major" "$minor" 2>/dev/null || {
                log_warn "无法创建设备文件 $device_path (权限不足)"
            }
        fi
    done
}

# 检查 X11 依赖
check_x11_dependencies() {
    log_info "检查 X11 依赖..."
    
    local required_commands=(
        "Xtigervnc"
        "flwm"
        "xauth"
        "xset"
    )
    
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "缺少必要的 X11 命令: ${missing_commands[*]}"
        return 1
    fi
    
    log_info "X11 依赖检查通过"
}

# 清理旧的 X11 会话
cleanup_old_sessions() {
    log_info "清理旧的 X11 会话..."
    
    local display="${DISPLAY:-:1}"
    local display_num="${display#:}"
    
    # 清理 VNC 进程
    pkill -f "Xtigervnc.*${display}" 2>/dev/null || true
    pkill -f "Xvnc.*${display}" 2>/dev/null || true
    
    # 清理 X11 socket 文件
    rm -f "/tmp/.X11-unix/X${display_num}" 2>/dev/null || true
    
    # 清理 VNC 锁文件
    rm -f "/tmp/.X${display_num}-lock" 2>/dev/null || true
    
    # 等待进程完全退出
    sleep 2
    
    log_info "旧会话清理完成"
}

# 验证 X11 环境
verify_x11_environment() {
    log_info "验证 X11 环境..."
    
    # 检查必要的目录
    local required_dirs=(
        "/tmp/.X11-unix"
        "/tmp/.ICE-unix"
        "/var/lib/xkb"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_error "缺少必要目录: $dir"
            return 1
        fi
    done
    
    # 检查权限
    if [ ! -w "/tmp/.X11-unix" ]; then
        log_error "/tmp/.X11-unix 目录不可写"
        return 1
    fi
    
    log_info "X11 环境验证通过"
}

# 主函数
main() {
    log_info "开始 X11 环境初始化..."
    
    # 检查依赖
    if ! check_x11_dependencies; then
        log_error "X11 依赖检查失败"
        exit 1
    fi
    
    # 清理旧会话
    cleanup_old_sessions
    
    # 初始化环境
    init_x11_environment
    
    # 验证环境
    if ! verify_x11_environment; then
        log_error "X11 环境验证失败"
        exit 1
    fi
    
    log_info "X11 环境初始化成功"
}

# 如果直接执行脚本
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
