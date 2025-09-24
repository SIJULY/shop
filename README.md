独角数卡一键部署脚本 (ARM 架构专用)
这是一个用于在基于 Debian/Ubuntu 的 ARM 架构 VPS 上一键部署“独角数卡”项目的 Shell 脚本。

脚本会自动处理所有依赖安装、文件配置、镜像构建和项目初始化工作。

✨ 特性
一键化: 真正实现从零到可访问的自动化部署。

ARM 架构适配: 解决了在 ARM VPS 上部署时可能遇到的所有已知问题（如基础镜像不兼容、数据库权限等）。

交互式配置: 脚本会引导您输入域名和数据库密码，无需手动修改配置文件。

Caddy 自动 HTTPS: 使用 Caddy 作为网页服务器，自动为您配置 SSL 证书，实现 HTTPS 加密访问。

🚀 使用方法
在您全新的、纯净的 ARM VPS 上，只需一行命令即可开始部署。

请将下面的命令中的 你的用户名 和 你的仓库名 替换为您自己的 GitHub 用户名和仓库名。

wget [https://raw.githubusercontent.com/SIJULY/shop/main/install.sh](https://raw.githubusercontent.com/SIJULY/shop/main/install.sh) && chmod +x install.sh && ./install.sh

📋 脚本执行流程
环境检查: 自动检查并安装 Docker, Docker Compose, Git。

信息收集: 提示您输入用于网站访问的域名和用于数据库的密码。

自动配置: 脚本将根据您的输入，自动在 /root/dujiaoka 目录下生成所有必需的配置文件 (docker-compose.yml, Dockerfile, Caddyfile)。

构建与启动: 自动在本地构建适配 ARM 架构的 PHP 镜像，并启动所有服务。

初始化: 自动安装 PHP 依赖并设置正确的文件权限。

⚠️ 注意事项
前提条件:

本脚本适用于全新的、基于 Debian 或 Ubuntu 的 ARM 架构（aarch64）VPS。

请确保在运行脚本前，您的域名已经解析到了这台 VPS 的 IP 地址。

请确保您 VPS 的防火墙（安全组）已经开放了 80 和 443 端口。

后续操作: 脚本执行成功后，请务必按照命令行最后的提示，打开浏览器完成最后的网页端安装步骤。
