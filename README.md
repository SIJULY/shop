# 独角数卡一键部署脚本 (ARM 架构专用)

这是一个用于在基于 Debian/Ubuntu 的 ARM 架构 VPS 上一键部署“独角数卡”项目的 Shell 脚本。

脚本会自动处理所有依赖安装、文件配置、镜像构建和项目初始化工作。

## ✨ 特性

* **一键化**: 真正实现从零到可访问的自动化部署。
* **ARM 架构适配**: 解决了在 ARM VPS 上部署时可能遇到的所有已知问题（如基础镜像不兼容、数据库权限等）。
* **交互式配置**: 脚本会引导您输入域名和数据库密码，无需手动修改配置文件。
* **Caddy 自动 HTTPS**: 使用 Caddy 作为网页服务器，自动为您配置 SSL 证书，实现 HTTPS 加密访问。

## 🚀 使用方法

在您全新的、纯净的 ARM VPS 上，只需下列命令即可开始部署。


    ```bash
    wget https://raw.githubusercontent.com/SIJULY/shop/main/install.sh && chmod +x install.sh && ./install.sh
    ```


## 📋 脚本执行流程

* **环境检查**: 自动检查并安装 Docker, Docker Compose, Git。
* **信息收集**: 提示您输入用于网站访问的域名和用于数据库的密码。
* **自动配置**: 脚本将根据您的输入，自动在 `/root/dujiaoka` 目录下生成所有必需的配置文件 (`docker-compose.yml`, `Dockerfile`, `Caddyfile`, `.env`)。
* **构建与启动**: 自动在本地构建适配 ARM 架构的 PHP 镜像，并启动所有服务。
* **初始化**: 自动安装 PHP 依赖、修正文件权限并重置管理员密码，跳过繁琐的网页安装。

## ⚠️ 注意事项

**前提条件**:
* 本脚本适用于全新的、基于 Debian 或 Ubuntu 的 ARM 架构（aarch64）VPS。
* 请确保在运行脚本前，您的域名已经解析到了这台 VPS 的 IP 地址。
* 请确保您 VPS 的防火墙（或云服务商的安全组）已经开放了 `80` 和 `443` 端口。

---

## 📖 手动安装分步指南

本教程整合了多次部署实践中的所有问题和解决方案，旨在提供一个从零开始、稳定可靠的部署流程，特别解决了原版教程中常见的数据库权限、文件写入以及管理员密码设置失败等核心问题。

### 第一步：准备工作 (环境与前置配置)

1.  **一台 ARM 架构的 VPS**：确保系统纯净，推荐 Ubuntu 20.04+ 或 Debian 10+。

2.  **安装 Docker 和 Docker Compose**：
    ```bash
    # 更新系统并安装 Docker 环境
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh

    # 安装 Docker Compose
    sudo apt-get update
    sudo apt-get install -y docker-compose

    # 启动 Docker 并设置为开机自启
    sudo systemctl start docker
    sudo systemctl enable docker
    ```

3.  **准备域名并解析**：
    * 准备一个域名，例如 `shop.yourdomain.com`。
    * 到您的域名服务商后台，添加一条 A 记录，将该域名解析到您 VPS 的公网 IP 地址。

4.  **开放防火墙端口**：
    确保您的 VPS 防火墙允许 `80` (HTTP) 和 `443` (HTTPS) 端口的入站流量。
    ```bash
    # 以 ufw 防火墙为例
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw reload
    ```

### 第二步：下载源码并创建核心配置文件

1.  **下载源码**：
    ```bash
    # 我们将项目放在 /root 目录下
    cd /root
    git clone https://github.com/assimon/dujiaoka.git
    cd dujiaoka
    ```

2.  **创建四个核心文件**：
    在 `dujiaoka` 目录下，**忽略项目自带的文件**，手动创建或覆盖以下四个文件。

    **1. `Dockerfile` (已修复 Debian 源问题)**
    ```dockerfile
    # 使用官方的、支持 ARM 架构的 PHP-FPM 镜像作为基础
    FROM php:7.4-fpm-buster

    # 设置工作目录
    WORKDIR /var/www/html

    # --- [核心修复] ---
    # 由于 Debian "Buster" 已过期，其软件源已失效。
    # 我们需要将软件源地址修改为 Debian 的存档服务器地址。
    RUN sed -i -e 's/deb.debian.org/archive.debian.org/g' \
        -e 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' \
        -e '/buster-updates/d' /etc/apt/sources.list
    # --- [核心修复结束] ---

    # 更新包列表并安装编译 PHP 扩展所需的系统依赖
    RUN apt-get update && apt-get install -y \
        git \
        curl \
        libpng-dev \
        libonig-dev \
        libxml2-dev \
        zip \
        unzip \
        libzip-dev

    # 安装 Dujiaoka 所需的 PHP 扩展
    RUN docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip

    # 安装 Redis 扩展
    RUN pecl install -o -f redis \
        && rm -rf /tmp/pear \
        && docker-php-ext-enable redis

    # 安装 Composer (PHP 依赖管理器)
    RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    # 更改目录所有者为 www-data，以便 Caddy 和 PHP-FPM 进程可以读写
    RUN chown -R www-data:www-data /var/www/html
    ```

    **2. `docker-compose.yml` (已修复数据库权限问题)**
    ```yaml
    services:
      # PHP 应用服务
      app:
        build:
          context: .
          dockerfile: Dockerfile
        container_name: dujiaoka_app
        restart: always
        volumes:
          - .:/var/www/html
        networks:
          - dujiaoka_network

      # Caddy 网页服务
      caddy:
        image: caddy:2-alpine
        container_name: dujiaoka_caddy
        restart: always
        ports:
          - "80:80"
          - "443:443"
        volumes:
          - .:/var/www/html
          - ./Caddyfile:/etc/caddy/Caddyfile
          - caddy_data:/data
          - caddy_config:/config
        depends_on:
          - app
        networks:
          - dujiaoka_network

      # 数据库服务
      db:
          image: mariadb:10.8
          container_name: dujiaoka_db
          restart: always
          user: root  # <--- [核心修复] 此行解决了安装时数据库“只读”或权限不足的问题！
          environment:
            MYSQL_ROOT_PASSWORD: "your_strong_root_password" # 请修改为一个复杂的数据库root密码
            MYSQL_DATABASE: "dujiaoka"
            MYSQL_USER: "dujiaoka"
            MYSQL_PASSWORD: "123Abc$" # 这里是你为dujiaoka程序设定的数据库密码，可以修改
          volumes:
            - ./mysql-data:/var/lib/mysql
          networks:
            - dujiaoka_network

      # Redis 服务
      redis:
        image: redis:6.2
        container_name: dujiaoka_redis
        restart: always
        networks:
          - dujiaoka_network

    networks:
      dujiaoka_network:

    volumes:
      caddy_data:
      caddy_config:
    ```

    **3. `Caddyfile`**
    ```caddy
    # 把 shop.yourdomain.com 替换成你自己的域名
    shop.yourdomain.com {
        root * /var/www/html/public
        php_fastcgi app:9000
        file_server
    }
    ```

    **4. `.env` (已包含关键修正)**
    ```dotenv
    APP_NAME=你的商店名称
    APP_ENV=local
    APP_KEY=
    APP_DEBUG=false
    APP_URL=https://shop.yourdomain.com # 替换成你自己的域名(https开头)

    LOG_CHANNEL=stack

    # 数据库配置 (必须与 docker-compose.yml 中保持一致)
    DB_CONNECTION=mysql
    DB_HOST=db
    DB_PORT=3306
    DB_DATABASE=dujiaoka
    DB_USERNAME=dujiaoka
    DB_PASSWORD=123Abc$ # 必须与 docker-compose.yml 中 MYSQL_PASSWORD 的值一致

    # redis配置
    REDIS_HOST=redis
    REDIS_PASSWORD=
    REDIS_PORT=6379

    BROADCAST_DRIVER=log
    SESSION_DRIVER=file
    SESSION_LIFETIME=120
    CACHE_DRIVER=redis
    QUEUE_CONNECTION=redis
    DUJIAO_ADMIN_LANGUAGE=zh_CN
    ADMIN_ROUTE_PREFIX=/admin

    # [!!! 核心修正 !!!]
    # 如果您使用域名并通过 https 访问，下面这个值必须为 true！
    # 这是导致登录时出现 "0 error" 的关键原因之一。
    ADMIN_HTTPS=true
    ```

### 第三步：构建容器并初始化应用

1.  **构建并启动所有容器**：
    ```bash
    docker-compose up -d --build
    ```

2.  **【核心】修复文件写入权限**：
    在进行Web安装**之前**，我们必须先修复文件权限，防止安装过程和后续登录时出现问题。
    ```bash
    # 确保日志目录存在
    mkdir -p storage/logs

    # 将整个项目文件夹的所有权交给容器内的 www-data 用户(ID:33)
    sudo chown -R 33:33 .

    # 赋予 storage 和 bootstrap/cache 目录最高的读写权限
    sudo chmod -R 777 storage bootstrap/cache
    ```

3.  **运行程序初始化命令**：
    ```bash
    # 安装PHP依赖
    docker-compose exec app composer install --no-dev -o

    # 生成应用密钥
    docker-compose exec app php artisan key:generate --force

    # 运行数据库迁移
    docker-compose exec app php artisan migrate --force

    # 清理配置缓存，确保新的 .env 配置生效
    docker-compose exec app php artisan config:clear
    ```

### 第四步：Web 界面安装

1.  打开浏览器，访问您的域名 (例如 `https://shop.yourdomain.com`)。
2.  您将看到安装向导。由于我们已经提前解决了所有权限问题，您只需按照提示，填写您想设置的管理员账号和密码，即可顺利完成安装。
3.  安装成功后，为安全起见，请重命名或删除 `install` 文件夹：
    ```bash
    mv public/install public/install_bak
    ```

### 第五步：【重要】解决首次登录密码错误的问题

独角数卡的安装程序有时无法正确保存您在Web界面设置的初始管理员密码。如果您使用设置的密码无法登录，请按照以下步骤手动重置。

1.  **进入应用后台命令行 (Tinker)**：
    ```bash
    docker-compose exec app php artisan tinker
    ```

2.  **依次执行以下命令来重置密码**：
    ```php
    // 第一步：找到 admin 用户。注意这里的模型路径是我们最终确认的正确路径。
    $user = Dcat\Admin\Models\Administrator::where('username', 'admin')->first();

    // 第二步：设置您的新密码。把 'YourNewPassword123' 换成您想要的真实密码。
    $user->password = bcrypt('YourNewPassword123');

    // 第三步：保存更改。看到 true 即代表成功。
    $user->save();

    // 第四步：退出。
    exit
    ```

3.  **重新登录**：现在，回到网站后台登录页面，使用用户名 `admin` 和您刚刚设置的新密码，即可成功登录。

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
