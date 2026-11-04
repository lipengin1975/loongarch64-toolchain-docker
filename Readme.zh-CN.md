> [English Version](Readme.md)

# GCC 12.5.0 + Binutils 2.43.1 龙芯 LoongArch64 容器构建镜像
> Dockerfile：基于 LoongNix 20，在龙芯原生环境编译 GCC 12.5.0 & Binutils 2.43.1，生成 loongarch64-linux-gnu 原生工具链（LP64D ABI）

[![LoongArch](https://img.shields.io/badge/Arch-LoongArch64-blue)](https://loongarch.dev/)
[![Base Image](https://img.shields.io/badge/Base-loongnix:20-green)](https://cr.loongnix.cn/loongson/loongnix)
[![GCC](https://img.shields.io/badge/GCC-12.5.0-orange)](https://gcc.gnu.org/)
[![Binutils](https://img.shields.io/badge/Binutils-2.43.1-red)](https://sourceware.org/binutils/)

## 📖 项目简介
本仓库提供一套可复现的 Dockerfile，用于在 **LoongArch64（龙芯）** 平台上，基于 LoongNix 20 源码编译：
- GNU Binutils 2.43.1（as / ld / objdump 等）
- GCC 12.5.0（C / C++ 编译器，LP64D ABI）

✅ 特点：
- 原生 `loongarch64-linux-gnu` 工具链，**不是交叉编译**，宿主机本身就是龙芯
- 单独编译新版 binutils，GCC 编译时强制绑定使用这套新版 as/ld，规避系统自带 binutils 版本过低问题
- 修复 LoongArch LP64D 动态链接器软链接问题
- 替换上游 `config.sub` / `config.guess`，保证龙芯架构识别正常
- 关闭 `-mabi=lp64` 旧选项，强制使用标准 LP64D
- 容器输出成品工具链路径：`/opt/gcc-12.5.0` 和 `/opt/binutils`

> ⚠️ 重要说明：**该镜像只能在 LoongArch64 机器上构建**（龙芯 3A5000/3A6000 等），x86_64 环境无法直接 build。

## 📦 前置准备
1. 一台 LoongArch64 主机，安装 LoongNix 20 / Debian LoongArch
2. Docker / containerd 环境正常
3. 提前下载源码包放到 Dockerfile 同目录：
```bash
# binutils
wget https://sourceware.org/pub/binutils/releases/binutils-2.43.1.tar.xz
# gcc
wget https://ftp.gnu.org/gnu/gcc/gcc-12.5.0/gcc-12.5.0.tar.xz
```

目录结构:

```plaintext
.
├── Dockerfile
├── binutils-2.43.1.tar.xz
├── gcc-12.5.0.tar.xz
└── README.md
```

## 🚀 构建镜像

```bash
docker build -t loongarch64-gcc:12.5.0-binutils-2.43.1 .
```

## ▶️ 运行容器

```bash
docker run -it --rm loongarch64-gcc:12.5.0-binutils-2.43.1
```

容器内验证

```bash
# 查看版本
gcc --version
g++ --version
as --version
ld --version

# 查看目标架构
gcc -dumpmachine

# 编译测试
echo 'int main(){return 0;}' | gcc -x c - -o test && ./test && rm test

```

## 📂 工具链安装路径

- Binutils：`/opt/binutils`
- GCC 12.5.0：`/opt/gcc-12.5.0`
- 动态库配置：自动写入 `/etc/ld.so.conf.d/gcc-12.5.0.conf` 并执行 `ldconfig`
- 默认 PATH 已经预置新版工具链优先

##  关键构建细节说明（对应 Dockerfile）

1. 先编译独立新版 binutils，后续 GCC configure、编译阶段强制使用这套 as/ld，不使用系统 ld
2. 更新 `config.sub` / `config.guess`，解决老版本脚本识别 loongarch64 失败问题
3. 包装 `gcc-upstream / gxx-upstream`，拦截非法 `-mabi=lp64` 参数，仅允许 LP64D
4. 软链接动态解释器：`/lib64/ld-linux-loongarch-lp64d.so.1`，解决部分程序加载问题
5. 手动 patch `collect-ld`，防止 GCC 内部硬编码指向 `/usr/bin/ld`
6. GCC 配置参数：`--enable-languages=c,c++ --disable-multilib --disable-bootstrap`
7. 编译顺序：`all-gcc` → patch collect-ld → 完整 make && install

## 📌 使用场景

- 龙芯 LoongNix 环境开发，需要高于系统源版本的 GCC
- 嵌入式 LoongArch 程序编译、Qt / C++ 项目、边缘网关、工业物联网程序编译
- 统一 CI 构建环境，保证团队编译环境一致
- 打包独立工具链，拷贝出来给其他龙芯机器使用

## ❗ 已知注意事项

1. **仅支持 LoongArch64 宿主机构建**，x86 下 qemu 模拟构建极慢且容易异常
2. 源码包需要手动下载，没有内置 wget 在线拉取（方便内网离线构建）
3. 只开启 C / C++，如需 Fortran / Go / Ada 需要修改 `--enable-languages`
4. `--disable-bootstrap`：不做 GCC 自举编译，加快构建；生产严格验证场景可以删掉该参数
5. ABI：固定 LP64D，不兼容 LP64S
6. **本编译器产出 ELF 文件的动态加载器写死为 `/lib64/ld-linux-loongarch-lp64d.so.1`**。
在目标运行环境如果不存在该文件，程序会提示找不到解释器，需要在目标系统执行一次软链接：

```bash
ln -s /lib64/ld.so.1 /lib64/ld-linux-loongarch-lp64d.so.1
```

## 📄 License

- Dockerfile 脚本：MIT
- GCC / Binutils：遵循各自 GNU GPL / LGPL 许可证

## 🤝 贡献

欢迎提交 Issue 和 PR：

- 增加离线缓存优化
- 增加多阶段构建（减小最终镜像体积）
- 增加交叉编译版本（x86_64 -> loongarch64）
- 增加 OpenMP、libstdc++ 额外测试用例
