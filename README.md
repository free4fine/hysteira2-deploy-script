# Hysteria 2 + Far & Field 部署项目

在 Linux VPS 上安装官方 Hysteria 2，并自动部署项目自带的 Far & Field 静态网站。向导可分别设置代理 UDP 端口与网站 HTTPS TCP 端口，默认均为 **443**；**TCP 80** 固定用于申请和续期域名证书。

这是独立的 Bash 项目：网站 ZIP 已随项目提供，安装不依赖上级目录、其他网站项目、Node.js 或 Python。Hysteria 程序仍需联网从官方来源下载安装。

## 开始使用

1. 将域名的 A / AAAA 记录指向 VPS；没有可用 IPv6 时不要配置 AAAA。域名应直接解析到 VPS。
2. 在云平台入站规则和系统防火墙中允许 TCP 80，以及准备使用的网站 TCP 端口和代理 UDP 端口。使用默认值时放行 TCP 80、TCP 443、UDP 443。脚本不会自动清空或修改防火墙规则。
3. 将**整个项目文件夹**上传到 VPS，在该文件夹运行：

```bash
sudo bash ./hysteria-maintain
```

选择 `1` 进入首次安装向导：

1. 填写域名，例如 `example.com`；必须填写，不带 `https://`、端口或路径。
2. 填写代理 UDP 端口，回车默认 `443`。
3. 填写网站 HTTPS TCP 端口，回车默认 `443`。
4. 核对域名、端口、网站地址和防火墙放行提示，输入 `y` 开始安装；其他输入取消。

端口接受 `1–65535` 的整数；格式错误会提示重新填写。TCP 和 UDP 可以使用相同数字，但网站 HTTPS 端口不能为 `80`，因为 TCP 80 保留给证书验证。向导完成后，脚本检查所选端口占用，并自动校验解压网站、生成随机密码、安装官方 Hysteria、写入配置并启用服务。自定义网站端口通过 `https://example.com:端口/` 访问。

完成后可在任意目录运行：

```bash
sudo hysteria-maintain
```

安装、重装和重启后会等待 HTTPS 就绪，最多约 60 秒，再显示状态，避免首次证书尚未签发时立即报异常。如果等待超时，仍会显示实际检查结果，可稍后选择 `2` 复查，或选择 `3` 查看签发日志。客户端参数和分享链接在菜单 `4`，分享链接包含密码。

### 系统要求

- Linux、systemd、管理员权限及正常的互联网访问。主要面向 Debian / Ubuntu。
- 缺少必要工具时，Debian / Ubuntu 会自动通过 `apt-get` 安装依赖；其他系统需要自行安装脚本提示的工具。
- 首次安装要求相关 Hysteria 文件和目标网站目录不存在，TCP 80、所选网站 TCP 端口及代理 UDP 端口未被其他程序占用。已有的非本项目安装会被拒绝覆盖。
- 本项目沿用官方支持的 `HYSTERIA_USER=root` 服务方式，凭据目录权限为 700，密码和配置文件权限为 600。

## 菜单

| 选项 | 功能 |
| --- | --- |
| 1 | 首次安装；检测到本项目已安装时，确认后重新安装官方程序，备份并保留原配置、密码和网站 |
| 2 | 检查服务、运行时长、版本、开机启动、域名、公网 IPv4/IPv6、A/AAAA、实际配置端口、证书、网站和近期异常 |
| 3 | 查看最近 100 条服务日志 |
| 4 | 查看客户端参数和分享链接 |
| 5 | 重启服务并检查状态 |
| 6 | 确认后删除本项目的服务、运行配置、凭据和已部署网站；保留菜单与安装用网站包以便重新安装 |
| 0 | 退出 |

重装显示并保留现有域名、端口、密码、配置和网站，不再次询问新参数；只有网站目录完全缺失时才恢复自带网站包。更换网站内容时请自行备份并更新网站目录。删除功能会同时删除项目状态目录中的配置备份，需要长期保留的内容请提前另存。

## 项目结构

```text
hysteira2-deploy-script/
├── hysteria-maintain                 # 安装与运维入口
├── assets/
│   ├── far-and-field.zip             # 自带网站，ZIP 根目录直接包含 index.html
│   └── far-and-field.zip.sha256      # 完整性校验
├── docs/
│   ├── OPERATIONS.md                # 状态页和服务器目录说明
│   └── WEBSITE-ASSET-SOURCES.md     # 网站图片来源与许可说明
├── tools/package-website.sh          # 更新网站 ZIP 的打包工具
└── tests/                           # 在临时目录验证安装、网站包和端口同步
```

文件夹名称沿用用户指定的 `hysteira2-deploy-script`。仓库只保存安装资料，不包含服务器真实密码、私钥或证书。

## 更新网站包

维护网站内容后，将已构建好的静态目录作为参数：

```bash
bash tools/package-website.sh /绝对路径/网站/dist
```

该命令重新生成 ZIP 与 SHA-256 文件。脚本执行安装时会验证校验值、ZIP 完整性、网站入口和路径安全；校验值用于发现损坏或误改，不是数字签名。

## 验证

本地回归测试和网站打包需要 `zip`、`unzip`、`zipinfo` 命令。Ubuntu / Debian 可先安装 `zip unzip`；这属于开发与验收工具，服务器正常安装只需要脚本自动检查的运行依赖。

```bash
bash -n hysteria-maintain
bash tests/test-install.sh
bash tests/test-status-ports.sh
bash tests/test-readiness.sh
```

测试使用模拟的官方安装程序及服务命令，全部文件写入临时目录，不连接 VPS、不安装真实服务。网站 ZIP 则进行实际校验、解压和文件对比。

真机安装、重装、删除及公网连接的验证结果见 [JP2 验收记录](docs/JP2-ACCEPTANCE-2026-10-29.md)，其中单独记录了当前电脑访问网站时的间歇 TCP 超时及对照结果。

## 官方参考

- [Hysteria 官方安装脚本](https://v2.hysteria.network/docs/getting-started/Server-Installation-Script/)
- [服务端配置](https://v2.hysteria.network/docs/advanced/Full-Server-Config/)
- [故障排查](https://v2.hysteria.network/docs/advanced/Troubleshooting/)

菜单与网站打包逻辑由本项目提供，不是 Hysteria 官方安装脚本的一部分。安装调用 `https://get.hy2.sh/`，默认安装运行时最新的官方版本；版本更新后的行为以官方说明为准。
