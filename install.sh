#!/bin/bash

# ==============================================================================
# 独角数卡 (Dujiaoka) ARM 架构 VPS 一键部署脚本
#
# 功能:
# 1. 自动检测并安装 Docker, Docker Compose, Git。
# 2. 从 GitHub 克隆最新的 Dujiaoka 源代码。
# 3. 交互式地获取用户域名和数据库密码。
# 4. 自动创建 docker-compose.yml, Dockerfile, Caddyfile。
# 5. 自动构建 Docker 镜像、启动所有服务、并完成初始化。
#
# 使用方法:
# wget https://raw.githubusercontent.com/你的用户名/你的仓库名/main/install.sh
# chmod +x install.sh
# ./install.sh
# ==============================================================================

# 定义颜色
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
PLAIN="\033[0m"

echo -e "${GREEN}独角数卡 ARM 架构 VPS 一键部署脚本即将开始...${PLAIN}"

# --- 函数定义 ---

# 检查并安装依赖
check_and_install_deps() {
    echo -e "${YELLOW}正在检查并安装必要的依赖...${PLAIN}"
    
    # 检查 Git
    if ! command -v git &> /dev/null; then
        echo "未检测到 Git，正在安装..."
        apt-get update && apt-get install -y git
    fi

    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        echo "未检测到 Docker，正在安装..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
    fi

    # 检查 Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        echo "未检测到 Docker Compose，正在安装..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi
    
    echo -e "${GREEN}所有依赖已准备就绪。${PLAIN}"
}

# 获取用户输入
get_user_input() {
    echo -e "${YELLOW}请输入部署所需的配置信息:${PLAIN}"
    read -p "请输入您准备好的域名 (例如 shop.yourdomain.com): " DOMAIN_NAME
    while [ -z "${DOMAIN_NAME}" ]; do
        echo -e "${RED}域名不能为空，请重新输入!${PLAIN}"
        read -p "请输入您准备好的域名 (例如 shop.yourdomain.com): " DOMAIN_NAME
    done

    read -sp "请为数据库设置一个复杂的密码: " DB_PASSWORD
    while [ -z "${DB_PASSWORD}" ]; do
        echo -e "\n${RED}数据库密码不能为空，请重新输入!${PLAIN}"
        read -sp "请为数据库设置一个复杂的密码: " DB_PASSWORD
    done
    echo "" # 换行
}

# --- 主逻辑 ---

# 1. 准备工作
check_and_install_deps
get_user_input

# 2. 获取源代码
echo -e "${YELLOW}正在从 GitHub 克隆独角数卡源代码...${PLAIN}"
git clone https://github.com/assimon/dujiaoka.git
cd dujiaoka

# 3. 创建配置文件
echo -e "${YELLOW}正在根据您的输入创建配置文件...${PLAIN}"

# 创建 docker-compose.yml
cat <<EOF > docker-compose.yml
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

# 创建 Dockerfile
cat <<EOF > Dockerfile
FROM php:7.4-fpm-buster
WORKDIR /var/www/html
RUN sed -i -e 's/deb.debian.org/archive.debian.org/g' \
       -e 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' \
       -e '/buster-updates/d' /etc/apt/sources.list
RUN apt-get update && apt-get install -y \
    git curl libpng-dev libonig-dev libxml2-dev zip unzip libzip-dev
RUN docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip
RUN pecl install -o -f redis && rm -rf /tmp/pear && docker-php-ext-enable redis
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
RUN chown -R www-data:www-data /var/www/html
EOF

# 创建 Caddyfile
cat <<EOF > Caddyfile
${DOMAIN_NAME} {
    root * /var/www/html/public
    php_fastcgi app:9000
    file_server
}
EOF

echo -e "${GREEN}所有配置文件已创建成功！${PLAIN}"

# 4. 构建、启动与初始化
echo -e "${YELLOW}正在构建 Docker 镜像，这个过程会比较长，请耐心等待...${PLAIN}"
docker-compose up -d --build

echo -e "${YELLOW}正在安装 PHP 依赖包...${PLAIN}"
docker-compose exec app composer install --ignore-platform-reqs

echo -e "${YELLOW}正在设置文件权限...${PLAIN}"
docker-compose exec app chown -R www-data:www-data /var/www/html

# 5. 完成提示
echo -e "${GREEN}===================================================================${PLAIN}"
echo -e "${GREEN}🎉 恭喜您！独角数卡已成功部署！ 🎉${PLAIN}"
echo -e "${GREEN}===================================================================${PLAIN}"
echo -e "${YELLOW}请立即执行以下后续步骤:${PLAIN}"
echo -e "1. ${GREEN}请确保您的域名 ${DOMAIN_NAME} 已正确解析到本服务器 IP。${PLAIN}"
echo -e "2. ${GREEN}请确保您服务器的防火墙（安全组）已开放 80 和 443 端口。${PLAIN}"
echo -e "3. 打开浏览器，访问 ${GREEN}https://${DOMAIN_NAME}${PLAIN}"
echo -e "4. 在安装向导中，填写以下信息:"
echo -e "   - MySQL 数据库地址: ${GREEN}db${PLAIN}"
echo -e "   - MySQL 用户名: ${GREEN}dujiaoka${PLAIN}"
echo -e "   - MySQL 密码: ${GREEN}您刚才设置的密码${PLAIN}"
echo -e "   - Redis 连接地址: ${GREEN}redis${PLAIN}"
echo -e "   - 网站 url: ${GREEN}https://${DOMAIN_NAME}${PLAIN}"
echo -e "5. 安装完成后，登录后台，在 ${YELLOW}配置 -> 系统设置${PLAIN} 中再次确认网站 URL 正确无误。"
echo -e "${GREEN}祝您使用愉快！${PLAIN}"
