# pc-ssh-channel

在 Android（Termux / proot）里用一条 `pc` 命令操作 Windows 电脑：执行命令、开终端、拉文件、推文件、全盘搜索、取回截图。

手机和电脑常常不在同一网段，安卓又只能同时挂一个 VPN。这个工具把几条可能的路一起探，谁先通走谁，并把结果缓存下来；连接断了会自动换下一条路。

## 特性

- **多路由并行探测**：Tailscale 直连、公网 / 校园网 IPv6、tailscaled 用户态（unix socket）、SOCKS5 出口，四条路同时试
- **路由缓存**：记录上次成功的路由，网络指纹变化时自动失效
- **断线换路**：正式连接返回 255 时，换下一条已探通的路重连
- **tailscaled 自愈**：SOCKS 出口活着就直接用；daemon 死了才拉起并 `up`
- **文件通道**：`pc --scp` 拉文件，`pcpush` 推文件（绕开 Windows 命令行 8191 字符上限）
- **配套小工具**：Everything 搜索、截图缩放取回、手机浏览器下载

## 命令

| 命令 | 作用 |
| --- | --- |
| `pc "命令"` | 在电脑上执行一条命令 |
| `pc` | 开交互终端 |
| `pc --scp "F:\路径\文件" [本地路径]` | 把电脑上的文件拉到本机 |
| `pcget "F:\路径\文件"` | 拉文件并用手机浏览器打开下载 |
| `pcpush <本地文件> <Windows 路径>` | 把本地文件推到电脑 |
| `pces "关键词" [数量]` | 用电脑上 Everything 的 HTTP 接口搜文件 |
| `pcshot <远程图片> <本地.jpg> [宽度]` | 把电脑上的图片缩放后取回 |
| `tsnc` / `ts-socks` | SSH ProxyCommand，一般由 `pc` 自动调用 |

## 工作方式

```
┌────────────── Android ──────────────┐        ┌──────── Windows ────────┐
│ Termux / proot Ubuntu               │        │ OpenSSH Server          │
│                                     │        │                         │
│  pc ──┬── ssh  tailscale 100.x ─────┼───────▶│  PowerShell             │
│       ├── ssh  公网 IPv6 ───────────┼───────▶│                         │
│       ├── ssh + tsnc（unix socket）─┤        │                         │
│       └── ssh + ts-socks（SOCKS5）──┘        │                         │
└─────────────────────────────────────┘        └─────────────────────────┘
```

`pc` 启动后：

1. `detect_routes` 按本机网络情况列出可用路由
2. 每条路由起一个后台探针，执行 `ssh ... "exit 0"`
3. 第一条探通的路立即使用，其余探针取消
4. 成功的路由写入缓存（按本机地址指纹校验）
5. 正式命令返回 255（连接层失败）时，换下一条已探通的路重试

路由说明：

| 路由 | 条件 | 说明 |
| --- | --- | --- |
| `lan` | 电脑的局域网 IPv4 与本机同网段，或同属一个私有网段大类 | 局域网直连，延迟最低；地址可自动学习 |
| `app` | 本机有 `100.x` 地址 | 走 Android 上的 Tailscale App |
| `v6` | 本机有公网 IPv6，且配置了 `PC_V6_HOST` | 直连，不需要 VPN |
| `proot` | tailscaled 的 unix socket 存在 | 用户态 Tailscale，经 `tailscale nc` |
| `socks` | 有 `ts-socks` | 用户态 Tailscale，经 SOCKS5 出口 |

`lan` 按两级判断：同网段（真实掩码）无条件启用；跨子网但同属一个私有地址大类（`10/8`、`172.16/12`、`192.168/16`）时也试一次，适配校园网这类三层可达的场景。探测结果按网络指纹缓存到 `~/.local/state/pc/lan-try`，失败过的网络下次直接跳过，不会反复等 3 秒。

`lan` 会先单独探测，通了就不再拉起 tailscaled，也不会被并行探测的提前退出误杀。
电脑的局域网地址不需要手填——每次连上后会后台问一次并缓存到
`~/.local/state/pc/lan-host`，只在手机网络指纹变化后重新学习。
想固定的话在配置里写 `PC_LAN_HOST`，配置优先于自动学习。

## 快速开始

### 1. Windows 端

安装并启动 OpenSSH Server，把自己的公钥放进授权文件。完整命令见 [docs/windows-setup.md](docs/windows-setup.md)。

要点：

- 管理员账户的公钥放 `C:\ProgramData\ssh\administrators_authorized_keys`
- 普通账户放 `%USERPROFILE%\.ssh\authorized_keys`
- 防火墙只放行需要的来源地址

### 2. Android 端

Termux 里装基础依赖：

```sh
pkg install openssh python coreutils
```

想用 proot Ubuntu：

```sh
pkg install proot-distro
proot-distro install ubuntu
proot-distro login ubuntu
```

进入 proot 后补装：

```sh
apt update && apt install -y openssh-client python3
```

生成密钥（已有就跳过）：

```sh
ssh-keygen -t ed25519 -C "android-pc"
cat ~/.ssh/id_ed25519.pub
```

把公钥内容贴到 Windows 的授权文件里。

### 3. Tailscale（可选）

如果两台机器在同一个 tailnet，或者电脑有可直连的公网 IPv6，可以跳过。

Android 上装 Tailscale App 是最省事的做法，对应 `app` 路由。想在 proot 里用用户态 tailscaled，对应 `proot` / `socks` 路由：

```sh
mkdir -p ~/.local/tailscale
# 从 https://pkgs.tailscale.com/stable/#static 下载 arm64 包
tar -xzf tailscale_*_arm64.tgz --strip-components=1 -C ~/.local/tailscale
mkdir -p ~/.local/tailscale/run ~/.local/tailscale/state
```

`pc` 会在需要时自动拉起 tailscaled，也可以手动启动：

```sh
~/.local/tailscale/tailscaled \
  --tun=userspace-networking \
  --socks5-server=127.0.0.1:1066 \
  --outbound-http-proxy-listen=127.0.0.1:1066 \
  --socket=$HOME/.local/tailscale/run/tailscaled.sock \
  --state=$HOME/.local/tailscale/state/tailscaled.state &

~/.local/tailscale/tailscale \
  --socket=$HOME/.local/tailscale/run/tailscaled.sock \
  up --accept-dns=false --hostname=android-proot
```

### 4. 安装脚本

```sh
git clone https://github.com/Therenery/pc-ssh-channel.git
cd pc-ssh-channel
./install.sh
```

编辑配置：

```sh
$EDITOR ~/.config/pc/pc.conf
```

至少填 `PC_USER` 和 `PC_TS_IP` / `PC_V6_HOST` 中的一个。

### 5. 使用

```sh
pc "hostname"
pc "Get-ChildItem C:\"
pc
pc --scp "F:\docs\report.pdf"
pcget "F:\docs\report.pdf"
pces "预算表" 10
```

## 配置

配置在 `~/.config/pc/pc.conf`，格式是 shell 变量。可用 `PC_CONF` 指定其他路径。

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PC_USER` | 无 | 电脑登录用户名，必填 |
| `PC_TS_IP` | 空 | Tailscale 地址或 MagicDNS 名 |
| `PC_V6_HOST` | 空 | 电脑公网 IPv6 地址 |
| `PC_V6_PREFIX` | 空 | 本机 v6 前缀过滤，留空表示任意公网 v6 |
| `PC_PORT` | `22` | SSH 端口 |
| `PC_TS_HOSTNAME` | `android-proot` | 手机在 tailnet 里的节点名 |
| `PC_TS_BASE` | `~/.local/tailscale` | tailscale 二进制目录 |
| `PC_TS_SOCKS_HOST` | `127.0.0.1` | SOCKS5 监听地址 |
| `PC_TS_SOCKS_PORT` | `1066` | SOCKS5 监听端口 |
| `PC_CACHE` | `/tmp/.pc-route` | 路由缓存文件 |
| `PC_INBOX` | `~/inbox` | 拉回来的文件目录 |
| `PC_HTTP_PORT` | `8099` | `pcget` 的本地 HTTP 端口 |
| `PC_EVERYTHING_PORT` | `18080` | Everything HTTP Server 端口 |

## 常见问题

**提示所有路由都不通**

先手动确认网络：

```sh
ssh -v -o ConnectTimeout=25 用户名@地址 "exit 0"
```

移动网络 RTT 常到 300~600ms，5 秒超时可能误判。`pc` 的探针上限是 15 秒；临时排查时把 `CONN_CT` 调大。

**局域网地址能 ping 通，但 `pc` 不走 lan**

按顺序查三处：

1. Windows 防火墙。sshd 自带规则通常只覆盖 Private profile。若电脑所在网络被识别为 Public，22 端口会被默认策略丢掉，需要单独加一条 Public 规则放行来源网段。
2. 客户端的 `IdentityFile`。`ssh_config` 里若按 `Host` 指定密钥，局域网地址必须命中同一个 Host 模式，否则 ssh 不会提供任何密钥，表现为 `Permission denied (publickey)`。
3. 学习到的地址过期。删掉 `~/.local/state/pc/lan-host` 和 `lan-try`，下次连接会重新学习。

**IPv6 路由不通，但 ping 能通**

安卓只能挂一个 VPN。Clash 开了 tun 且没开 IPv6 时，v6 会被拦掉。处理方式：在 Clash 里打开 IPv6，或关掉 Clash 走 Tailscale。

**中文文本在浏览器里乱码**

Windows 上存成 UTF-8 带 BOM，首字节 `EF BB BF`。浏览器按 GBK 解码 UTF-8 无 BOM 文件时会出现「鏀惰垂」这类乱码。

**scp 路径怎么写**

Windows 路径 `F:\dir\file.txt` 在 scp 里写成 `/F:/dir/file.txt`。`pc --scp` 会自动转换。

**SSH 进来没有管理员权限**

Windows OpenSSH 登录得到的是 UAC 过滤后的令牌。需要提权的命令，单独用计划任务或其他方式执行。

**推大文件被截断**

Windows 命令行有 8191 字符上限。用 `pcpush`，它按 4000 字节分片追加写。

**平板上的 Termux 里 ssh 连不上**

Termux 默认不带 ssh 客户端，也没有密钥。装 `openssh`、生成密钥、把公钥加到电脑，然后确认有一条可用的路由（Tailscale App 在线，或电脑有可达的 IPv6）。三样齐了就能连。

## 安全

- 仓库里没有任何私钥、token、主机地址或用户名
- 私钥只放在本机 `~/.ssh/`，不要提交、不要贴给别人
- 防火墙按来源地址放行，尽量别把 22 端口开到整个公网
- 优先走 Tailscale；公网 IPv6 方案请配合防火墙白名单

## License

MIT
