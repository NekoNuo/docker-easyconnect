# Build stage - 构建必要的组件
FROM debian:bookworm-slim AS build

ARG ANDROID_PATCH BUILD_ENV=local MIRROR_URL=http://ftp.cn.debian.org/debian/ EC_HOST

COPY ["./build-scripts/config-apt.sh", "./build-scripts/get-echost-names.sh", "/tmp/build-scripts/"]

RUN . /tmp/build-scripts/config-apt.sh && \
    . /tmp/build-scripts/get-echost-names.sh && \
    case "$(dpkg --print-architecture)" in \
        amd64 | i386 | arm64 ) go=golang-go ;; \
        * ) go=gccgo-go ;; \
    esac && \
    apt-get update && \
    apt-get install -y --no-install-recommends --no-install-suggests ca-certificates \
                    busybox libssl-dev automake $go $ecgccpkg build-essential

RUN mkdir results && cd results && mkdir fake-hwaddr tinyproxy-ws novnc fake-getlogin && mkdir /tmp/src -p

COPY fake-hwaddr /tmp/src/fake-hwaddr/
COPY fake-getlogin /tmp/src/fake-getlogin/

RUN . /tmp/build-scripts/get-echost-names.sh && \
    cd /tmp/src/fake-hwaddr && CC=${ec_cc} make clean all && install -D fake-hwaddr.so /results/fake-hwaddr/usr/local/lib/fake-hwaddr.so && \
    cd /tmp/src/fake-getlogin && CC=${ec_cc} make clean all && install -D fake-getlogin.so /results/fake-getlogin/usr/local/lib/fake-getlogin.so

# https://github.com/tinyproxy/tinyproxy/pull/211#issue-382736027
ARG TINYPROXY_COMMIT=991e47d8ebd4b12710828b2b486535e4c25ba26c

RUN cd /tmp/src/ && \
    busybox wget https://github.com/tinyproxy/tinyproxy/archive/${TINYPROXY_COMMIT}.zip -O tinyproxy.zip && \
    busybox unzip tinyproxy.zip && mv tinyproxy-${TINYPROXY_COMMIT} tinyproxy && cd tinyproxy && \
    ./autogen.sh --prefix=/usr && make && install -D src/tinyproxy /results/tinyproxy-ws/usr/bin/tinyproxy

ARG NOVNC_METHOD=min-size GOPROXY=http://proxy.golang.com.cn,direct

RUN cd /tmp/src/ && \
    case "${NOVNC_METHOD}" in \
      min-size ) \
        busybox wget https://github.com/novnc/noVNC/archive/refs/heads/master.zip -O novnc.zip && \
        busybox wget https://github.com/novnc/websockify-other/archive/refs/heads/master.zip -O novnc-websockify.zip && \
        busybox unzip novnc.zip && mv noVNC-master novnc && ln -s vnc.html novnc/index.html && \
        sed -i "s#UI.initSetting('path', 'websockify')#UI.initSetting('path','websockify/websockify')#" novnc/app/ui.js && \
        mkdir -p /results/novnc/usr/local/share/ && mv novnc /results/novnc/usr/local/share/novnc && \
        busybox unzip novnc-websockify.zip && mv websockify-other-master novnc-websockify && \
        cd novnc-websockify/c/ && make && install -D websockify /results/novnc/usr/local/bin/websockify ;; \
      easy-novnc ) \
        busybox wget https://github.com/pgaskin/easy-novnc/archive/refs/heads/master.zip -O easy-novnc.zip && \
        busybox unzip easy-novnc.zip && mv easy-novnc-master easy-novnc && cd easy-novnc && \
        go build -ldflags "-s -w" -gccgoflags "-Wl,-s,-gc-sections -fdata-sections -ffunction-sections -static-libgo" && \
        install -D easy-novnc /results/novnc/usr/local/bin/easy-novnc ;; \
      * ) printf "Not a vaild value of NOVNC_METHOD: %s\n" "${NOVNC_METHOD}" >&2 && false ;; \
    esac && ln -s novnc-${NOVNC_METHOD}.sh /results/novnc/usr/local/bin/novnc

# Main stage - 主要的应用程序镜像
FROM debian:bookworm-slim

ARG ANDROID_PATCH MIRROR_URL=http://ftp.cn.debian.org/debian/ EC_HOST VPN_TYPE=EC_GUI

COPY ["./build-scripts/config-apt.sh", "./build-scripts/get-echost-names.sh",  "./build-scripts/add-qemu.sh", \
      "/tmp/build-scripts/"]

RUN . /tmp/build-scripts/config-apt.sh && \
    . /tmp/build-scripts/get-echost-names.sh && \
    . /tmp/build-scripts/add-qemu.sh && \
    apt-get update && \
    if [ "ATRUST" = "$VPN_TYPE" ]; then \
        extra_pkgs="libssl1.1 libatk-bridge2.0-0 libgtk-3-0 libgbm1 libqt5x11extras5 procps \
                    libqt5core5a libqt5network5 libqt5widgets5 libldap-2.4-2 stalonetray"; \
    else \
        extra_pkgs="libgtk2.0-0 libdbus-glib-1-2 libgconf-2-4 libnspr4:$EC_HOST libnss3:$EC_HOST"; \
    fi && \
    apt-get install -y --no-install-recommends --no-install-suggests \
        libx11-xcb1 libnss3 libasound2 iptables xclip libxtst6 \
        dante-server tigervnc-standalone-server tigervnc-tools psmisc flwm x11-utils \
        busybox libssl-dev iproute2 tinyproxy-bin libxss1 ca-certificates \
        fonts-wqy-microhei socat jq bc netcat-openbsd $qemu_pkgs $extra_pkgs && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd -r socks && useradd -r -g socks socks

COPY ["./build-scripts/install-vpn-gui.sh", "./build-scripts/mk-qemu-wrapper.sh", "/tmp/build-scripts/"]

COPY ./docker-root-preinst /

ARG VPN_URL ELECTRON_URL USE_VPN_ELECTRON VPN_DEB_PATH

RUN /tmp/build-scripts/install-vpn-gui.sh

COPY ./docker-root /

COPY --from=build /results/fake-hwaddr/ /results/fake-getlogin/ /results/tinyproxy-ws/ /results/novnc/ /

# 设置 VNC 优化脚本权限
RUN chmod +x /usr/local/bin/vnc-performance-monitor.sh && \
    chmod +x /usr/local/bin/vnc-optimize.sh && \
    chmod +x /usr/local/bin/vnc-lowres-optimizer.sh && \
    mkdir -p /etc/tigervnc /var/log && \
    touch /var/log/vnc-performance.log

#ENV TYPE="" PASSWORD="" LOOP=""
#ENV DISPLAY
#ENV USE_NOVNC=""

ENV PING_INTERVAL=1800

VOLUME /root/ /usr/share/sangfor/EasyConnect/resources/logs/

CMD ["start.sh"]
