#!/bin/bash
# 简化的 X11 环境初始化脚本
# 专门解决 TigerVNC "Couldn't add screen" 问题

set -euo pipefail

# 日志函数
log_info() {
    echo "$(date -Iseconds) [X11-SIMPLE] $*"
}

log_warn() {
    echo "$(date -Iseconds) [X11-SIMPLE] WARN: $*" >&2
}

log_error() {
    echo "$(date -Iseconds) [X11-SIMPLE] ERROR: $*" >&2
}

# 简化的初始化函数
init_x11_simple() {
    log_info "开始简化 X11 环境初始化..."
    
    # 检查必需的命令
    if ! command -v Xtigervnc >/dev/null 2>&1; then
        log_error "Xtigervnc 命令不存在"
        return 1
    fi
    
    if ! command -v flwm >/dev/null 2>&1; then
        log_error "flwm 命令不存在"
        return 1
    fi
    
    log_info "✅ 必需命令检查通过"
    
    # 创建必要的目录
    log_info "创建必要的目录..."
    mkdir -p /tmp/.X11-unix
    mkdir -p /tmp/.ICE-unix
    mkdir -p /tmp/.font-unix
    mkdir -p /var/lib/xkb
    
    # 设置正确的权限
    chmod 1777 /tmp/.X11-unix 2>/dev/null || true
    chmod 1777 /tmp/.ICE-unix 2>/dev/null || true
    chmod 1777 /tmp/.font-unix 2>/dev/null || true
    
    log_info "✅ 目录创建完成"
    
    # 设置环境变量
    export DISPLAY="${DISPLAY:-:1}"
    export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
    export XDG_SESSION_TYPE="x11"
    export XDG_CURRENT_DESKTOP="FLWM"
    
    # 创建 X11 认证文件
    touch "$XAUTHORITY" 2>/dev/null || true
    chmod 600 "$XAUTHORITY" 2>/dev/null || true
    
    log_info "✅ 环境变量设置完成"
    
    # 清理旧的会话
    log_info "清理旧的 X11 会话..."
    local display="${DISPLAY:-:1}"
    local display_num="${display#:}"
    
    # 清理 VNC 进程
    pkill -f "Xtigervnc.*${display}" 2>/dev/null || true
    pkill -f "Xvnc.*${display}" 2>/dev/null || true
    
    # 清理 socket 文件
    rm -f "/tmp/.X11-unix/X${display_num}" 2>/dev/null || true
    rm -f "/tmp/.X${display_num}-lock" 2>/dev/null || true
    
    # 等待清理完成
    sleep 1
    
    log_info "✅ 旧会话清理完成"
    
    # 创建基本的设备文件（如果需要且有权限）
    log_info "检查设备文件..."
    local devices_ok=true
    
    if [ ! -e /dev/null ]; then
        mknod /dev/null c 1 3 2>/dev/null || {
            log_warn "无法创建 /dev/null (权限不足，但可能不影响功能)"
            devices_ok=false
        }
    fi
    
    if [ ! -e /dev/zero ]; then
        mknod /dev/zero c 1 5 2>/dev/null || {
            log_warn "无法创建 /dev/zero (权限不足，但可能不影响功能)"
            devices_ok=false
        }
    fi
    
    if $devices_ok; then
        log_info "✅ 设备文件检查通过"
    else
        log_warn "⚠️  部分设备文件创建失败，但不影响基本功能"
    fi
    
    log_info "简化 X11 环境初始化完成"
    return 0
}

# 验证环境
verify_environment() {
    log_info "验证 X11 环境..."
    
    # 检查关键目录
    if [ ! -d "/tmp/.X11-unix" ]; then
        log_error "X11 socket 目录不存在"
        return 1
    fi
    
    if [ ! -w "/tmp/.X11-unix" ]; then
        log_error "X11 socket 目录不可写"
        return 1
    fi
    
    log_info "✅ 环境验证通过"
    return 0
}

# 主函数
main() {
    log_info "开始简化 X11 环境初始化..."
    
    if ! init_x11_simple; then
        log_error "X11 环境初始化失败"
        exit 1
    fi
    
    if ! verify_environment; then
        log_error "X11 环境验证失败"
        exit 1
    fi
    
    log_info "✅ 简化 X11 环境初始化成功"
}

# 如果直接执行脚本
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
