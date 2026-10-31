#!/bin/sh
# 启动时按环境变量生成 3proxy 配置, 写到 /run/3proxy.cfg 再启动 (容器跑 host 网络)
#   PORT       监听端口, 默认 2020
#   MAXCONN    最大并发连接数, 默认 10000 (3proxy 自己默认只有 100, 超出的新连接会被直接丢掉)
#   DNS        DNS 服务器, 空格分隔; 默认用宿主机 /etc/resolv.conf 里的
#   BLOCK_LAN  设成 1 时屏蔽本机和内网 (不许经代理访问); 默认不屏蔽
#   LOGDUMP    长连接每传多少字节先记一条日志, 默认 1048576 (1MB); 设成 0 关闭, 只在连接结束时记一条
# 账号在 /etc/3proxy/passwd (宿主机同名目录挂载进来), 用 user 脚本管理
PORT="${PORT:-2020}"
MAXCONN="${MAXCONN:-10000}"
LOGDUMP="${LOGDUMP:-1048576}"
PASSWD="/etc/3proxy/passwd"

# 静态编译的 3proxy 没有系统解析器, 用内置解析器 + 缓存 (按 DNS 的 TTL 缓存), 必须给 nserver
NSERVERS=$(for ip in ${DNS:-$(awk '$1 == "nameserver" {print $2}' /etc/resolv.conf)}; do
    case "$ip" in *.*.*.*) echo "nserver $ip";; esac
done)
[ -n "$NSERVERS" ] || NSERVERS="nserver 8.8.8.8"

# BLOCK_LAN=1 时不许经代理访问本机和内网: 宿主机上只对内开放的服务、云主机元数据 (169.254.169.254) 等;
# 本机网卡上的地址 (包括公网 IP) 也算. 域名请求是先解析再查规则, 绕不过去
DENY=""
if [ "$BLOCK_LAN" = "1" ]; then
    LOCAL=$(ip -4 -o addr show | awk '{sub(/\/.*/, "", $4); printf "%s,", $4}')
    DENY="deny * * ${LOCAL}0.0.0.0/8,10.0.0.0/8,100.64.0.0/10,127.0.0.0/8,169.254.0.0/16,172.16.0.0/12,192.168.0.0/16"
fi

# 3proxy 默认只在连接结束时记一条日志, 而连接池 (比如 new-api) 会让一条连接几小时不断, 期间一直没有日志,
# 3proxy 停止时还开着的连接也不会补记. logdump: 每传 LOGDUMP 字节先记一条 (字节数和耗时是距上一条的增量)
case "$LOGDUMP" in
    *[!0-9]*) echo "错误: LOGDUMP 只能是数字 (字节数), 0 表示关闭" >&2; exit 1;;
    0) LOGDUMP_LINE="";;
    *) LOGDUMP_LINE="logdump $LOGDUMP $LOGDUMP";;
esac

# 账号文件为空时 3proxy 解析配置会失败, 直接报错退出 (宿主机上往 /etc/3proxy/passwd 写一行 USER:CL:PASSWORD 即可)
if ! grep -q : "$PASSWD" 2>/dev/null; then
    echo "错误: $PASSWD 里没有账号, 格式是一行一个 USER:CL:PASSWORD" >&2
    exit 1
fi

# maxconn: 见上; -s: Linux splice 零拷贝, 只在大流量时启用, 小请求照常走用户态缓冲
# monitor: 账号文件变了 1 分钟内自动重新加载 (user 脚本改完会立即通知重载)
# 日志: 时间 错误码(0 为正常) 账号 客户端 请求的目标 实际连的 IP 收/发字节 耗时(毫秒)
cat > /run/3proxy.cfg <<EOF
$NSERVERS
nscache 65536
maxconn $MAXCONN
log
$LOGDUMP_LINE
logformat "L%Y-%m-%d %H:%M:%S %E %U %C:%c %n:%q %R %I/%O %Dms"
monitor $PASSWD
users \$$PASSWD
auth strong
$DENY
allow *
socks -p$PORT -s
EOF

exec 3proxy /run/3proxy.cfg
