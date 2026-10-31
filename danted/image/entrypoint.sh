#!/bin/sh
# 容器跑 host 网络: 网卡不一定叫 eth0, 端口也不一定是 2020.
# 启动时按 PORT / EXTERNAL (默认取默认路由的网卡) 改写配置, 写到 /run 下再启动, 不动原配置 (可能是挂载进来的)
PORT="${PORT:-2020}"
EXTERNAL="${EXTERNAL:-$(awk '$2 == "00000000" { print $1; exit }' /proc/net/route)}"

sed -e "s/^internal:.*/internal: 0.0.0.0 port = ${PORT}/" \
    -e "s/^external:.*/external: ${EXTERNAL:-eth0}/" \
    /home/danted/conf/sockd.conf > /run/sockd.conf

exec sockd -f /run/sockd.conf -N 4
