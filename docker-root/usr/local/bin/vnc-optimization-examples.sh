#!/bin/bash
# VNC 优化配置示例和使用说明

set -euo pipefail

# 显示使用说明
show_usage() {
    cat << 'EOF'
=== VNC 智能优化系统使用说明 ===

## 🚀 快速启用

### 基础自动优化（推荐）
docker run -e VNC_AUTO_OPTIMIZE=1 ...

### 智能优化守护进程（高级）
docker run -e VNC_AUTO_OPTIMIZE=1 -e VNC_SMART_OPTIMIZE=1 ...

### 低资源环境优化
docker run -e VNC_AUTO_LOWRES=1 ...

## 📊 环境变量配置

### 基础配置
VNC_AUTO_OPTIMIZE=1          # 启用自动优化
VNC_SMART_OPTIMIZE=1         # 启用智能优化守护进程
VNC_AUTO_LOWRES=1           # 启用低资源自动检测
VNC_DEBUG=1                 # 启用调试日志

### 监控配置
VNC_MONITOR_INTERVAL=15     # 监控间隔（秒）
VNC_LOG_FILE=/var/log/vnc-auto-optimizer.log

### 优化阈值配置
VNC_PRESSURE_LIGHT=15       # 轻度优化阈值
VNC_PRESSURE_MEDIUM=35      # 中度优化阈值  
VNC_PRESSURE_HEAVY=55       # 重度优化阈值

## 🎯 优化级别说明

### 级别 0 - 默认配置
- 帧率: 30fps
- 质量: 6 (0-9)
- 压缩: 6 (0-9)
- 色彩深度: 24bit
- 分辨率: 1110x620

### 级别 1 - 轻度优化
- 帧率: 25fps
- 质量: 5
- 压缩: 7
- 延迟: 5ms

### 级别 2 - 中度优化  
- 帧率: 18fps
- 质量: 3
- 压缩: 8
- 色彩深度: 16bit
- 延迟: 25ms

### 级别 3 - 重度优化
- 帧率: 10fps
- 质量: 1
- 压缩: 9
- 色彩深度: 8bit
- 分辨率: 800x600
- 延迟: 80ms

## 🔧 手动控制命令

### 查看优化状态
docker exec <container> vnc-auto-optimizer.sh status

### 重置优化配置
docker exec <container> vnc-auto-optimizer.sh reset

### 测试资源获取
docker exec <container> vnc-auto-optimizer.sh test

### 查看优化历史
docker exec <container> tail -f /tmp/vnc-optimization-history.log

## 📈 压力评分算法

系统会根据以下指标计算资源压力评分：

### CPU 压力 (最高 45 分)
- VNC 进程 CPU > 80%: +25 分
- VNC 进程 CPU > 50%: +15 分  
- VNC 进程 CPU > 30%: +8 分
- 系统 CPU > 90%: +20 分
- 系统 CPU > 70%: +12 分

### 内存压力 (最高 35 分)
- VNC 内存 > 800MB: +20 分
- VNC 内存 > 500MB: +12 分
- VNC 内存 > 300MB: +6 分
- 系统内存 > 85%: +15 分
- 系统内存 > 70%: +8 分

### 连接压力 (最高 12 分)
- 连接数 > 5: +12 分
- 连接数 > 3: +6 分

### 系统负载 (最高 15 分)
- 负载 > 3.0: +15 分
- 负载 > 2.0: +8 分

## 🛡️ 安全特性

- 最小优化间隔: 60秒（避免频繁调整）
- 滑动窗口平均: 5个采样点
- 优化历史记录: 完整的操作日志
- 智能回滚: 压力降低时自动恢复
- 配置验证: 防止无效参数

## 📋 故障排除

### 优化不生效
1. 检查环境变量: echo $VNC_AUTO_OPTIMIZE
2. 查看日志: tail -f /var/log/vnc-auto-optimizer.log
3. 验证进程: ps aux | grep vnc-auto-optimizer

### 性能仍然不佳
1. 检查压力评分: vnc-auto-optimizer.sh status
2. 手动重置: vnc-auto-optimizer.sh reset
3. 调整阈值: 降低 VNC_PRESSURE_* 值

### 日志文件过大
1. 自动清理: memory-cleanup.sh logs
2. 手动清理: > /var/log/vnc-auto-optimizer.log

EOF
}

# 显示配置示例
show_examples() {
    cat << 'EOF'
=== Docker 运行示例 ===

## 基础优化模式
docker run -d \
  -e VNC_AUTO_OPTIMIZE=1 \
  -e PASSWORD=your_password \
  -p 5901:5901 \
  -p 1080:1080 \
  your-easyconnect-image

## 智能优化模式（推荐）
docker run -d \
  -e VNC_AUTO_OPTIMIZE=1 \
  -e VNC_SMART_OPTIMIZE=1 \
  -e VNC_DEBUG=1 \
  -e PASSWORD=your_password \
  -p 5901:5901 \
  -p 1080:1080 \
  -v /path/to/logs:/var/log \
  your-easyconnect-image

## 低资源环境
docker run -d \
  --memory=512m \
  --cpus=1.0 \
  -e VNC_AUTO_OPTIMIZE=1 \
  -e VNC_AUTO_LOWRES=1 \
  -e VNC_NETWORK_MODE=minimal \
  -e PASSWORD=your_password \
  -p 5901:5901 \
  your-easyconnect-image

## 自定义阈值
docker run -d \
  -e VNC_AUTO_OPTIMIZE=1 \
  -e VNC_SMART_OPTIMIZE=1 \
  -e VNC_PRESSURE_LIGHT=10 \
  -e VNC_PRESSURE_MEDIUM=25 \
  -e VNC_PRESSURE_HEAVY=40 \
  -e VNC_MONITOR_INTERVAL=10 \
  -e PASSWORD=your_password \
  -p 5901:5901 \
  your-easyconnect-image

=== Docker Compose 示例 ===

version: '3.8'
services:
  easyconnect:
    image: your-easyconnect-image
    environment:
      - VNC_AUTO_OPTIMIZE=1
      - VNC_SMART_OPTIMIZE=1
      - VNC_DEBUG=1
      - PASSWORD=your_password
      - VNC_MONITOR_INTERVAL=15
      - VNC_PRESSURE_LIGHT=15
      - VNC_PRESSURE_MEDIUM=35
      - VNC_PRESSURE_HEAVY=55
    ports:
      - "5901:5901"
      - "1080:1080"
      - "8888:8888"
    volumes:
      - ./logs:/var/log
      - ./config:/root/conf
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '2.0'
        reservations:
          memory: 512M
          cpus: '1.0'

EOF
}

# 性能测试
run_performance_test() {
    echo "=== VNC 优化性能测试 ==="
    
    # 检查必要工具
    local missing_tools=()
    for tool in bc jq netstat ps; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo "⚠️  缺少工具: ${missing_tools[*]}"
        echo "某些功能可能受限"
    fi
    
    # 测试资源获取
    echo ""
    echo "1. 测试系统资源获取..."
    if vnc-auto-optimizer.sh test >/dev/null 2>&1; then
        echo "✅ 资源获取正常"
    else
        echo "❌ 资源获取失败"
    fi
    
    # 测试优化配置生成
    echo ""
    echo "2. 测试优化配置生成..."
    local test_config="/tmp/test-vnc-config"
    cat > "$test_config" << 'EOF'
export VNC_FRAMERATE=20
export VNC_QUALITY=4
export VNC_COMPRESS=7
EOF
    
    if [ -f "$test_config" ]; then
        echo "✅ 配置生成正常"
        rm -f "$test_config"
    else
        echo "❌ 配置生成失败"
    fi
    
    # 测试状态管理
    echo ""
    echo "3. 测试状态管理..."
    if vnc-auto-optimizer.sh status >/dev/null 2>&1; then
        echo "✅ 状态管理正常"
    else
        echo "❌ 状态管理失败"
    fi
    
    echo ""
    echo "性能测试完成"
}

# 主函数
main() {
    case "${1:-usage}" in
        "usage"|"help")
            show_usage
            ;;
        "examples")
            show_examples
            ;;
        "test")
            run_performance_test
            ;;
        *)
            echo "用法: $0 [usage|examples|test]"
            echo "  usage    - 显示使用说明（默认）"
            echo "  examples - 显示配置示例"
            echo "  test     - 运行性能测试"
            exit 1
            ;;
    esac
}

main "$@"
