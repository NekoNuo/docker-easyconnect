#!/bin/bash
eval "$(detect-iptables.sh)"
eval "$(detect-route.sh)"
eval "$(vpn-config.sh)"

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
		# eth0 need >1s to be ready
		# refer to https://stackoverflow.com/questions/25226531/dante-sever-fail-to-bind-ip-by-interface-name-in-docker-container
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

	# 拒绝 tun 侧主动请求的连接.
	iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
	iptables -A INPUT -i $VPN_TUN -p tcp -j DROP
}

force_open_ports() {
	# 暴露 54530 等用于和浏览器通讯的端口
	tmp_port=20000
	for port in $FORCE_OPEN_PORTS; do
		open_port $port
		open_port $tmp_port
		iptables -t nat -A PREROUTING -p tcp --dport $port -m addrtype --dst-type LOCAL -j REDIRECT --to-port $tmp_port
		socat tcp-listen:$tmp_port,reuseaddr,fork tcp4:127.0.0.1:$port &
		((tmp_port++))
	done
}

init_vpn_config() {
	if [ "EC_CLI" = "$_VPN_TYPE" ]; then
		ln -fs /usr/share/sangfor/EasyConnect/resources/{conf_${EC_VER},conf}
	fi

	if [ "EC_GUI" = "$_VPN_TYPE" ]; then
		# 登录信息持久化处理
		## 持久化配置文件夹 感谢 @hexid26 https://github.com/Hagb/docker-easyconnect/issues/21
		cp -r /usr/share/sangfor/EasyConnect/resources/conf_backup/. ~/conf/
		rm -f ~/conf/ECDomainFile
		[ -e ~/easy_connect.json ] && mv ~/easy_connect.json ~/conf/easy_connect.json # 向下兼容
		mkdir -p /usr/share/sangfor/EasyConnect/resources/conf/
		cd ~/conf/

		## 不再假定 /root 的文件系统（可能从宿主机挂载）支持 unix sock（用于 ECDomainFile），因此不直接使用
		for file in *; do
			## 通过软链接减小拷贝量
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
		## 容器退出时将配置文件同步回 /root/conf。感谢 @Einskai 的点子
		trap "sync_ec2volume; exit;" SIGINT SIGQUIT SIGSTOP SIGTSTP SIGTERM
	else
		trap "exit;" SIGINT SIGQUIT SIGSTOP SIGTSTP SIGTERM
	fi
}

start_tigervncserver() {
	# 确保必要的目录和文件存在
	mkdir -p ~/.vnc
	mkdir -p /tmp
	chmod 1777 /tmp  # 确保 /tmp 有正确的权限

	# 创建 X11 认证文件
	touch ~/.Xauthority
	chmod 600 ~/.Xauthority

	# 清理旧的 VNC 密码文件
	rm -f ~/.vnc/passwd

	# 设置 VNC 密码
	if [ -n "$PASSWORD" ]; then
		echo "VNC: 设置 VNC 密码"
		# 使用 -f 参数直接从标准输入读取密码
		printf %s "$PASSWORD" | tigervncpasswd -f > ~/.vnc/passwd
	else
		# 如果没有设置密码，使用默认密码
		echo "VNC: 使用默认密码 'password'"
		printf %s "password" | tigervncpasswd -f > ~/.vnc/passwd
	fi

	# 验证密码文件是否创建成功
	if [ ! -f ~/.vnc/passwd ]; then
		echo "VNC: 错误 - 无法创建 VNC 密码文件"
		return 1
	fi

	# 设置密码文件权限
	chmod 600 ~/.vnc/passwd

	# 验证密码文件内容
	if [ ! -s ~/.vnc/passwd ]; then
		echo "VNC: 错误 - 密码文件为空"
		return 1
	fi

	echo "VNC: 密码文件创建成功 ($(stat -c%s ~/.vnc/passwd) 字节)"

	VNC_SIZE="${VNC_SIZE:-1024x768}"

	# VNC 性能优化配置
	VNC_ENCODING="${VNC_ENCODING:-tight}"  # 编码格式: tight, zrle, hextile, raw
	VNC_QUALITY="${VNC_QUALITY:-6}"        # 压缩质量: 0-9 (0=最高压缩, 9=最高质量)
	VNC_COMPRESS="${VNC_COMPRESS:-6}"      # 压缩级别: 0-9 (0=无压缩, 9=最高压缩)
	VNC_FRAMERATE="${VNC_FRAMERATE:-30}"   # 帧率限制: 1-60 fps
	VNC_DEPTH="${VNC_DEPTH:-24}"           # 色彩深度: 8, 16, 24, 32
	VNC_DEFERTIME="${VNC_DEFERTIME:-1}"    # 延迟更新时间(ms): 0-200

	# 根据网络条件和服务器配置自动调整参数
	if [ -n "$VNC_NETWORK_MODE" ]; then
		case "$VNC_NETWORK_MODE" in
			"fast"|"lan")
				VNC_ENCODING="raw"
				VNC_QUALITY="9"
				VNC_COMPRESS="0"
				VNC_FRAMERATE="60"
				VNC_DEPTH="32"
				VNC_DEFERTIME="0"
				echo "VNC: 配置为高速网络模式 (LAN)"
				;;
			"slow"|"wan"|"mobile")
				VNC_ENCODING="tight"
				VNC_QUALITY="2"
				VNC_COMPRESS="9"
				VNC_FRAMERATE="15"
				VNC_DEPTH="16"
				VNC_DEFERTIME="50"
				echo "VNC: 配置为低速网络模式 (WAN/Mobile)"
				;;
			"lowres"|"minimal")
				VNC_ENCODING="tight"
				VNC_QUALITY="1"
				VNC_COMPRESS="9"
				VNC_FRAMERATE="10"
				VNC_DEPTH="8"
				VNC_DEFERTIME="100"
				VNC_SIZE="800x600"  # 降低分辨率
				echo "VNC: 配置为低资源模式 (Minimal)"
				;;
			"balanced"|*)
				VNC_ENCODING="tight"
				VNC_QUALITY="6"
				VNC_COMPRESS="6"
				VNC_FRAMERATE="30"
				VNC_DEPTH="24"
				VNC_DEFERTIME="1"
				echo "VNC: 配置为平衡模式 (默认)"
				;;
		esac
	fi

	# 自动检测服务器配置并优化
	if [ "$VNC_AUTO_LOWRES" = "1" ]; then
		echo "VNC: 检测服务器配置..."

		# 检测可用内存 (MB)
		local available_mem=$(free -m | awk 'NR==2{printf "%.0f", $7}')
		# 检测 CPU 核心数
		local cpu_cores=$(nproc)
		# 检测系统负载
		local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ' | cut -d'.' -f1)

		echo "VNC: 系统资源 - 内存:${available_mem}MB CPU:${cpu_cores}核心 负载:${load_avg}"

		# 低内存优化 (小于 512MB 可用内存)
		if [ "$available_mem" -lt 512 ]; then
			echo "VNC: 检测到低内存环境，启用内存优化模式"
			VNC_ENCODING="tight"
			VNC_QUALITY="1"
			VNC_COMPRESS="9"
			VNC_DEPTH="8"
			VNC_SIZE="640x480"
			VNC_FRAMERATE="8"
			VNC_DEFERTIME="200"
		# 中等内存优化 (小于 1GB 可用内存)
		elif [ "$available_mem" -lt 1024 ]; then
			echo "VNC: 检测到中等内存环境，启用轻量优化模式"
			VNC_ENCODING="tight"
			VNC_QUALITY="3"
			VNC_COMPRESS="8"
			VNC_DEPTH="16"
			VNC_SIZE="800x600"
			VNC_FRAMERATE="15"
			VNC_DEFERTIME="50"
		fi

		# 低 CPU 优化 (单核或高负载)
		if [ "$cpu_cores" -eq 1 ] || [ "$load_avg" -gt 2 ]; then
			echo "VNC: 检测到 CPU 资源紧张，启用 CPU 优化模式"
			VNC_FRAMERATE=$((VNC_FRAMERATE / 2))
			[ "$VNC_FRAMERATE" -lt 5 ] && VNC_FRAMERATE=5
			VNC_DEFERTIME=$((VNC_DEFERTIME + 50))
			VNC_QUALITY=$((VNC_QUALITY - 1))
			[ "$VNC_QUALITY" -lt 0 ] && VNC_QUALITY=0
		fi
	fi

	# 构建 VNC 服务器参数 (使用 rfbauth 而不是 passwd)
	VNC_ARGS="-geometry $VNC_SIZE -localhost=0 -rfbauth ~/.vnc/passwd"
	VNC_ARGS="$VNC_ARGS -depth $VNC_DEPTH"
	VNC_ARGS="$VNC_ARGS -DeferTime $VNC_DEFERTIME"

	# 添加编码相关参数 (注意：这些参数主要影响客户端连接，服务器端主要设置基础参数)
	case "$VNC_ENCODING" in
		"tight")
			# TigerVNC 服务器端不直接设置编码，这些参数由客户端协商
			echo "VNC: 推荐客户端使用 Tight 编码"
			;;
		"zrle")
			echo "VNC: 推荐客户端使用 ZRLE 编码"
			;;
		"hextile")
			echo "VNC: 推荐客户端使用 Hextile 编码"
			;;
		"raw")
			echo "VNC: 推荐客户端使用 Raw 编码"
			;;
	esac

	# 帧率控制 (通过环境变量传递给 VNC 服务器)
	export VNC_FRAMERATE

	echo "VNC: 启动参数 - 编码:$VNC_ENCODING 质量:$VNC_QUALITY 压缩:$VNC_COMPRESS 帧率:${VNC_FRAMERATE}fps 深度:${VNC_DEPTH}bit"

	# 清理可能存在的旧 VNC 会话
	echo "VNC: 清理旧的 VNC 会话..."
	vncserver -kill "$DISPLAY" 2>/dev/null || true
	pkill -f "Xtigervnc.*${DISPLAY}" 2>/dev/null || true

	# 等待端口释放
	sleep 2

	# 设置 X11 环境变量和必要的系统配置
	export XAUTHORITY=~/.Xauthority
	export XDG_RUNTIME_DIR=/tmp
	export XDG_SESSION_TYPE=x11
	export XDG_CURRENT_DESKTOP=FLWM

	# 确保 X11 相关目录存在
	mkdir -p /tmp/.X11-unix
	chmod 1777 /tmp/.X11-unix

	# 创建必要的设备文件（如果不存在）
	if [ ! -e /dev/null ]; then
		mknod /dev/null c 1 3 2>/dev/null || true
	fi
	if [ ! -e /dev/zero ]; then
		mknod /dev/zero c 1 5 2>/dev/null || true
	fi
	if [ ! -e /dev/random ]; then
		mknod /dev/random c 1 8 2>/dev/null || true
	fi
	if [ ! -e /dev/urandom ]; then
		mknod /dev/urandom c 1 9 2>/dev/null || true
	fi

	# 创建简单的 VNC 启动脚本
	cat > ~/.vnc/xstartup << 'EOF'
#!/bin/bash
export XDG_RUNTIME_DIR=/tmp
flwm &
EOF
	chmod +x ~/.vnc/xstartup

	open_port 5901

	# 初始化 X11 环境（使用简化版本）
	echo "VNC: 初始化 X11 环境..."
	if ! /usr/local/bin/init-x11-simple.sh; then
		echo "VNC: ❌ X11 环境初始化失败，尝试基本初始化..."
		# 基本的环境设置作为后备
		mkdir -p /tmp/.X11-unix
		chmod 1777 /tmp/.X11-unix 2>/dev/null || true
		export XAUTHORITY=~/.Xauthority
		export XDG_RUNTIME_DIR=/tmp
		touch ~/.Xauthority 2>/dev/null || true
		chmod 600 ~/.Xauthority 2>/dev/null || true
		echo "VNC: 基本环境设置完成"
	fi

	# 启动 TigerVNC 服务器 (直接使用 Xtigervnc，避免包装器问题)
	echo "VNC: 启动 TigerVNC 服务器 (显示: $DISPLAY)"
	echo "VNC: 使用直接启动方式避免包装器问题"

	# 计算显示端口
	DISPLAY_NUM=${DISPLAY#:}
	VNC_PORT=$((5900 + DISPLAY_NUM))

	# 使用最简单的 Xtigervnc 启动方式
	echo "VNC: 尝试启动 TigerVNC (基本模式)..."
	Xtigervnc "$DISPLAY" \
		-geometry "$VNC_SIZE" \
		-depth "$VNC_DEPTH" \
		-rfbauth ~/.vnc/passwd \
		-rfbport "$VNC_PORT" \
		-desktop "aTrust VNC Desktop" \
		-dpi 96 \
		-SecurityTypes VncAuth &

	VNC_PID=$!
	echo "VNC: Xtigervnc 启动，PID: $VNC_PID (基本模式)"

	# 等待一下看是否启动成功
	sleep 2

	# 如果基本模式失败，尝试更简单的模式
	if ! kill -0 "$VNC_PID" 2>/dev/null; then
		echo "VNC: 基本模式失败，尝试最简模式..."
		Xtigervnc "$DISPLAY" \
			-geometry "$VNC_SIZE" \
			-depth 24 \
			-rfbauth ~/.vnc/passwd \
			-rfbport "$VNC_PORT" \
			-desktop "VNC Desktop" &

		VNC_PID=$!
		echo "VNC: Xtigervnc 启动，PID: $VNC_PID (最简模式)"
	fi

	# 检查 VNC 服务器是否成功启动
	sleep 3
	if kill -0 "$VNC_PID" 2>/dev/null && pgrep -f "Xtigervnc.*${DISPLAY}" >/dev/null; then
		echo "VNC: ✅ TigerVNC 服务器启动成功 (PID: $VNC_PID)"

		# 启动窗口管理器 (因为 Xtigervnc 不支持 -xstartup)
		sleep 1
		DISPLAY="$DISPLAY" flwm &
		echo "VNC: 窗口管理器 flwm 已启动"
	else
		echo "VNC: ❌ TigerVNC 服务器启动失败"

		# 查看可能的错误日志
		for logfile in ~/.vnc/*${DISPLAY}.log ~/.vnc/$(hostname)${DISPLAY}.log; do
			if [ -f "$logfile" ]; then
				echo "=== VNC 日志: $logfile ==="
				tail -10 "$logfile"
			fi
		done

		# 运行故障排除脚本
		echo "VNC: 运行故障排除诊断..."
		/usr/local/bin/vnc-troubleshoot.sh check || true

		return 1
	fi
	stalonetray -f 0 2> /dev/null &

	if [ -n "$ECPASSWORD" ]; then
		echo "ECPASSWORD has been deprecated, because of the confusion of its name." >&2
		echo "Use CLIP_TEXT instead." >&2
	fi

	[ -z "$CLIP_TEXT" ] && CLIP_TEXT="$ECPASSWORD"

	# 将 easyconnect 的密码放入粘贴板中，应对密码复杂且无法保存的情况 (eg: 需要短信验证登录)
	# 感谢 @yakumioto https://github.com/Hagb/docker-easyconnect/pull/8
	echo "$CLIP_TEXT" | DISPLAY=:1 xclip -selection c

	# 环境变量USE_NOVNC不为空时，启动 easy-novnc
	if [ -n "$USE_NOVNC" ]; then
		open_port 8080
		novnc
	fi

	# 启动 VNC 性能监控和智能优化 (根据模式选择)
	if [ "${VNC_LITE_MODE:-0}" = "1" ]; then
		echo "启动 VNC 轻量级监控模式..."
		vnc-monitor-lite.sh monitor &
		VNC_LITE_PID=$!
		echo "轻量级监控已启动，PID: $VNC_LITE_PID"
	elif [ "$VNC_AUTO_OPTIMIZE" = "1" ]; then
		echo "启动 VNC 智能自动优化系统..."

		# 生成初始优化配置
		vnc-optimize.sh auto

		# 启动智能优化守护进程（高级模式）
		if [ "${VNC_SMART_OPTIMIZE:-0}" = "1" ]; then
			echo "启动智能优化守护进程..."
			vnc-auto-optimizer.sh monitor &
			VNC_OPTIMIZER_PID=$!
			echo "智能优化守护进程已启动，PID: $VNC_OPTIMIZER_PID"
		else
			# 启动基础性能监控（兼容模式）
			echo "启动基础性能监控..."
			vnc-performance-monitor.sh monitor &
			VNC_MONITOR_PID=$!
			echo "性能监控已启动，PID: $VNC_MONITOR_PID"
		fi
	else
		echo "VNC 监控已禁用 (设置 VNC_LITE_MODE=1 启用轻量级监控)"
	fi

	# 内存优化检查
	if [ "${VNC_MEMORY_OPTIMIZE:-0}" = "1" ]; then
		echo "启动内存优化..."
		memory-optimizer.sh auto &
		echo "内存优化已启动"
	fi

	# 启动低资源优化器 (如果启用)
	if [ "$VNC_AUTO_LOWRES" = "1" ]; then
		echo "启动 VNC 低资源优化器..."
		vnc-lowres-optimizer.sh detect
		# 应用低资源配置
		if [ -f "/tmp/vnc-lowres-config" ]; then
			source /tmp/vnc-lowres-config
			echo "已应用低资源优化配置"
		fi
	fi

}

keep_pinging() {
	[ -n "$PING_ADDR" ] && while sleep $PING_INTERVAL; do
		busybox ping -c1 -W1 -w1 "$PING_ADDR" >/dev/null 2>/dev/null
	done &
}

# 部分服务器禁ping，用wget一个网页的url代替
keep_pinging_url() {
	[ -n "$PING_ADDR_URL" ] && while sleep $PING_INTERVAL; do
		timeout 10 busybox wget -q --spider "$PING_ADDR_URL" 2>/dev/null
	done &
}

# container 再次运行时清除 /tmp 中的锁，使 container 能够反复使用。
# 感谢 @skychan https://github.com/Hagb/docker-easyconnect/issues/4#issuecomment-660842149
for f in /tmp/* /tmp/.*; do
	[ "/tmp/.X11-unix" != "$f" ] && rm -rf -- "$f"
done

ulimit -n 1048576 # https://github.com/Hagb/docker-easyconnect/issues/245 @rikaunite
forward_ports &
start_danted &
start_tinyproxy &
config_vpn_iptables &
force_open_ports &
keep_pinging &
keep_pinging_url &
if [ -z "$DISPLAY" ]
then
	export DISPLAY=:1
	start_tigervncserver &
fi

init_vpn_config
wait

[ -n "$EXIT" ] && export MAX_RETRY=0
start-sangfor.sh &
wait $!

if [ "EC_GUI" = "$_VPN_TYPE" ]; then
	sync_ec2volume
fi
