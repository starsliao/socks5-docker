# 3proxy 1.0.2 (官方最新版) SOCKS5 代理镜像, 只有 amd64
#
# 3proxy 用 glibc 静态编译 (官方 Makefile.Linux 的 STATIC 模式: 不带插件, 只用内置 DNS 解析);
# 3proxy 一个连接一个线程, glibc 的线程创建和 malloc 比 musl 快, 新建连接更省 CPU.
# 运行层是 busybox, 只给 entrypoint.sh 和账号管理脚本 user 提供 shell
#
# 构建: docker build --provenance=false -t 3proxy:1.0.2 .

FROM debian:trixie-slim AS build

ARG VER=1.0.2
ARG SHA256=60967fe736bb0ba93fe125c9574c8ad3fec1d2d94d11d981b871379bd94de964

RUN apt-get update && apt-get install -y --no-install-recommends gcc make libc6-dev
ADD https://github.com/3proxy/3proxy/releases/download/${VER}/3proxy-${VER}.tar.gz /src/
# HTTPSRV=false: 不编内置 HTTP 服务和 web 管理界面, 用不上
RUN cd /src && echo "${SHA256}  3proxy-${VER}.tar.gz" | sha256sum -c - \
 && tar xzf 3proxy-${VER}.tar.gz && cd 3proxy-${VER} \
 && make -f Makefile.Linux -j"$(nproc)" STATIC=true HTTPSRV=false \
 && strip bin/3proxy && cp bin/3proxy /usr/local/bin/

FROM busybox:1.37-musl

COPY --from=build /usr/local/bin/3proxy /usr/local/bin/3proxy
COPY --chmod=755 entrypoint.sh user /usr/local/bin/
RUN mkdir -p /etc/3proxy /run
CMD ["entrypoint.sh"]
