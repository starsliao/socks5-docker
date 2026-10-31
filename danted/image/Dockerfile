# sockd: Dante 1.4.4 (官方最新) + Alpine 3.24, 认证方式同上游 lozyme/sockd (PAM pwdfile)
# 运行用 host 网络 (UDP 转发要用), 端口用 -e PORT 指定
# 构建: docker build --provenance=false -t sockd:1.4.4 .

FROM alpine:3.24 AS build

ARG DANTE_VER=1.4.4
ARG DANTE_SHA256=1973c7732f1f9f0a4c0ccf2c1ce462c7c25060b25643ea90f9b98f53a813faec
ARG PWDFILE_VER=1.0
ARG PWDFILE_SHA256=5b8db1397cff9cadfd1bb96f53c134b787ab0e6a0fbedb71040541d340313ba2

RUN apk add --no-cache build-base linux-pam-dev bison flex
WORKDIR /src

# dante: Alpine 官方包没编 PAM, 所以自己编, 只编服务端;
# 两处 sed 等同 Alpine 官方 dante 包的 musl 补丁 (ifdev.patch / gaierrval.patch)
RUN wget -q -O dante.tar.gz https://www.inet.no/dante/files/dante-${DANTE_VER}.tar.gz \
 && echo "${DANTE_SHA256}  dante.tar.gz" | sha256sum -c - \
 && tar xzf dante.tar.gz && cd dante-${DANTE_VER} \
 && sed -i -E '/^#if .*HAVE_(SEND|RECV)BUF_IOCTL/ s/(HAVE_(SEND|RECV)BUF_IOCTL)/defined(\1)/g' sockd/sockd_io.c \
 && sed -i 's/^gaierrval: \(EAI_[A-Z_]*\)$/"gaierrval: \1"/' configure \
 && CFLAGS="-O2 -std=gnu17 -Wno-implicit-function-declaration -D_GNU_SOURCE" ac_cv_func_sched_setscheduler=no \
    ./configure --prefix=/usr --disable-client --without-libwrap --without-upnp \
                --without-gssapi --without-ldap --without-bsdauth \
 && grep -q 'define HAVE_COND_PAM 1' include/autoconf.h \
 && make -j"$(nproc)" && make install && strip /usr/sbin/sockd

# pam_pwdfile: 上游用的 PAM 密码文件模块; Alpine 3.24 的 PAM 只从 /usr/lib/security 加载模块
RUN wget -q -O pwdfile.tar.gz https://github.com/tiwe-de/libpam-pwdfile/archive/refs/tags/v${PWDFILE_VER}.tar.gz \
 && echo "${PWDFILE_SHA256}  pwdfile.tar.gz" | sha256sum -c - \
 && tar xzf pwdfile.tar.gz \
 && CFLAGS="-O2 -std=gnu17" make -C libpam-pwdfile-${PWDFILE_VER} PAM_LIB_DIR=/usr/lib/security install


FROM alpine:3.24

RUN apk add --no-cache linux-pam
COPY --from=build /usr/sbin/sockd /usr/sbin/sockd
COPY --from=build /usr/lib/security/pam_pwdfile.so /usr/lib/security/pam_pwdfile.so
COPY sockd.conf /home/danted/conf/sockd.conf
COPY pam entrypoint.sh /home/danted/script/
RUN chmod +x /home/danted/script/pam /home/danted/script/entrypoint.sh \
 && touch /home/danted/conf/sockd.passwd \
 && mkdir -p /etc/pam.d \
 && printf 'auth required pam_pwdfile.so pwdfile=/home/danted/conf/sockd.passwd\naccount required pam_permit.so\n' > /etc/pam.d/sockd \
 && mkpasswd -m sha512 test >/dev/null

WORKDIR /home/danted
EXPOSE 2020
CMD ["script/entrypoint.sh"]
