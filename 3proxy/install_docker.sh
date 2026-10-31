#!/bin/bash
#
# 3proxy Socks5 一键 Docker 安装  https://github.com/starsliao/socks5-docker
# 镜像是自己打的 3proxy:1.0.2 (官方最新版, glibc 静态编译 + busybox, 只有 amd64; 构建见 image/)
#
# 用法 (root):
#   bash install_docker.sh        国外服务器: 镜像从 Docker Hub 拉
#   bash install_docker.sh cn     国内服务器: 镜像从阿里云拉, docker 也走阿里云源装
# 账号默认随机生成 (账号 16 位, 密码 8 位), 装完会打印; 每次运行都会重置账号
# 可选参数用环境变量传, 例如:  PORT=1080 PROXY_USER=xxx PROXY_PASS=xxx bash install_docker.sh [cn]
#   PORT 端口 (2020)    PROXY_USER / PROXY_PASS 账号密码    MAXCONN 最大并发连接 (10000)
#   DNS 指定 DNS, 空格分隔 (默认用本机的)    BLOCK_LAN=1 屏蔽本机和内网 (默认不屏蔽)    BBR=0 不开 BBR
#   LOGDUMP 长连接每传多少字节先记一条日志 (默认 1048576 即 1MB; 设成 0 只在连接结束时记一条)
# 管理用户:  docker exec 3proxy user {show|add USER PASSWORD|del USER}
#

# 随机串: 大小写字母 + 数字, 三类都至少有一个 (不用符号, 免得 socks5h:// 链接和 shell 里要转义)
rand_str(){
    local s
    while :; do
        s=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$1")
        [[ $s =~ [a-z] && $s =~ [A-Z] && $s =~ [0-9] ]] && break
    done
    echo "$s"
}

PORT="${PORT:-2020}"
PROXY_USER="${PROXY_USER:-$(rand_str 16)}"
PROXY_PASS="${PROXY_PASS:-$(rand_str 8)}"
CONF_DIR="/etc/3proxy"

if [ "$1" = "cn" ]; then
    IMAGE="registry.cn-shenzhen.aliyuncs.com/starsl/3proxy:1.0.2"
    DOCKER_MIRROR="--mirror Aliyun"
else
    IMAGE="starsliao/3proxy:1.0.2"
    DOCKER_MIRROR=""
fi

if [ "$(id -u)" != "0" ]; then
    echo "Error: 请用 root 运行"
    exit 1
fi

# 账号密码只能用 URL 里不用转义的字符 (和容器里 user 脚本的规则一样)
for s in "$PROXY_USER" "$PROXY_PASS"; do
    case "$s" in
        *[!A-Za-z0-9._~-]*) echo "Error: 账号和密码只能用字母、数字和 . _ ~ -"; exit 1;;
    esac
done
case "$LOGDUMP" in
    *[!0-9]*) echo "Error: LOGDUMP 只能是数字 (字节数), 0 表示关闭"; exit 1;;
esac

if ! command -v curl >/dev/null 2>&1; then
    (apt-get update && apt-get install -y curl) || yum install -y curl
fi

# 1. 安装并启动 docker
if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh -s -- $DOCKER_MIRROR || exit 1
fi
systemctl enable --now docker >/dev/null 2>&1 || service docker start

# 2. 开启 BBR (内核 4.9+): 高延迟、有丢包的链路 (比如跨境) 上吞吐提升明显; 已经开了或内核不支持就跳过
if [ "$BBR" != "0" ] && [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" != "bbr" ]; then
    modprobe tcp_bbr 2>/dev/null
    if grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        printf 'net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' > /etc/sysctl.d/99-bbr.conf
        sysctl -p /etc/sysctl.d/99-bbr.conf >/dev/null && echo "已开启 BBR"
    else
        echo "内核不支持 BBR, 跳过"
    fi
fi

# 3. 拉镜像
if ! docker pull "$IMAGE"; then
    [ "$1" = "cn" ] || echo "拉取失败; 国内服务器请用: bash install_docker.sh cn"
    exit 1
fi

# 4. 删掉旧容器, 再确认端口空着
docker rm -f 3proxy >/dev/null 2>&1
if command -v ss >/dev/null 2>&1 && [ -n "$(ss -Hltn "sport = :$PORT")" ]; then
    echo "Error: 端口 $PORT 已被占用:"
    ss -Hltnp "sport = :$PORT"
    echo "换个端口, 例如: PORT=1080 bash install_docker.sh${1:+ $1}"
    exit 1
fi

# 5. 账号文件: 一行一个 USER:CL:PASSWORD, 只有 root 能读; 每次安装都重写, 只留这次的账号
mkdir -p "$CONF_DIR"
(umask 077; echo "${PROXY_USER}:CL:${PROXY_PASS}" > "$CONF_DIR/passwd")

# 6. 启动容器: host 网络 (UDP 转发要用); 3proxy 每个连接要占 2 个以上文件描述符, 放宽 nofile;
#    去掉所有特权, 只留绑定 1024 以下端口的权限; 日志用宿主机时区, 限制大小
LOCALTIME=""
[ -f /etc/localtime ] && LOCALTIME="-v /etc/localtime:/etc/localtime:ro"
docker run -d \
    --name 3proxy \
    --restart always \
    --network host \
    --ulimit nofile=65535:65535 \
    --cap-drop ALL --cap-add NET_BIND_SERVICE \
    -e PORT="$PORT" -e MAXCONN="$MAXCONN" -e DNS="$DNS" -e BLOCK_LAN="$BLOCK_LAN" -e LOGDUMP="$LOGDUMP" \
    -v "$CONF_DIR:/etc/3proxy" $LOCALTIME \
    --log-opt max-size=10m --log-opt max-file=3 \
    "$IMAGE" || exit 1

# 7. 验证: 和下面打印的测试地址同一种写法 (socks5h, 域名由代理端解析), 走代理访问 cip.cc 查出口 IP
#    cip.cc 国内外都能访问; 返回多行, 取第一个 IPv4
sleep 2
IP=$(curl -sf --max-time 10 -x "socks5h://${PROXY_USER}:${PROXY_PASS}@127.0.0.1:${PORT}" cip.cc | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
if [ -n "$IP" ]; then
    echo "安装成功"
    echo "使用地址: socks5h://${PROXY_USER}:${PROXY_PASS}@${IP}:${PORT}"
    echo "测试地址: curl -x socks5h://${PROXY_USER}:${PROXY_PASS}@${IP}:${PORT} cip.cc"
    echo "管理用户: docker exec 3proxy user {show|add USER PASSWORD|del USER}"
    echo "云服务器记得在安全组放行 TCP ${PORT}"
else
    echo "验证失败, 查看日志: docker logs 3proxy"
    exit 1
fi
