#!/bin/bash
# aTrust VNC 快速启动脚本

set -euo pipefail

# 配置
DOCKER_IMAGE="your-dockerhub-username/docker-easyconnect-atrust:atrust-amd64"
CONTAINER_NAME="atrust-vnc"
VNC_PASSWORD=""
SERVER_TYPE="normal"  # normal, lowres, minimal

# 颜色输出
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

# 显示帮助信息
show_help() {
    echo "aTrust VNC 快速启动脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -p, --password PASSWORD    设置 VNC 密码"
    echo "  -t, --type TYPE           服务器类型: normal, lowres, minimal"
    echo "  -i, --image IMAGE         Docker 镜像名称"
    echo "  -n, --name NAME           容器名称"
    echo "  -h, --help                显示帮助信息"
    echo ""
    echo "服务器类型说明:"
    echo "  normal   - 标准配置 (推荐 >1GB 内存)"
    echo "  lowres   - 低资源配置 (512MB-1GB 内存)"
    echo "  minimal  - 最小配置 (<512MB 内存)"
    echo ""
    echo "示例:"
    echo "  $0 -p mypassword -t normal"
    echo "  $0 --password mypassword --type lowres"
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--password)
                VNC_PASSWORD="$2"
                shift 2
                ;;
            -t|--type)
                SERVER_TYPE="$2"
                shift 2
                ;;
            -i|--image)
                DOCKER_IMAGE="$2"
                shift 2
                ;;
            -n|--name)
                CONTAINER_NAME="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 检查 Docker 是否运行
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker 未运行或无权限访问"
        exit 1
    fi
    log_info "Docker 检查通过"
}

# 检查镜像是否存在
check_image() {
    if ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
        log_warn "镜像 $DOCKER_IMAGE 不存在，尝试拉取..."
        docker pull "$DOCKER_IMAGE" || {
            log_error "无法拉取镜像 $DOCKER_IMAGE"
            exit 1
        }
    fi
    log_info "镜像检查通过: $DOCKER_IMAGE"
}

# 停止现有容器
stop_existing() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_warn "停止现有容器: $CONTAINER_NAME"
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
}

# 获取配置
get_config() {
    local encoding quality compress framerate depth size memory cpu
    
    case "$SERVER_TYPE" in
        "minimal")
            encoding="tight"
            quality="0"
            compress="9"
            framerate="5"
            depth="8"
            size="640x480"
            memory="256m"
            cpu="0.5"
            log_info "使用最小配置 (适合 <512MB 内存)"
            ;;
        "lowres")
            encoding="tight"
            quality="2"
            compress="8"
            framerate="10"
            depth="16"
            size="800x600"
            memory="512m"
            cpu="1.0"
            log_info "使用低资源配置 (适合 512MB-1GB 内存)"
            ;;
        "normal"|*)
            encoding="tight"
            quality="6"
            compress="6"
            framerate="30"
            depth="24"
            size="1110x620"
            memory="1g"
            cpu="2.0"
            log_info "使用标准配置 (推荐 >1GB 内存)"
            ;;
    esac
    
    echo "$encoding $quality $compress $framerate $depth $size $memory $cpu"
}

# 启动容器
start_container() {
    local config
    config=($(get_config))
    
    local encoding="${config[0]}"
    local quality="${config[1]}"
    local compress="${config[2]}"
    local framerate="${config[3]}"
    local depth="${config[4]}"
    local size="${config[5]}"
    local memory="${config[6]}"
    local cpu="${config[7]}"
    
    log_info "启动 aTrust 容器..."
    log_info "配置: ${encoding} 编码, 质量${quality}, 压缩${compress}, ${framerate}fps, ${depth}bit, ${size}"
    
    docker run -d \
        --name "$CONTAINER_NAME" \
        --device /dev/net/tun \
        --cap-add NET_ADMIN \
        --sysctl net.ipv4.conf.default.route_localnet=1 \
        --memory="$memory" \
        --cpus="$cpu" \
        -p 127.0.0.1:5901:5901 \
        -p 127.0.0.1:1080:1080 \
        -p 127.0.0.1:8888:8888 \
        -p 127.0.0.1:54631:54631 \
        -p 127.0.0.1:8080:8080 \
        -v "${CONTAINER_NAME}-data:/root" \
        -e PASSWORD="$VNC_PASSWORD" \
        -e URLWIN=1 \
        -e VNC_AUTO_LOWRES=1 \
        -e VNC_AUTO_OPTIMIZE=1 \
        -e VNC_ENCODING="$encoding" \
        -e VNC_QUALITY="$quality" \
        -e VNC_COMPRESS="$compress" \
        -e VNC_FRAMERATE="$framerate" \
        -e VNC_DEPTH="$depth" \
        -e VNC_SIZE="$size" \
        -e USE_NOVNC=1 \
        "$DOCKER_IMAGE"
    
    log_info "容器启动成功: $CONTAINER_NAME"
}

# 显示连接信息
show_connection_info() {
    echo ""
    echo -e "${BLUE}=== aTrust VNC 连接信息 ===${NC}"
    echo -e "${GREEN}VNC 客户端连接:${NC}"
    echo "  地址: 127.0.0.1:5901"
    echo "  密码: $VNC_PASSWORD"
    echo ""
    echo -e "${GREEN}Web VNC (noVNC):${NC}"
    echo "  地址: http://127.0.0.1:8080"
    echo ""
    echo -e "${GREEN}aTrust Web 登录:${NC}"
    echo "  地址: https://127.0.0.1:54631"
    echo "  (忽略证书警告)"
    echo ""
    echo -e "${GREEN}代理服务:${NC}"
    echo "  SOCKS5: 127.0.0.1:1080"
    echo "  HTTP:   127.0.0.1:8888"
    echo ""
    echo -e "${GREEN}管理命令:${NC}"
    echo "  查看日志: docker logs $CONTAINER_NAME"
    echo "  进入容器: docker exec -it $CONTAINER_NAME bash"
    echo "  停止容器: docker stop $CONTAINER_NAME"
    echo "  性能监控: docker exec $CONTAINER_NAME vnc-performance-monitor.sh status"
    echo "  资源优化: docker exec $CONTAINER_NAME vnc-lowres-optimizer.sh detect"
}

# 等待容器启动
wait_for_container() {
    log_info "等待容器启动..."
    local count=0
    while [ $count -lt 30 ]; do
        if docker exec "$CONTAINER_NAME" pgrep -f "aTrustAgent" >/dev/null 2>&1; then
            log_info "aTrust 服务已启动"
            return 0
        fi
        sleep 2
        count=$((count + 1))
        echo -n "."
    done
    echo ""
    log_warn "容器启动可能需要更长时间，请检查日志"
}

# 主函数
main() {
    echo -e "${BLUE}aTrust VNC 快速启动脚本${NC}"
    echo ""
    
    # 解析参数
    parse_args "$@"
    
    # 检查密码
    if [ -z "$VNC_PASSWORD" ]; then
        echo -n "请输入 VNC 密码: "
        read -s VNC_PASSWORD
        echo ""
        if [ -z "$VNC_PASSWORD" ]; then
            log_error "密码不能为空"
            exit 1
        fi
    fi
    
    # 执行启动流程
    check_docker
    check_image
    stop_existing
    start_container
    wait_for_container
    show_connection_info
    
    log_info "启动完成！"
}

# 捕获中断信号
trap 'log_warn "脚本被中断"; exit 1' INT TERM

# 运行主函数
main "$@"
