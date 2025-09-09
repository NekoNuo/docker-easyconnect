#!/bin/bash
# 优化版启动脚本 - 解决内存泄露问题
# 基于原始 start.sh，添加了内存管理和进程清理机制

set -euo pipefail

eval "$(detect-iptables.sh)"
eval "$(detect-route.sh)"
eval "$(vpn-config.sh)"

# 全局变量存储后台进程PID
declare -a BACKGROUND_PIDS=()

# 信号处理函数
cleanup_and_exit() {
    echo "收到退出信号，开始清理..."
    
    # 清理后台进程
    for pid in "${BACKGROUND_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "终止进程 $pid"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 2
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
    
    # 清理 VPN 相关进程
    killall -TERM $VPN_PROCS 2>/dev/null || true
    sleep 2
    killall -KILL $VPN_PROCS 2>/dev/null || true
    
    # 清理 VNC 进程
    pkill -TERM -f "Xtigervnc\|flwm\|stalonetray" 2>/dev/null || true
    sleep 2
    pkill -KILL -f "Xtigervnc\|flwm\|stalonetray" 2>/dev/null || true
    
    # 清理网络相关进程
    pkill -TERM -f "socat\|danted\|tinyproxy" 2>/dev/null || true
    sleep 2
    pkill -KILL -f "socat\|danted\|tinyproxy" 2>/dev/null || true
    
    # 执行原有的清理逻辑
    if [ "EC_GUI" = "$_VPN_TYPE" ]; then
        sync_ec2volume
    fi
    
    echo "清理完成，退出"
    exit 0
}

# 设置信号处理
trap cleanup_and_exit SIGINT SIGQUIT SIGTERM

# 启动后台进程的包装函数
start_background_process() {
    local cmd="$1"
    local name="${2:-unknown}"
    
    echo "启动后台进程: $name"
    eval "$cmd" &
    local pid=$!
    BACKGROUND_PIDS+=("$pid")
    echo "后台进程 $name 已启动，PID: $pid"
}

# 内存监控函数
monitor_memory() {
    while true; do
        sleep 300  # 每5分钟检查一次
        
        local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
        if [ "$mem_usage" -gt 85 ]; then
            echo "警告: 内存使用率过高 (${mem_usage}%)，执行清理"
            /usr/local/bin/memory-cleanup.sh memory >/dev/null 2>&1 || true
        fi
        
        # 检查日志文件大小
        if [ -f "/var/log/vnc-performance.log" ]; then
            local log_size=$(stat -c%s "/var/log/vnc-performance.log" 2>/dev/null || echo 0)
            if [ "$log_size" -gt 104857600 ]; then  # 100MB
                echo "警告: VNC日志文件过大，执行清理"
                /usr/local/bin/memory-cleanup.sh logs >/dev/null 2>&1 || true
            fi
        fi
    done
}

# 原有函数保持不变，但添加内存优化
forward_ports() {
    if [ -n "$FORWARD" ]; then
        if iptables -t mangle -A PREROUTING -m addrtype --dst-type LOCAL -j MARK --set-mark 2; then
            iptables -t mangle -D PREROUTING -m addrtype --dst-type LOCAL -j MARK --set-mark 2
            iptables -t nat -A POSTROUTING -p tcp -m mark --mark 2 -j MASQUERADE
            ip rule add fwmark 2 table 2
            format_error() { echo Format error in \""$rule"\": "$@" >&2 ; }
            for rule in $FORWARD; do
                array=(${rule//:/ })
                case ${#array[@]} in
                    3) src_args="" ;;
                    4) src_args="-s ${array[0]}" ;;
                    *) format_error; continue ;;
                esac
                dst=${array[-2]}:${array[-1]}
                dport=${array[-3]}
                match_args="$src_args --dport $dport -m addrtype --dst-type LOCAL -i $VPN_TUN"
                iptables -t mangle -A PREROUTING -p tcp $match_args -j MARK --set-mark 2
                iptables -t mangle -A PREROUTING -p udp $match_args -j MARK --set-mark 2
                iptables -t nat -A PREROUTING -p tcp $match_args -j DNAT --to-destination $dst
                iptables -t nat -A PREROUTING -p udp $match_args -j DNAT --to-destination $dst
            done
        else
            echo "Can't append iptables used to forward ports from EasyConnect to host network!" >&2
        fi
    fi
}

start_danted() {
    cp /etc/danted.conf.sample /run/danted.conf

    if [[ -n "$SOCKS_PASSWD" && -n "$SOCKS_USER" ]];then
        id $SOCKS_USER &> /dev/null
        if [ $? -ne 0 ]; then
            useradd $SOCKS_USER
        fi

        echo $SOCKS_USER:$SOCKS_PASSWD | chpasswd
        sed -i 's/socksmethod: none/socksmethod: username/g' /run/danted.conf

        echo "use socks5 auth: $SOCKS_USER:$SOCKS_PASSWD"
    fi

    internals=""
    externals=""
    ipv6=$(ip -6 a)
    if [[ $ipv6 ]]; then
        internals="internal: 0.0.0.0 port = 1080\\ninternal: :: port = 1080"
    else
        internals="internal: 0.0.0.0 port = 1080"
    fi
    for iface in $(ip -o addr | sed -E 's/^[0-9]+: ([^ ]+) .*/\1/' | sort | uniq | grep -v "sit\|vir"); do
        externals="${externals}external: $iface\\n"
    done
    externals="${externals}external: $VPN_TUN\\n"
    sed /^internal:/c"$internals" -i /run/danted.conf
    sed /^external:/c"$externals" -i /run/danted.conf
    open_port 1080
    if ip tuntap add mode tun $VPN_TUN; then
        ip addr add 10.0.0.1/32 dev $VPN_TUN
        sleep 2
        /usr/sbin/danted -D -f /run/danted.conf
        ip tuntap del mode tun $VPN_TUN
    else
        echo 'Failed to create tun interface! Please check whether /dev/net/tun is available.' >&2
        echo 'Also refer to https://github.com/Hagb/docker-easyconnect/blob/master/doc/faq.md.' >&2
        exit 1
    fi
}

start_tinyproxy() {
    open_port 8888
    tinyproxy -c /etc/tinyproxy.conf
}

config_vpn_iptables() {
    iptables -t nat -A POSTROUTING -o $VPN_TUN -j MASQUERADE
    open_port 4440
    iptables -t nat -N SANGFOR_OUTPUT
    iptables -t nat -A PREROUTING -j SANGFOR_OUTPUT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i $VPN_TUN -p tcp -j DROP
}

# 优化的端口转发函数 - 记录socat进程
force_open_ports() {
    tmp_port=20000
    for port in $FORCE_OPEN_PORTS; do
        open_port $port
        open_port $tmp_port
        iptables -t nat -A PREROUTING -p tcp --dport $port -m addrtype --dst-type LOCAL -j REDIRECT --to-port $tmp_port
        
        # 启动socat并记录PID
        socat tcp-listen:$tmp_port,reuseaddr,fork tcp4:127.0.0.1:$port &
        local socat_pid=$!
        BACKGROUND_PIDS+=("$socat_pid")
        echo "socat进程已启动，端口 $port -> $tmp_port，PID: $socat_pid"
        
        ((tmp_port++))
    done
}

# 保持原有的init_vpn_config函数
init_vpn_config() {
    if [ "EC_CLI" = "$_VPN_TYPE" ]; then
        ln -fs /usr/share/sangfor/EasyConnect/resources/{conf_${EC_VER},conf}
    fi

    if [ "EC_GUI" = "$_VPN_TYPE" ]; then
        cp -r /usr/share/sangfor/EasyConnect/resources/conf_backup/. ~/conf/
        rm -f ~/conf/ECDomainFile
        [ -e ~/easy_connect.json ] && mv ~/easy_connect.json ~/conf/easy_connect.json
        mkdir -p /usr/share/sangfor/EasyConnect/resources/conf/
        cd ~/conf/

        for file in *; do
            ln -s ~/conf/"$file" /usr/share/sangfor/EasyConnect/resources/conf/"$file"
        done
        cd -
        [ -n "$DISABLE_PKG_VERSION_XML" ] && ln -fs /dev/null /usr/share/sangfor/EasyConnect/resources/conf/pkg_version.xml

        sync_ec2volume() {
            cd /usr/share/sangfor/EasyConnect/resources/conf/
            [ -n "$DISABLE_PKG_VERSION_XML" ] && rm pkg_version.xml
            for file in *; do
                [ -r "$file" -a ! -L "$file" -a "ECDomainFile" != "$file" ] && cp -r "$file" ~/conf/
            done
            cd ~/conf/
            for file in *; do
                [ ! -e /usr/share/sangfor/EasyConnect/resources/conf/"$file" ] && {
                    rm -r "$file"
                }
            done
        }
    fi
}

# 优化的VNC启动函数
start_tigervncserver() {
    mkdir -p ~/.vnc
    mkdir -p /tmp
    chmod 1777 /tmp

    touch ~/.Xauthority
    chmod 600 ~/.Xauthority

    rm -f ~/.vnc/passwd

    if [ -n "$PASSWORD" ]; then
        echo "VNC: 设置 VNC 密码"
        printf %s "$PASSWORD" | tigervncpasswd -f > ~/.vnc/passwd
    else
        echo "VNC: 使用默认密码 'password'"
        printf %s "password" | tigervncpasswd -f > ~/.vnc/passwd
    fi

    if [ ! -f ~/.vnc/passwd ] || [ ! -s ~/.vnc/passwd ]; then
        echo "VNC: 错误 - 无法创建 VNC 密码文件"
        return 1
    fi

    chmod 600 ~/.vnc/passwd

    VNC_SIZE="${VNC_SIZE:-1110x620}"
    VNC_ENCODING="${VNC_ENCODING:-tight}"
    VNC_QUALITY="${VNC_QUALITY:-6}"
    VNC_COMPRESS="${VNC_COMPRESS:-6}"
    VNC_FRAMERATE="${VNC_FRAMERATE:-30}"
    VNC_DEPTH="${VNC_DEPTH:-24}"
    VNC_DEFERTIME="${VNC_DEFERTIME:-1}"

    # 内存优化：根据可用内存自动调整参数
    local available_mem=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    if [ "$available_mem" -lt 512 ]; then
        echo "VNC: 检测到低内存环境 (${available_mem}MB)，启用内存优化"
        VNC_QUALITY="1"
        VNC_COMPRESS="9"
        VNC_DEPTH="8"
        VNC_SIZE="800x600"
        VNC_FRAMERATE="15"
        VNC_DEFERTIME="100"
    fi

    export VNC_FRAMERATE

    echo "VNC: 启动参数 - 编码:$VNC_ENCODING 质量:$VNC_QUALITY 压缩:$VNC_COMPRESS 帧率:${VNC_FRAMERATE}fps 深度:${VNC_DEPTH}bit"

    # 清理旧的 VNC 会话
    echo "VNC: 清理旧的 VNC 会话..."
    vncserver -kill "$DISPLAY" 2>/dev/null || true
    pkill -f "Xtigervnc.*${DISPLAY}" 2>/dev/null || true

    sleep 2

    export XAUTHORITY=~/.Xauthority
    export XDG_RUNTIME_DIR=/tmp

    cat > ~/.vnc/xstartup << 'EOF'
#!/bin/bash
export XDG_RUNTIME_DIR=/tmp
flwm &
EOF
    chmod +x ~/.vnc/xstartup

    open_port 5901

    echo "VNC: 启动 TigerVNC 服务器 (显示: $DISPLAY)"

    DISPLAY_NUM=${DISPLAY#:}
    VNC_PORT=$((5900 + DISPLAY_NUM))

    Xtigervnc "$DISPLAY" \
        -geometry "$VNC_SIZE" \
        -depth "$VNC_DEPTH" \
        -rfbauth ~/.vnc/passwd \
        -rfbport "$VNC_PORT" \
        -desktop "aTrust VNC Desktop" &

    VNC_PID=$!
    BACKGROUND_PIDS+=("$VNC_PID")
    echo "VNC: Xtigervnc 启动，PID: $VNC_PID"

    sleep 3
    if kill -0 "$VNC_PID" 2>/dev/null && pgrep -f "Xtigervnc.*${DISPLAY}" >/dev/null; then
        echo "VNC: ✅ TigerVNC 服务器启动成功 (PID: $VNC_PID)"

        sleep 1
        DISPLAY="$DISPLAY" flwm &
        local flwm_pid=$!
        BACKGROUND_PIDS+=("$flwm_pid")
        echo "VNC: 窗口管理器 flwm 已启动，PID: $flwm_pid"
    else
        echo "VNC: ❌ TigerVNC 服务器启动失败"
        return 1
    fi
    
    stalonetray -f 0 2> /dev/null &
    local tray_pid=$!
    BACKGROUND_PIDS+=("$tray_pid")

    [ -z "$CLIP_TEXT" ] && CLIP_TEXT="$ECPASSWORD"
    echo "$CLIP_TEXT" | DISPLAY=:1 xclip -selection c

    if [ -n "$USE_NOVNC" ]; then
        open_port 8080
        novnc &
        local novnc_pid=$!
        BACKGROUND_PIDS+=("$novnc_pid")
    fi

    # 有条件地启动监控（默认禁用以节省内存）
    if [ "$VNC_AUTO_OPTIMIZE" = "1" ] && [ "$available_mem" -gt 1024 ]; then
        echo "启动 VNC 性能监控..."
        vnc-performance-monitor.sh monitor &
        local monitor_pid=$!
        BACKGROUND_PIDS+=("$monitor_pid")
    fi
}

# 优化的保活函数
keep_pinging() {
    if [ -n "$PING_ADDR" ]; then
        while sleep $PING_INTERVAL; do
            busybox ping -c1 -W1 -w1 "$PING_ADDR" >/dev/null 2>/dev/null || true
        done &
        local ping_pid=$!
        BACKGROUND_PIDS+=("$ping_pid")
        echo "保活ping已启动，PID: $ping_pid"
    fi
}

keep_pinging_url() {
    if [ -n "$PING_ADDR_URL" ]; then
        while sleep $PING_INTERVAL; do
            timeout 10 busybox wget -q --spider "$PING_ADDR_URL" 2>/dev/null || true
        done &
        local ping_url_pid=$!
        BACKGROUND_PIDS+=("$ping_url_pid")
        echo "保活URL请求已启动，PID: $ping_url_pid"
    fi
}

# 主启动流程
echo "启动优化版 docker-easyconnect..."

# 清除 /tmp 中的锁
for f in /tmp/* /tmp/.*; do
    [ "/tmp/.X11-unix" != "$f" ] && rm -rf -- "$f"
done

# 设置文件描述符限制
ulimit -n 1048576

# 启动内存监控
start_background_process "monitor_memory" "memory-monitor"

# 启动各种服务
start_background_process "forward_ports" "port-forward"
start_background_process "start_danted" "socks-proxy"
start_background_process "start_tinyproxy" "http-proxy"
start_background_process "config_vpn_iptables" "vpn-iptables"
start_background_process "force_open_ports" "force-ports"
start_background_process "keep_pinging" "keep-ping"
start_background_process "keep_pinging_url" "keep-ping-url"

if [ -z "$DISPLAY" ]; then
    export DISPLAY=:1
    start_background_process "start_tigervncserver" "vnc-server"
fi

init_vpn_config

echo "等待服务启动完成..."
sleep 5

[ -n "$EXIT" ] && export MAX_RETRY=0
start-sangfor.sh &
SANGFOR_PID=$!
BACKGROUND_PIDS+=("$SANGFOR_PID")

echo "所有服务已启动，后台进程数: ${#BACKGROUND_PIDS[@]}"

# 等待主进程
wait $SANGFOR_PID

# 清理并退出
cleanup_and_exit
