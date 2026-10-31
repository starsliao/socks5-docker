# socks5-docker

SOCKS5 代理的一键 Docker 安装脚本。有两个版本，各放在一个目录里：

| 目录 | 版本 | 特点 |
| --- | --- | --- |
| [3proxy/](3proxy/) | 3proxy 1.0.2 | 推荐。吞吐最高，CPU 和内存占用最低；可选屏蔽本机和内网 |
| [danted/](danted/) | Dante 1.4.4 | 老牌 SOCKS5 服务；PAM 认证，密码用 sha512-crypt 保存 |

两个脚本的用法相同：

- 国外服务器从 Docker Hub 拉镜像；国内服务器加 `cn` 参数，从阿里云拉镜像
- 随机生成账号（账号 16 位、密码 8 位），每次运行都会重置账号
- 容器用 host 网络运行，TCP 和 UDP 转发都支持
- 装完自动走代理访问 cip.cc 自检，并打印 `socks5h://` 使用地址

## 一键安装

用 root 运行。

### 3proxy（推荐）

```bash
# 国外服务器
curl -fsSLO https://raw.githubusercontent.com/starsliao/socks5-docker/main/3proxy/install_docker.sh && bash install_docker.sh

# 国内服务器
curl -fsSLO https://cdn.jsdelivr.net/gh/starsliao/socks5-docker@main/3proxy/install_docker.sh && bash install_docker.sh cn
```

### Dante

```bash
# 国外服务器
curl -fsSLO https://raw.githubusercontent.com/starsliao/socks5-docker/main/danted/install_docker.sh && bash install_docker.sh

# 国内服务器
curl -fsSLO https://cdn.jsdelivr.net/gh/starsliao/socks5-docker@main/danted/install_docker.sh && bash install_docker.sh cn
```

国内服务器用 jsDelivr 下载脚本，因为 raw.githubusercontent.com 在国内时通时不通。

两个版本默认都用 2020 端口。同一台机器上两个都装的话，第二个要用 `PORT=端口号` 换一个端口。3proxy 的脚本发现端口被占用时，会提示并退出。

可选参数和账号管理见各目录里的 README。

## 两个版本对比

同一台 3 核机器上实测（客户端、后端和代理在同一台机器上）：

| | 3proxy | Dante |
| --- | --- | --- |
| 单连接吞吐 | 1903 MB/s | 674 MB/s |
| 每 GB 流量耗 CPU | 0.54 s | 1.52 s |
| 每秒新建连接（含认证，100 并发） | 2844 次 | 461 次 |
| 空闲内存 | 0.7 MB | 9.5 MB |
| 500 个并发连接时的进程内存 | 约 33 MB | 约 265 MB |
| 镜像大小 | 4.4 MB | 16 MB |
| 账号管理 | `docker exec 3proxy user ...` | `docker exec sockd script/pam ...` |
| 账号环境变量 | `PROXY_USER` / `PROXY_PASS` | `SOCKD_USER` / `SOCKD_PASS` |

- 两列数字来自同一台机器上的两轮测试，方法相同。
- Dante 新建连接慢，有一部分是因为它的镜像用 sha512-crypt 保存密码，每次认证都要算一遍这种故意做慢的哈希。它是多进程模型，连接一多，内存也涨得快。
