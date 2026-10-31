# 3proxy SOCKS5

[socks5-docker](../README.md) 里的 3proxy 版，性能最好、最省资源。另有 [Dante 版](../danted/)。

3proxy SOCKS5 代理的一键 Docker 安装脚本，镜像自己打包：

- 3proxy 1.0.2（官方最新版，2026-10-24 发布）
- glibc 静态编译，运行层用 busybox，镜像 4.4MB，只有 amd64
- 配置按性能调过，具体见[做了哪些优化](#做了哪些优化)
- 容器用 host 网络运行，TCP 和 UDP 转发都支持

## 性能

同一台 3 核机器上实测（客户端、后端和代理在同一台机器上）：

| | 本镜像 | 3proxy 官方镜像 | gost 3.3.2 | dante 1.4.4 |
| --- | --- | --- | --- | --- |
| 单连接吞吐 | **1903 MB/s** | 953 MB/s | 781 MB/s | 674 MB/s |
| 每 GB 流量耗 CPU | **0.54 s** | 1.07 s | 1.51 s | 1.52 s |
| 每秒新建连接（含认证，100 并发） | **2844 次** | 2619 次 | 1780 次 | 461 次 |
| 每千次新连接耗 CPU | **450 ms** | 473 ms | 755 ms | 4717 ms |
| 空闲内存 | **0.7 MB** | 2.6 MB | 21~37 MB | 9.5 MB |
| 镜像大小 | **4.4 MB** | 14.1 MB | 86.7 MB | 16 MB |

- 本镜像和官方镜像是同一轮测试的结果；gost、dante 来自另一轮，测试机器和方法相同，官方镜像在两轮里的结果相差 10% 以内。
- 本镜像单连接跑到 1903 MB/s，已经达到客户端 curl 的上限（直连后端是 1819 MB/s）。
- 500 个并发连接时，本镜像的进程内存（PSS）是 32MB，官方镜像是 43MB。算上内核里的 TCP 缓冲区，两者的总内存基本一样（都在 124MB 左右），因为大头是 TCP 缓冲区。
- dante 新建连接慢，有一部分是测试用的镜像造成的：它用 sha512-crypt 保存密码，每次认证都要算一遍这种故意做慢的哈希。

## 一键安装

用 root 运行：

```bash
# 国外服务器：镜像从 Docker Hub 拉
curl -fsSLO https://raw.githubusercontent.com/starsliao/socks5-docker/main/3proxy/install_docker.sh && bash install_docker.sh

# 国内服务器：镜像从阿里云拉，Docker 也用阿里云源安装
# （raw.githubusercontent.com 在国内时通时不通，这里用 jsDelivr 下载）
curl -fsSLO https://cdn.jsdelivr.net/gh/starsliao/socks5-docker@main/3proxy/install_docker.sh && bash install_docker.sh cn
```

已经下载过脚本的话，直接运行 `bash install_docker.sh`（国内加 `cn`）。

脚本依次执行：安装 Docker（没装的话）→ 开启 BBR → 拉镜像 → 检查端口是否空闲 → 随机生成账号 → 启动容器并设为开机自启 → 走代理访问 cip.cc 自检。成功后输出：

```
安装成功
使用地址: socks5h://<账号>:<密码>@<出口IP>:2020
测试地址: curl -x socks5h://<账号>:<密码>@<出口IP>:2020 cip.cc
管理用户: docker exec 3proxy user {show|add USER PASSWORD|del USER}
云服务器记得在安全组放行 TCP 2020
```

端口被占用时（比如已经装了 danted），脚本会显示占用端口的进程，然后退出。

### 可选参数

用环境变量传：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PORT` | `2020` | 监听端口 |
| `PROXY_USER` | 随机 16 位 | 账号 |
| `PROXY_PASS` | 随机 8 位 | 密码 |
| `MAXCONN` | `10000` | 最大并发连接数 |
| `DNS` | 本机 `/etc/resolv.conf` 里的 | 代理解析域名用的 DNS，多个用空格分隔 |
| `BLOCK_LAN` | 不屏蔽 | 设成 `1` 则屏蔽本机和内网，不许经代理访问 |
| `BBR` | 开启 | 设成 `0` 则不改内核的 TCP 拥塞控制 |

```bash
PORT=1080 PROXY_USER=myuser PROXY_PASS=MyPass123 bash install_docker.sh

# 公网上给别人用、不想让人经代理访问本机和内网时，打开屏蔽
BLOCK_LAN=1 bash install_docker.sh
```

账号和密码只能由字母、数字和 `. _ ~ -` 组成，这些字符在 `socks5h://` 链接和命令行里都不用转义。随机生成的账号由大小写字母和数字组成，三类都至少出现一次。

**每次运行都会重置账号**：账号文件会被重写，只保留这次的账号。如果只想加账号或改密码，用下面的 `user` 命令。

## 管理账号

```bash
docker exec 3proxy user show                 # 查看账号
docker exec 3proxy user add USER PASSWORD    # 添加账号 / 修改密码
docker exec 3proxy user del USER             # 删除账号
```

- 账号保存在宿主机的 `/etc/3proxy/passwd`，只有 root 能读，一行一个 `USER:CL:PASSWORD`。
- 增删账号会让 3proxy 立即重新加载配置。已建立的连接不受影响，但被删账号的连接会被断开。重新加载的那一瞬间，极少数新连接可能会失败。
- 也可以直接改这个文件，1 分钟内自动生效。
- **文件不能为空**：没有账号时 3proxy 加载配置会失败，所以 `user del` 不允许删掉最后一个账号。
- 密码用明文保存：SOCKS5 协议本身就是明文传账号密码，存哈希的意义不大，而明文认证不会额外消耗 CPU。

## 做了哪些优化

容器启动时，按环境变量生成下面这份配置（以默认参数为例，`nserver` 取自 `/etc/resolv.conf`；`deny` 那一行只有 `BLOCK_LAN=1` 时才有）：

```
nserver <本机 DNS>
nscache 65536
maxconn 10000
log
logformat "L%Y-%m-%d %H:%M:%S %E %U %C:%c %n:%q %R %I/%O %Dms"
monitor /etc/3proxy/passwd
users $/etc/3proxy/passwd
auth strong
deny * * <本机网卡地址>,0.0.0.0/8,10.0.0.0/8,100.64.0.0/10,127.0.0.0/8,169.254.0.0/16,172.16.0.0/12,192.168.0.0/16
allow *
socks -p2020 -s
```

- **`maxconn 10000`**：3proxy 默认最多只允许 100 个并发连接，超出的新连接会被直接丢掉，不给客户端任何提示。
- **`-s`（splice 零拷贝）**：大流量时，数据在内核里直接从一个 socket 转到另一个 socket，不经过用户态。实测单连接吞吐翻倍，每 GB 的 CPU 减半。小请求仍走普通缓冲，不会变慢。
- **内置 DNS 解析加缓存**（`nserver` + `nscache`）：按 DNS 记录的 TTL 缓存，同一个域名不用每次都去查询。
- **glibc 静态编译**：3proxy 每个连接用一个线程。用同样的源码和参数编译，musl 版每次新建连接要多花 24% 的 CPU。
- **可选屏蔽本机和内网**（`BLOCK_LAN=1`，默认不屏蔽）：打开后，不能经代理访问宿主机上只对内开放的服务、云主机元数据（169.254.169.254）和内网机器。本机网卡上的地址（包括公网 IP）也在屏蔽范围内。域名请求是先解析、再按 IP 匹配规则，所以没法用 `localhost` 之类的域名绕过。UDP 转发同样受这些规则限制。
- **容器参数**：
  - `--ulimit nofile=65535:65535`：每个连接要占 2 个以上文件描述符，Docker 默认的上限不够用。
  - `--cap-drop ALL --cap-add NET_BIND_SERVICE`：去掉所有特权，只保留绑定 1024 以下端口的权限。
  - 日志使用宿主机时区，单个日志文件最大 10MB，最多保留 3 个。
- **BBR**：在高延迟、有丢包的链路（比如跨境）上，吞吐提升明显。已经开启或内核不支持时会跳过，写在 `/etc/sysctl.d/99-bbr.conf`。

日志每行依次是：时间、错误码（0 表示正常）、账号、客户端地址、请求的目标、实际连接的 IP、收/发字节数、耗时：

```
2026-10-31 03:26:52 00000 u2 127.0.0.1:56788 cip.cc:80 101.132.81.133 499/70 831ms
```

## 镜像

| 用途 | 地址 |
| --- | --- |
| 国外 | `starsliao/3proxy:1.0.2` |
| 国内 | `registry.cn-shenzhen.aliyuncs.com/starsl/3proxy:1.0.2` |

不用脚本、手动运行：

```bash
mkdir -p /etc/3proxy && (umask 077; echo 'USER:CL:PASSWORD' > /etc/3proxy/passwd)
docker run -d --name 3proxy --restart always --network host \
    --ulimit nofile=65535:65535 --cap-drop ALL --cap-add NET_BIND_SERVICE \
    -e PORT=2020 -v /etc/3proxy:/etc/3proxy \
    starsliao/3proxy:1.0.2
```

要完全自己写配置，可以把配置文件放进 `/etc/3proxy`，在 `docker run` 末尾加上 `3proxy /etc/3proxy/你的配置.cfg`。注意静态编译的 3proxy 不能用系统解析器，配置里必须写 `nserver`。

## 自己构建

在仓库根目录执行：

```bash
docker build --provenance=false -t 3proxy:1.0.2 3proxy/image/
```

`3proxy/image/` 目录里：

- `Dockerfile`：多阶段构建。在 Debian 里用官方 Makefile 的 STATIC 模式编译 3proxy（不带插件和内置 HTTP 服务），源码包会校验 sha256，最后复制到 busybox 里。
- `entrypoint.sh`：启动时按环境变量生成配置，然后启动 3proxy。
- `user`：账号管理脚本。

## 注意事项

- 云服务器要在安全组里放行 TCP 端口。UDP 转发的中继端口是随机高端口，要用 UDP 转发还得放行 UDP。
- SOCKS5 是明文协议。从国内直连海外的 SOCKS5 去访问被墙的网站，会被识别出来并封掉端口。
