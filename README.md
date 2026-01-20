# 独角数卡一键部署脚本 (ARM 架构专用)

专为 ARM/AMD 架构优化 | 智能 IP/域名双模 | 自动 HTTPS | 菜单化管理

这是一个基于 Docker 的独角数卡一键部署工具。它不再依赖本地繁琐的编译过程，而是直接拉取优化后的云端镜像，实现了秒级部署、自动配置和无痛更新。

## ✨ 特性

* **⚡️ 极速安装:**: 摒弃本地编译，直接拉取 sijuly0713/dujiaoka 预编译镜像，部署时间从 20 分钟缩短至 30 秒。
* **🧠 智能双模:**:
* 
域名模式: 自动申请 SSL 证书，开启 HTTPS，强制后台安全连接。
IP 模式: 自动识别 IP 输入，支持自定义端口，适合内网或无域名测试。
* **🛠 全能管理菜单:**: 内置 安装、更新 (保留数据)、卸载 (可选删库) 功能。
* **🛡Caddy 自动 HTTPS**: 使用 Caddy 作为网页服务器，自动为您配置 SSL 证书，实现 HTTPS 加密访问。

## 🚀 一键安装

```bash
wget https://raw.githubusercontent.com/SIJULY/shop/main/install.sh && chmod +x install.sh && ./install.sh
```

## 📖 登陆设置

![telegram-cloud-photo-size-1-5150420585916599219-y](https://github.com/user-attachments/assets/cd6b58b3-4ba1-4301-b93a-d10d5ec839e3)

1. 数据库配置 (最关键部分)选项填写内容说明MySQL 数据库地址db必须填这个！ (代表 Docker 里的数据库容器)
2. MySQL 端口3306保持默认MySQL
3. 数据库名dujiaoka保持默认MySQL
4. 用户名dujiaoka注意： 默认是 root，建议改为 dujiaoka
5. MySQL 密码你刚才在脚本里设置的密码就是安装脚本运行时让你输入的那个密码
6. Redis 配置选项填写内容说明Redis 连接地址redis必须填这个！ (代表 Docker 里的 Redis 容器)Redis
7. 密码(留空)不要填任何东西
8. Redis 端口6379保持默认



### 第六步：常见问题与维护

* **如何查看日志？**
    * 查看程序日志: `docker-compose logs -f app`
    * 查看网页服务器日志: `docker-compose logs -f caddy`

* **如何停止/启动？**
    * 停止: `docker-compose down`
    * 启动: `docker-compose up -d`

* **如果安装彻底失败，如何从头再来？**
    如果遇到无法解决的问题，可以彻底清除数据，然后从本教程第二步重新开始。
    ```bash
    # 停止并删除所有容器、网络
    docker-compose down

    # 删除所有数据库数据
    sudo rm -rf ./mysql-data

    # 删除Caddy证书数据
    sudo rm -rf ./caddy_data ./caddy_config
    ```

---
至此，您已完成独角数卡的所有部署和修正工作，可以开始正常使用了。
