#!/bin/bash

# ==============================================================================
# 独角数卡 (Dujiaoka) ARM VPS 终极部署一键脚本
#
# v1.5 (最终稳定版) - 移除自动填充数据和重置密码步骤，改为引导用户进行Web安装
#
# 作者: 小龙女她爸
# ==============================================================================

# 设置颜色
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[34m"
PLAIN="\033[0m"

# 确保脚本以root权限运行
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}错误: 请以root权限运行此脚本。${PLAIN}"
  exit 1
fi

# 函数：打印信息
info() {
    echo -e "${GREEN}[信息] $1${PLAIN}"
}

warn() {
    echo -e "${YELLOW}[警告] $1${PLAIN}"
}

error() {
    echo -e "${RED}[错误] $1${PLAIN}"
    exit 1
}

# 函数：检查并安装依赖
check_and_install_deps() {
    info "正在检查系统依赖 (git, curl, docker)..."
    if ! command -v git &> /dev/null || ! command -v curl &> /dev/null || ! command -v docker &> /dev/null; then
        warn "部分依赖未安装，正在尝试自动安装..."
        if command -v apt-get &> /dev/null; then
            apt-get update
            apt-get install -y git curl
            if ! command -v docker &> /dev/null; then
              # 先尝试从 Ubuntu 源安装
              apt-get install -y docker.io || error "从Ubuntu源安装docker.io失败。"
              apt-get install -y docker-compose || warn "从Ubuntu源安装docker-compose可能版本过旧。"
            fi
            systemctl start docker
            systemctl enable docker
        else
            error "不支持的操作系统。请手动安装 git, curl, 和 Docker。"
        fi
    fi
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE_COMMAND="docker compose"
    elif docker-compose version &> /dev/null; then
        warn "推荐的 Docker Compose V2 (带空格) 不可用，将使用旧版 docker-compose (带连字符)。"
        DOCKER_COMPOSE_COMMAND="docker-compose"
    else
        error "Docker Compose 未安装或无法运行，请检查您的 Docker 环境。"
    fi
    info "所有依赖已满足。"
}

# --- 脚本主逻辑开始 ---

clear
echo -e "${BLUE}=====================================================${PLAIN}"
echo -e "${BLUE}    欢迎使用独角数卡终极部署一键脚本 v1.5 (最终稳定版)      ${PLAIN}"
echo -e "${BLUE}=====================================================${PLAIN}"
echo

# 1. 检查依赖
check_and_install_deps

# 2. 收集用户信息
info "请输入您的配置信息："
read -p "请输入您的网站域名 (例如: shop.yourdomain.com): " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then
    error "域名不能为空！"
fi

read -p "请输入数据库密码 (默认: Admin888): " DB_PASSWORD
DB_PASSWORD=${DB_PASSWORD:-Admin888}

DB_ROOT_PASSWORD="dujiaoka_root_password_$(date +%s)"

INSTALL_DIR="/root"
info "源码将安装在 $INSTALL_DIR 目录下。"
echo

# 3. 下载源码
info "正在从 GitHub 下载独角数卡源码..."
cd "$INSTALL_DIR" || exit 1
if [ -d "dujiaoka" ]; then
    warn "dujiaoka 目录已存在，将进行覆盖安装。"
    rm -rf dujiaoka
fi
git clone https://github.com/assimon/dujiaoka.git
cd dujiaoka || error "进入 dujiaoka 目录失败。"
info "源码下载完成。"

# 4. 创建配置文件
info "正在创建并修正配置文件..."

# --- 创建 Dockerfile ---
cat > Dockerfile << EOF
FROM php:7.4-fpm-buster
WORKDIR /var/www/html
RUN sed -i -e 's/deb.debian.org/archive.debian.org/g' \
    -e 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' \
    -e '/buster-updates/d' /etc/apt/sources.list
RUN apt-get update && apt-get install -y git curl libpng-dev libonig-dev libxml2-dev zip unzip libzip-dev
RUN docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip
RUN pecl install -o -f redis && rm -rf /tmp/pear && docker-php-ext-enable redis
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
RUN chown -R www-data:www-data /var/www/html
EOF
info "Dockerfile 创建成功。"

# --- 创建 docker-compose.yml ---
cat > docker-compose.yml << EOF
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: dujiaoka_app
    restart: always
    links:
      - db
      - redis
    volumes:
      - .:/var/www/html
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
  db:
    image: mariadb:10.8
    container_name: dujiaoka_db
    restart: always
    user: root
    environment:
      MYSQL_ROOT_PASSWORD: "${DB_ROOT_PASSWORD}"
      MYSQL_DATABASE: "dujiaoka"
      MYSQL_USER: "dujiaoka"
      MYSQL_PASSWORD: "${DB_PASSWORD}"
    volumes:
      - ./mysql-data:/var/lib/mysql
  redis:
    image: redis:6.2
    container_name: dujiaoka_redis
    restart: always
volumes:
  caddy_data:
  caddy_config:
EOF
info "docker-compose.yml 创建成功。"

# --- 创建 Caddyfile ---
cat > Caddyfile << EOF
${DOMAIN_NAME} {
    root * /var/www/html/public
    php_fastcgi app:9000
    file_server
}
EOF
info "Caddyfile 创建成功。"

# --- 创建 .env 文件 ---
cp .env.example .env
sed -i "s|APP_URL=http://localhost|APP_URL=https://${DOMAIN_NAME}|g" .env
sed -i "s|DB_PASSWORD=|DB_PASSWORD=${DB_PASSWORD}|g" .env
sed -i "s|ADMIN_HTTPS=false|ADMIN_HTTPS=true|g" .env
info ".env 文件创建并修正成功。"

# 5. 构建和初始化
info "正在构建并启动 Docker 容器，这可能需要几分钟..."
$DOCKER_COMPOSE_COMMAND up -d --build
info "容器启动成功。等待数据库初始化..."
retry_count=0
max_retries=20
until $DOCKER_COMPOSE_COMMAND exec db mysqladmin ping -h"127.0.0.1" --silent; do
    info "等待数据库服务就绪... (${retry_count}/${max_retries})"
    sleep 3
    retry_count=$((retry_count+1))
    if [ $retry_count -ge $max_retries ]; then
        error "数据库服务长时间未就绪，安装失败。"
    fi
done
info "数据库服务已就绪。"

info "正在为数据库用户授予远程访问权限..."
$DOCKER_COMPOSE_COMMAND exec db mysql -u root -p"${DB_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON dujiaoka.* TO 'dujiaoka'@'%';"
info "数据库权限授予成功。"

# 6. 修复权限并初始化应用
info "正在设置文件权限..."
mkdir -p storage/logs
chown -R 33:33 .
chmod -R 777 storage bootstrap/cache
info "文件权限设置完成。"

info "正在安装PHP依赖并初始化应用..."
$DOCKER_COMPOSE_COMMAND exec app composer install --no-dev -o
$DOCKER_COMPOSE_COMMAND exec app php artisan key:generate --force
$DOCKER_COMPOSE_COMMAND exec app php artisan migrate --force
$DOCKER_COMPOSE_COMMAND exec app php artisan config:clear
info "应用初始化完成。"


# 7. 完成
clear
echo -e "${GREEN}=====================================================${PLAIN}"
echo -e "${GREEN}    🎉 恭喜！后台环境已成功部署！ 🎉    ${PLAIN}"
echo -e "${GREEN}=====================================================${PLAIN}"
echo
echo -e "${YELLOW}下一步，请在浏览器中完成最后的安装步骤：${PLAIN}"
echo
echo -e "1. 打开浏览器, 访问您的域名: ${BLUE}https://${DOMAIN_NAME}${PLAIN}"
echo -e "2. 您将看到独角数卡的网页安装向导。"
echo -e "3. 按照提示完成安装，并在最后一步设置您的管理员账号和密码。"
echo
echo -e "祝您使用愉快！"
echo
