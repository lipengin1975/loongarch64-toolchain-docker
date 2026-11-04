FROM cr.loongnix.cn/loongson/loongnix:20

ARG GCC_VERSION=12.5.0
ARG BINUTILS_VERSION=2.43.1

ENV DEBIAN_FRONTEND=noninteractive
ENV PREFIX=/opt/gcc-12.5.0
ENV SRC_DIR=/usr/local/src
ENV BINUTILS_PREFIX=/opt/binutils
ENV PATH=/opt/gcc-12.5.0/bin:/opt/binutils/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ============================================================
# 1. 安装构建依赖
# ============================================================
RUN set -eux; \
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    rm -f /etc/apt/apt.conf.d/*post-invoke*; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        g++ \
        make \
        git \
        wget \
        ca-certificates \
        tar \
        gzip \
        bzip2 \
        xz-utils \
        patch \
        diffutils \
        flex \
        bison \
        gawk \
        perl \
        python3 \
        texinfo \
        zlib1g-dev \
        libgmp-dev \
        libmpfr-dev \
        libmpc-dev \
        libisl-dev \
        file; \
    rm -rf /var/lib/apt/lists/*

WORKDIR ${SRC_DIR}

# ============================================================
# 2. 编译 GNU Binutils for LoongArch
# ============================================================
COPY binutils-${BINUTILS_VERSION}.tar.xz /tmp/

RUN set -eux; \
    cd /tmp; \
    tar -xf binutils-${BINUTILS_VERSION}.tar.xz; \
    mkdir -p /tmp/binutils-build; \
    cd /tmp/binutils-build; \
    /tmp/binutils-${BINUTILS_VERSION}/configure \
        --build=loongarch64-linux-gnu \
        --host=loongarch64-linux-gnu \
        --target=loongarch64-linux-gnu \
        --prefix=${BINUTILS_PREFIX} \
        --disable-nls \
        --disable-werror \
        --disable-doc \
        --enable-shared \
        --enable-plugins \
        --with-system-zlib; \
    make -j$(nproc); \
    make install; \
    ${BINUTILS_PREFIX}/bin/as --version; \
    ${BINUTILS_PREFIX}/bin/ld --version; \
    cd /; \
    rm -rf /tmp/binutils-${BINUTILS_VERSION} \
           /tmp/binutils-${BINUTILS_VERSION}.tar.xz \
           /tmp/binutils-build

# ============================================================
# 3. 验证新版 Binutils
# ============================================================
RUN set -eux; \
    ${BINUTILS_PREFIX}/bin/as --version; \
    ${BINUTILS_PREFIX}/bin/ld --version; \
    printf '.text\n.globl test_symbol\ntest_symbol:\n  nop\n' \
        > /tmp/test.s; \
    ${BINUTILS_PREFIX}/bin/as -o /tmp/test.o /tmp/test.s; \
    file /tmp/test.o; \
    rm -f /tmp/test.s /tmp/test.o

WORKDIR ${SRC_DIR}

# ============================================================
# 4. 下载并解压 GCC 官方源码
# ============================================================
COPY gcc-${GCC_VERSION}.tar.xz ./

RUN set -eux; \
    tar -xf gcc-${GCC_VERSION}.tar.xz; \
    rm gcc-${GCC_VERSION}.tar.xz

# ============================================================
# 5. 下载 GCC 所需依赖
# ============================================================
RUN cd ${SRC_DIR}/gcc-${GCC_VERSION} \
    && ./contrib/download_prerequisites

# ============================================================
# 6. 更新 GNU config 辅助脚本
# ============================================================
RUN set -eux; \
    git clone --depth 1 \
        https://git.savannah.gnu.org/git/config.git \
        /tmp/gnu-config; \
    find ${SRC_DIR}/gcc-${GCC_VERSION} \
        -type f -name config.sub \
        -exec cp /tmp/gnu-config/config.sub {} \;; \
    find ${SRC_DIR}/gcc-${GCC_VERSION} \
        -type f -name config.guess \
        -exec cp /tmp/gnu-config/config.guess {} \;; \
    find ${SRC_DIR}/gcc-${GCC_VERSION} \
        -type f \( -name config.sub -o -name config.guess \) \
        -exec chmod +x {} \;; \
    rm -rf /tmp/gnu-config

# ============================================================
# 7. 验证 GMP 能识别 LoongArch
# ============================================================
RUN ${SRC_DIR}/gcc-${GCC_VERSION}/gmp/config.sub \
    loongarch64-linux-gnu

# ============================================================
# 8. 创建宿主编译器包装脚本
# ============================================================
RUN set -eux; \
    printf '%s\n' \
        '#!/bin/sh' \
        'for arg in "$@"; do' \
        '    if [ "$arg" = "-mabi=lp64" ]; then' \
        '        echo "error: vendor-only option -mabi=lp64 is not allowed" >&2' \
        '        exit 1' \
        '    fi' \
        'done' \
        'exec /usr/bin/gcc -B/usr/bin/ "$@"' \
        > /usr/local/bin/gcc-upstream; \
    chmod +x /usr/local/bin/gcc-upstream; \
    printf '%s\n' \
        '#!/bin/sh' \
        'for arg in "$@"; do' \
        '    if [ "$arg" = "-mabi=lp64" ]; then' \
        '        echo "error: vendor-only option -mabi=lp64 is not allowed" >&2' \
        '        exit 1' \
        '    fi' \
        'done' \
        'exec /usr/bin/g++ -B/usr/bin/ "$@"' \
        > /usr/local/bin/gxx-upstream; \
    chmod +x /usr/local/bin/gxx-upstream

# ============================================================
# 9. 确认基础工具链及目标平台
# ============================================================
RUN set -eux; \
    uname -m; \
    /usr/bin/gcc --version; \
    /usr/bin/gcc -dumpmachine; \
    ${SRC_DIR}/gcc-${GCC_VERSION}/gmp/config.sub \
        loongarch64-unknown-linux-gnu; \
    ${BINUTILS_PREFIX}/bin/as --version; \
    ${BINUTILS_PREFIX}/bin/ld --version

# ============================================================
# 10. 配置 GCC
#     关键修复：
#       --with-as 指定新版汇编器
#       --with-ld 指定新版链接器
#       LD 显式指定，避免 configure 记录系统旧版 ld
# ============================================================
RUN mkdir -p ${SRC_DIR}/gcc-build

WORKDIR ${SRC_DIR}/gcc-build

ENV CC=/usr/local/bin/gcc-upstream
ENV CXX=/usr/local/bin/gxx-upstream

RUN set -eux; \
    export PATH="${BINUTILS_PREFIX}/bin:/usr/bin:/bin:${PATH}"; \
    export AS="${BINUTILS_PREFIX}/bin/as"; \
    export LD="${BINUTILS_PREFIX}/bin/ld"; \
    ../gcc-${GCC_VERSION}/configure \
        --prefix=${PREFIX} \
        --build=loongarch64-linux-gnu \
        --host=loongarch64-linux-gnu \
        --target=loongarch64-linux-gnu \
        --with-arch=loongarch64 \
        --with-abi=lp64d \
        --with-as=${BINUTILS_PREFIX}/bin/as \
        --with-ld=${BINUTILS_PREFIX}/bin/ld \
        --enable-languages=c,c++ \
        --disable-multilib \
        --disable-bootstrap \
        --disable-nls \
        --enable-checking=release

# ============================================================
# 解决 LoongArch LP64D 动态装在器路径问题
# ============================================================
RUN set -eux; \
    if [ ! -e /lib64/ld-linux-loongarch-lp64d.so.1 ] && \
       [ ! -L /lib64/ld-linux-loongarch-lp64d.so.1 ]; then \
        ln -s /lib64/ld.so.1 /lib64/ld-linux-loongarch-lp64d.so.1; \
    fi; \
    test -x /lib64/ld-linux-loongarch-lp64d.so.1

# ============================================================
# 11. 编译 GCC，并确保使用新版 Binutils
# ============================================================
RUN set -eux; \
    make -j$(nproc) all-gcc; \
    if [ -f gcc/collect-ld ]; then \
        sed -i \
            's|ORIGINAL_LD_FOR_TARGET="/usr/bin/ld"|ORIGINAL_LD_FOR_TARGET="/opt/binutils/bin/ld"|g; \
             s|ORIGINAL_LD_BFD_FOR_TARGET="/usr/bin/ld.bfd"|ORIGINAL_LD_BFD_FOR_TARGET="/opt/binutils/bin/ld"|g; \
             s|ORIGINAL_PLUGIN_LD_FOR_TARGET="/usr/bin/ld"|ORIGINAL_PLUGIN_LD_FOR_TARGET="/opt/binutils/bin/ld"|g' \
            gcc/collect-ld; \
        grep -F 'ORIGINAL_PLUGIN_LD_FOR_TARGET="/opt/binutils/bin/ld"' gcc/collect-ld; \
    else \
        echo "ERROR: gcc/collect-ld was not generated by all-gcc" >&2; \
        exit 1; \
    fi

# ============================================================
# 12. 编译并安装剩余 GCC 组件
# ============================================================
RUN set -eux; \
    make -j$(nproc); \
    make install

# ============================================================
# 13. 配置 GCC 12.5.0 环境变量
# ============================================================
ENV GCC_PREFIX=/opt/gcc-12.5.0

ENV PATH="/opt/gcc-12.5.0/bin:/opt/binutils/bin:${PATH}"

# Register GCC shared libraries with the system dynamic linker
RUN set -eux; \
    test -x "${GCC_PREFIX}/bin/gcc"; \
    test -x "${GCC_PREFIX}/bin/g++"; \
    mkdir -p /etc/ld.so.conf.d; \
    if [ -d "${GCC_PREFIX}/lib" ]; then \
        echo "${GCC_PREFIX}/lib" > /etc/ld.so.conf.d/gcc-12.5.0.conf; \
    fi; \
    if [ -d "${GCC_PREFIX}/lib64" ]; then \
        echo "${GCC_PREFIX}/lib64" >> /etc/ld.so.conf.d/gcc-12.5.0.conf; \
    fi; \
    ldconfig; \
    gcc --version; \
    g++ --version

# ============================================================
# 14. 验证安装结果
# ============================================================
RUN set -eux; \
    ${PREFIX}/bin/gcc --version; \
    ${PREFIX}/bin/g++ --version; \
    ${PREFIX}/bin/gcc -dumpmachine; \
    printf 'int main(void) { return 0; }\n' \
        | ${PREFIX}/bin/gcc -x c - -o /tmp/gcc-test; \
    /tmp/gcc-test; \
    rm -f /tmp/gcc-test

WORKDIR /workspace

CMD ["/bin/bash"]

