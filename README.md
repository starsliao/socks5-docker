# danted-docker

Dante SOCKS5 代理的一键 Docker 安装脚本。安装步骤参考 [Lozy/danted](https://github.com/Lozy/danted) README 里的 "Install by Docker"，镜像重新打包：

- Dante 1.4.4（官方最新版，修复了 CVE-2024-54662）
- 基于 Alpine 3.24，镜像压缩后约 4.5MB，只有 amd64
- 认证方式和上游一样：PAM + pam_pwdfile 密码文件，不建系统用户；密码用 sha512-crypt 保存
- 容器用 host 网络运行，TCP 和 UDP 转发都支持

## 一键安装

用 root 运行：

```bash
# 国外服务器：镜像从 Docker Hub 拉
curl -fsSLO https://raw.githubusercontent.com/starsliao/danted-docker/main/install_docker.sh && bash install_docker.sh

# 国内服务器：镜像从阿里云拉，Docker 也用阿里云源安装
# （raw.githubusercontent.com 在国内时通时不通，这里用 jsDelivr 下载）
curl -fsSLO https://cdn.jsdelivr.net/gh/starsliao/danted-docker@main/install_docker.sh && bash install_docker.sh cn
```

已经下载过脚本的话，直接运行 `bash install_docker.sh`（国内加 `cn`）。

脚本会依次：安装 Docker（没装的话）→ 拉镜像 → 用 host 网络启动容器并设为开机自启 → 随机生成账号 → 走代理访问 cip.cc 自检。成功后输出：

```
安装成功
使用地址: socks5h://<账号>:<密码>@<出口IP>:2020
测试地址: curl -x socks5h://<账号>:<密码>@<出口IP>:2020 cip.cc
管理用户: docker exec sockd script/pam {show|add USER PASSWORD|del USER}
云服务器记得在安全组放行 TCP 2020
```

### 可选参数

用环境变量传：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PORT` | `2020` | 监听端口 |
| `SOCKD_USER` | 随机 16 位 | 账号 |
| `SOCKD_PASS` | 随机 8 位 | 密码 |

```bash
PORT=1080 SOCKD_USER=myuser SOCKD_PASS='MyPass123' bash install_docker.sh
```

随机账号由大小写字母和数字组成，三类都至少出现一次。没有用符号，这样 `socks5h://` 链接和命令行里都不用转义。

**每次运行都会重置账号**：密码文件会被清空，只保留这次的账号。只想加账号或改密码，用下面的 `script/pam`。

## 管理账号

```bash
docker exec sockd script/pam show                 # 查看账号
docker exec sockd script/pam add USER PASSWORD    # 添加账号 / 修改密码
docker exec sockd script/pam del USER             # 删除账号
```

账号保存在宿主机的 `/etc/sockd/sockd.passwd`，增删立即生效，不用重启容器。

## 镜像

| 用途 | 地址 |
| --- | --- |
| 国外 | `starsliao/sockd:1.4.4` |
| 国内 | `registry.cn-shenzhen.aliyuncs.com/starsl/sockd:1.4.4` |

不用脚本、手动运行：

```bash
mkdir -p /etc/sockd && touch /etc/sockd/sockd.passwd
docker run -d --name sockd --restart always --network host -e PORT=2020 \
    -v /etc/sockd/sockd.passwd:/home/danted/conf/sockd.passwd \
    starsliao/sockd:1.4.4
docker exec sockd script/pam add USER PASSWORD
```

## 自己构建

```bash
docker build --provenance=false -t sockd:1.4.4 image/
```

`image/` 目录里：

- `Dockerfile`：多阶段构建，编译 dante 1.4.4（只编服务端，打上 Alpine 官方包用的 musl 兼容补丁）和 pam_pwdfile
- `sockd.conf`：沿用上游的配置
- `entrypoint.sh`：启动时按 `PORT` 和默认路由所在的网卡改写配置
- `pam`：账号管理脚本，用法和上游一样

## 注意事项

- 云服务器要在安全组里放行 TCP 端口。UDP 转发的中继端口是随机高端口，要用 UDP 转发还得放行 UDP。
- SOCKS5 是明文协议。从国内直连海外的 SOCKS5 去访问被墙的网站，会被识别出来并封掉端口。
- 镜像里的配置文件在 `/home/danted/conf/sockd.conf`，不是 Debian 包的 `/etc/danted.conf`。
