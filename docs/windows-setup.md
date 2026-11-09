# Windows 端配置

在管理员 PowerShell 里执行。

## 1. 安装 OpenSSH Server

Windows 10 1809 / 11 自带可选功能：

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
```

确认在监听：

```powershell
Get-Service sshd
Get-NetTCPConnection -LocalPort 22 -State Listen
```

## 2. 放入公钥

在手机上生成密钥对，把公钥内容（`ssh-ed25519 AAAA... comment` 一整行）复制过来。

**登录账户属于 Administrators 组**时，sshd 读的是公共文件：

```powershell
$key = 'ssh-ed25519 AAAA... android-pc'
Add-Content -Path C:\ProgramData\ssh\administrators_authorized_keys -Value $key
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r `
  /grant "Administrators:F" /grant "SYSTEM:F"
```

**普通账户**则放进用户目录：

```powershell
New-Item -ItemType Directory -Force -Path $env:USERPROFILE\.ssh | Out-Null
Add-Content -Path $env:USERPROFILE\.ssh\authorized_keys -Value 'ssh-ed25519 AAAA... android-pc'
```

权限不对时 sshd 会直接拒绝，Windows 上尤其容易踩这个坑。

## 3. 防火墙

默认安装通常会建一条 `OpenSSH Server (sshd)` 规则。没有就手动加：

```powershell
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' `
  -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

如果走公网 IPv6，建议按来源前缀收紧：

```powershell
New-NetFirewallRule -DisplayName 'Allow-SSH-v6-from-phone' `
  -Direction Inbound -Protocol TCP -LocalPort 22 `
  -RemoteAddress 2001:db8:1234::/48 -Action Allow
```

IPv6 前缀会随运营商或校园网变化，变了记得同步改规则。

## 4. 验证

在手机或另一台机器上：

```sh
ssh -o ConnectTimeout=10 用户名@地址 "hostname"
```

首次连接会提示确认主机指纹，核对后输入 `yes`。`pc` 使用 `StrictHostKeyChecking=accept-new`，首次自动接受并记录。

## 5. 可选设置

**默认 shell** 默认就是 PowerShell。想换回 cmd：

```powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
  -Value "C:\Windows\System32\cmd.exe" -PropertyType String -Force
```

**端口** 改 `C:\ProgramData\ssh\sshd_config` 里的 `Port`，同时改防火墙规则和手机端 `PC_PORT`。

**会话权限** SSH 登录得到的是 UAC 过滤令牌，`whoami /groups` 里能看到 Administrators 组标记为「仅用于拒绝」。需要管理员权限的操作，用计划任务以最高权限运行，或另开一个提权通道。

## 6. 排错

| 现象 | 检查 |
| --- | --- |
| 连接被拒 | `Get-Service sshd`、防火墙规则、端口 |
| 提示 Permission denied (publickey) | 公钥位置、文件 ACL、`sshd_config` 的 `PubkeyAuthentication` |
| 连接超时 | 地址是否正确、来源网络是否能到 22 端口 |
| 登录后立刻断开 | `sshd_config` 的 `Subsystem`、用户 profile 脚本报错 |

sshd 日志：

```powershell
Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 30
```
