#!/bin/bash
#
# Dante Socks5 一键 Docker 安装  https://github.com/starsliao/socks5-docker
# 步骤照 https://github.com/Lozy/danted README 的 "Install by Docker",
# 镜像换成自己打的 sockd:1.4.4 (Dante 1.4.4 + Alpine 3.24, 只有 amd64; 构建见 image/)
#
# 用法 (root):
#   bash install_docker.sh        国外服务器: 镜像从 Docker Hub 拉
#   bash install_docker.sh cn     国内服务器: 镜像从阿里云拉, docker 也走阿里云源装
# 账号默认随机生成 (账号 16 位, 密码 8 位), 装完会打印; 每次运行都会重置账号
# 指定端口/账号:  PORT=1080 SOCKD_USER=xxx SOCKD_PASS=xxx bash install_docker.sh [cn]
# 管理用户:       docker exec sockd script/pam {show|add USER PASSWORD|del USER}
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
SOCKD_USER="${SOCKD_USER:-$(rand_str 16)}"
SOCKD_PASS="${SOCKD_PASS:-$(rand_str 8)}"
PASSWD_FILE="/etc/sockd/sockd.passwd"

if [ "$1" = "cn" ]; then
    IMAGE="registry.cn-shenzhen.aliyuncs.com/starsl/sockd:1.4.4"
    DOCKER_MIRROR="--mirror Aliyun"
else
    IMAGE="starsliao/sockd:1.4.4"
    DOCKER_MIRROR=""
fi

if [ "$(id -u)" != "0" ]; then
    echo "Error: 请用 root 运行"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    (apt-get update && apt-get install -y curl) || yum install -y curl
fi

# 1. 安装并启动 docker
if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh -s -- $DOCKER_MIRROR || exit 1
fi
systemctl enable --now docker >/dev/null 2>&1 || service docker start

# 2. 拉镜像
if ! docker pull "$IMAGE"; then
    [ "$1" = "cn" ] || echo "拉取失败; 国内服务器请用: bash install_docker.sh cn"
    exit 1
fi

# 3. 密码文件要先建好, 否则 docker 会在宿主机上建出一个同名目录
#    (上游 README 里的 sockd.passwd 是相对名, docker 会当成命名卷, 这里改成绝对路径);
#    每次安装都清空, 只留下面这次的账号
mkdir -p "$(dirname "$PASSWD_FILE")"
: > "$PASSWD_FILE"

# 4. 启动容器: 上游 README 的 docker run, 改成 host 网络 (UDP 转发要用), 加上开机自启和日志大小限制
docker rm -f sockd >/dev/null 2>&1
docker run -d \
    --name sockd \
    --restart always \
    --network host \
    --env PORT="$PORT" \
    --volume "${PASSWD_FILE}:/home/danted/conf/sockd.passwd" \
    --log-opt max-size=10m --log-opt max-file=3 \
    "$IMAGE" || exit 1

# 5. 添加账号
docker exec sockd script/pam add "$SOCKD_USER" "$SOCKD_PASS" || exit 1
docker exec sockd script/pam show

# 6. 验证: 和下面打印的测试地址同一种写法 (socks5h, 域名由代理端解析), 走代理访问 cip.cc 查出口 IP
#    cip.cc 国内外都能访问; 返回多行, 取第一个 IPv4
sleep 2
IP=$(curl -sf --max-time 10 -x "socks5h://${SOCKD_USER}:${SOCKD_PASS}@127.0.0.1:${PORT}" cip.cc | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
if [ -n "$IP" ]; then
    echo "安装成功"
    echo "使用地址: socks5h://${SOCKD_USER}:${SOCKD_PASS}@${IP}:${PORT}"
    echo "测试地址: curl -x socks5h://${SOCKD_USER}:${SOCKD_PASS}@${IP}:${PORT} cip.cc"
    echo "管理用户: docker exec sockd script/pam {show|add USER PASSWORD|del USER}"
    echo "云服务器记得在安全组放行 TCP ${PORT}"
else
    echo "验证失败, 查看日志: docker logs sockd"
    exit 1
fi
