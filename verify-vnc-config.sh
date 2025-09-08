#!/bin/bash
# VNC 配置验证脚本

echo "=== VNC 配置验证 ==="
echo ""

# 1. 检查 TigerVNC 配置文件
echo "1. 检查 TigerVNC 配置文件:"
if [ -f "docker-root/etc/tigervnc/vncserver-config-defaults" ]; then
    echo "✅ 配置文件存在"
    echo "配置内容:"
    cat docker-root/etc/tigervnc/vncserver-config-defaults
    echo ""
    
    # 验证配置语法
    echo "验证配置语法:"
    if perl -c docker-root/etc/tigervnc/vncserver-config-defaults 2>/dev/null; then
        echo "✅ 配置语法正确"
    else
        echo "❌ 配置语法错误"
        perl -c docker-root/etc/tigervnc/vncserver-config-defaults
    fi
else
    echo "❌ 配置文件不存在"
fi

echo ""

# 2. 检查启动脚本中的 VNC 相关部分
echo "2. 检查启动脚本中的 VNC 启动参数:"
if [ -f "docker-root/usr/local/bin/start.sh" ]; then
    echo "VNC 启动函数:"
    grep -A 20 "start_tigervncserver()" docker-root/usr/local/bin/start.sh | head -25
    echo ""
    
    echo "VNC 参数构建:"
    grep -A 5 "VNC_ARGS=" docker-root/usr/local/bin/start.sh
else
    echo "❌ 启动脚本不存在"
fi

echo ""

# 3. 检查 Dockerfile 中的 VNC 相关设置
echo "3. 检查 Dockerfile 中的 VNC 相关设置:"
if [ -f "Dockerfile" ]; then
    echo "TigerVNC 安装:"
    grep -i "tigervnc" Dockerfile || echo "未找到 TigerVNC 安装"
    echo ""
    
    echo "VNC 脚本权限设置:"
    grep -A 5 "chmod.*vnc" Dockerfile || echo "未找到 VNC 脚本权限设置"
else
    echo "❌ Dockerfile 不存在"
fi

echo ""

# 4. 检查优化脚本
echo "4. 检查 VNC 优化脚本:"
for script in vnc-performance-monitor.sh vnc-optimize.sh vnc-lowres-optimizer.sh; do
    if [ -f "docker-root/usr/local/bin/$script" ]; then
        echo "✅ $script 存在"
    else
        echo "❌ $script 不存在"
    fi
done

echo ""

# 5. 生成测试用的 VNC 启动命令
echo "5. 建议的测试命令:"
echo ""
echo "# 最小化测试 (仅基础 VNC)"
echo "docker run --rm -it \\"
echo "  --device /dev/net/tun \\"
echo "  --cap-add NET_ADMIN \\"
echo "  -e PASSWORD=test123 \\"
echo "  -e VNC_AUTO_LOWRES=0 \\"
echo "  -e VNC_AUTO_OPTIMIZE=0 \\"
echo "  -p 127.0.0.1:5901:5901 \\"
echo "  gys619/docker-easyconnect-atrust:atrust-amd64"
echo ""

echo "# 完整功能测试"
echo "docker run --rm -it \\"
echo "  --device /dev/net/tun \\"
echo "  --cap-add NET_ADMIN \\"
echo "  --sysctl net.ipv4.conf.default.route_localnet=1 \\"
echo "  -e PASSWORD=test123 \\"
echo "  -e USE_NOVNC=1 \\"
echo "  -e VNC_AUTO_LOWRES=1 \\"
echo "  -e VNC_AUTO_OPTIMIZE=1 \\"
echo "  -p 127.0.0.1:5901:5901 \\"
echo "  -p 127.0.0.1:8080:8080 \\"
echo "  -p 127.0.0.1:54631:54631 \\"
echo "  gys619/docker-easyconnect-atrust:atrust-amd64"
echo ""

echo "=== 验证完成 ==="
