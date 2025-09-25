#!/bin/bash

# ==============================================================================
# 独角数卡 (Dujiaoka) ARM VPS 终极部署一键脚本 (修正版)
#
# 功能:
#   - 自动安装 Docker 和 Git
#   - 自动下载源码
#   - 自动生成包含所有修正的配置文件 (Dockerfile, docker-compose.yml等)
#   - 自动构建容器并初始化
#   - 自动处理文件权限问题
#   - 自动跳过Web安装并强制重置管理员密码
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

# 函数：打印警告
warn() {
    echo -e "${YELLOW}[警告] $1${PLAIN}"
}

# 函数：打印错误并退出
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
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh
            apt-get install -y docker-compose
            systemctl start docker
            systemctl enable docker
        else
            error "不支持的操作系统。请手动安装 git, curl, 和 Docker。"
        fi
    fi
    info "所有依赖已满足。"
}

# --- 脚本主逻辑开始 ---

clear
echo -e "${BLUE}=====================================================${PLAIN}"
echo -e "${BLUE}    欢迎使用独角数卡终极部署一键脚本 v1.1          ${PLAIN}"
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

read -p "请输入您要设置的后台管理员密码 (默认: Admin888): " ADMIN_PASSWORD
ADMIN_PASSWORD=${ADMIN_PASSWORD:-Admin888}

read -p "请输入数据库密码 (默认: 050148Sq$): " DB_PASSWORD
DB_PASSWORD=${DB_PASSWORD:-"050148Sq$"}

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
    volumes:
      - .:/var/www/html
    networks:
      - dujiaoka_network
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
  db:
    image: mariadb:10.8
    container_name: dujiaoka_db
    restart: always
    user: root
    environment:
      MYSQL_ROOT_PASSWORD: "your_strong_root_password"
      MYSQL_DATABASE: "dujiaoka"
      MYSQL_USER: "dujiaoka"
      MYSQL_PASSWORD: "${DB_PASSWORD}"
    volumes:
      - ./mysql-data:/var/lib/mysql
    networks:
      - dujiaoka_network
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

# --- 创建 .env 文件 (修正) ---
cp .env.example .env
# 修复：使用更健壮的 sed 命令来替换 DB_PASSWORD
sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/" .env
# 确保 DB_USERNAME 和 DB_DATABASE 也匹配
sed -i "s/^DB_USERNAME=.*/DB_USERNAME=dujiaoka/" .env
sed -i "s/^DB_DATABASE=.*/DB_DATABASE=dujiaoka/" .env
info ".env 文件创建并修正成功。"

# 5. 构建和初始化
info "正在构建并启动 Docker 容器，这可能需要几分钟..."
docker-compose up -d --build
info "容器启动成功。等待数据库初始化..."

# 修复：增加数据库就绪检查
until docker-compose exec db mysqladmin ping -hlocalhost -u root -p"${DB_PASSWORD}" &> /dev/null; do
  echo -n "."
  sleep 1
done
echo -e "\n数据库服务已就绪。"

# 6. 修复权限并初始化应用
info "正在设置文件权限..."
mkdir -p storage/logs
chown -R 33:33 .
chmod -R 777 storage bootstrap/cache
info "文件权限设置完成。"

info "正在安装PHP依赖并初始化应用..."
docker-compose exec app composer install --no-dev -o
docker-compose exec app php artisan key:generate --force
docker-compose exec app php artisan migrate --force
docker-compose exec app php artisan config:clear
info "应用初始化完成。"

# 7. 自动重置管理员密码
info "正在自动重置管理员密码..."
docker-compose exec app php artisan db:seed --class=AdminTablesSeeder > /dev/null 2>&1
docker-compose exec -T app php artisan tinker <<EOF
\$user = Dcat\Admin\Models\Administrator::where('username', 'admin')->first();
\$user->password = bcrypt('${ADMIN_PASSWORD}');
\$user->save();
exit
EOF
info "管理员密码重置成功。"

# 8. 创建安装锁定文件
info "正在创建安装锁定文件以跳过Web安装..."
touch public/install.lock

# 9. 完成
clear
echo -e "${GREEN}=====================================================${PLAIN}"
echo -e "${GREEN}    🎉 恭喜！独角数卡已成功部署并完成所有修正！  🎉    ${PLAIN}"
echo -e "${GREEN}=====================================================${PLAIN}"
echo
echo -e "后台登录地址: ${YELLOW}https://${DOMAIN_NAME}/admin${PLAIN}"
echo -e "用户名:           ${YELLOW}admin${PLAIN}"
echo -e "密码:             ${YELLOW}${ADMIN_PASSWORD}${PLAIN}"
echo
echo -e "您可以将此脚本上传到 GitHub，方便在其他VPS上快速部署。"
echo -e "祝您使用愉快！"
echo
