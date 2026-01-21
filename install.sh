#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 固定安装目录
INSTALL_DIR="/root/dujiaoka_sijuly"

# ====================================================
# 函数：环境检查
# ====================================================
check_env() {
    for cmd in wget openssl curl; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${YELLOW}[系统] 正在安装 $cmd...${NC}"
            if [ -f /etc/redhat-release ]; then
                yum install -y $cmd
            elif [ -f /etc/debian_version ]; then
                apt-get update && apt-get install -y $cmd
            fi
        fi
    done

    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}[系统] 正在安装 Docker...${NC}"
        curl -fsSL https://get.docker.com | bash -s docker
        systemctl enable docker
        systemctl start docker
    fi

    if ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}[系统] 正在安装 Docker Compose...${NC}"
        curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
}

# ====================================================
# 函数：安装/重装
# ====================================================
install_shop() {
    check_env
    
    echo -e "${YELLOW}[配置] 请输入站点配置信息：${NC}"
    read -p "请输入您的域名或IP (例如 shop.test.com 或 192.168.1.5): " USER_INPUT
    read -p "请设置数据库密码 (尽量复杂): " USER_DB_PASS

    if [ -z "$USER_INPUT" ] || [ -z "$USER_DB_PASS" ]; then
        echo -e "${RED}[错误] 输入不能为空！${NC}"
        return
    fi

    RAW_INPUT=$(echo "$USER_INPUT" | sed 's~http[s]*://~~g')
    
    if [[ $RAW_INPUT =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        IS_IP_MODE="true"
        echo -e "${YELLOW}[识别] 检测到您使用的是 IP 模式。${NC}"
        read -p "请输入访问端口 (默认 8080): " USER_PORT
        USER_PORT=${USER_PORT:-8080}
        FINAL_URL="http://${RAW_INPUT}:${USER_PORT}"
        HTTPS_STATE="false"
        CADDY_CONFIG=":80"
        echo -e "将在端口 ${GREEN}${USER_PORT}${NC} 上部署 HTTP 服务。"
    else
        IS_IP_MODE="false"
        echo -e "${YELLOW}[识别] 检测到您使用的是 域名 模式。${NC}"
        FINAL_URL="https://${RAW_INPUT}"
        HTTPS_STATE="true"
        CADDY_CONFIG="${RAW_INPUT}"
        echo -e "将在端口 ${GREEN}80/443${NC} 上部署 HTTPS 服务。"
    fi

    # 检测目录是否存在，避免暴力覆盖导致配置丢失
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${RED}[警告] 检测到安装目录已存在！${NC}"
        read -p "是否覆盖安装？(y/n): " OVERWRITE
        if [[ "$OVERWRITE" != "y" ]]; then return; fi
        rm -rf "$INSTALL_DIR"
    fi

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    echo -e "${GREEN}[1/5] 下载配置文件...${NC}"
    wget -O docker-compose.yml https://raw.githubusercontent.com/SIJULY/shop/main/docker-compose.yml
    wget -O env.conf https://raw.githubusercontent.com/SIJULY/shop/main/env.conf

    echo -e "${GREEN}[2/5] 生成 Caddy 配置...${NC}"
    if [ "$IS_IP_MODE" == "true" ]; then
        cat > Caddyfile <<EOF
${CADDY_CONFIG} {
    reverse_proxy web:80
}
EOF
    else
        cat > Caddyfile <<EOF
${CADDY_CONFIG} {
    reverse_proxy web:80
    encode gzip
}
EOF
    fi

    echo -e "${GREEN}[3/5] 配置参数...${NC}"
    # 生成随机 Key
    NEW_APP_KEY="base64:$(openssl rand -base64 32)"
    sed -i "s|APP_KEY=APP_KEY|APP_KEY=${NEW_APP_KEY}|g" env.conf
    
    # 替换 URL 和 密码
    sed -i "s|APP_URL=APP_URL|APP_URL=${FINAL_URL}|g" env.conf
    sed -i "s|DB_PASSWORD=DB_PASSWORD|DB_PASSWORD=${USER_DB_PASS}|g" env.conf
    sed -i "s|MYSQL_ROOT_PASSWORD=dujiaoka|MYSQL_ROOT_PASSWORD=${USER_DB_PASS}|g" docker-compose.yml
    sed -i "s|MYSQL_PASSWORD=dujiaoka|MYSQL_PASSWORD=${USER_DB_PASS}|g" docker-compose.yml

    if [ "$IS_IP_MODE" == "true" ]; then
        sed -i "s|- \"80:80\"|- \"${USER_PORT}:80\"|g" docker-compose.yml
        sed -i "s|- \"443:443\"|#- \"443:443\"|g" docker-compose.yml
    fi

    # 写入 HTTPS 配置
    echo "ADMIN_HTTPS=${HTTPS_STATE}" >> env.conf

    echo -e "${GREEN}[4/5] 设置权限...${NC}"
    mkdir -p storage uploads redis-data mysql-data
    chmod -R 777 storage uploads env.conf

    echo -e "${GREEN}[5/5] 启动服务...${NC}"
    docker-compose down 2>/dev/null
    docker-compose up -d

    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}             安装成功！                   ${NC}"
    echo -e "访问地址: ${FINAL_URL}"
    echo -e "数据库密码: ${USER_DB_PASS}"
    echo -e "${GREEN}==========================================${NC}"
}

update_shop() {
    if [ ! -d "$INSTALL_DIR" ]; then echo -e "${RED}[错误] 目录不存在${NC}"; return; fi
    cd "$INSTALL_DIR"
    docker-compose pull
    docker-compose up -d
    # 修复更新后的权限问题
    docker-compose exec web chmod -R 777 storage bootstrap/cache
    docker-compose exec web php artisan optimize:clear
    docker-compose exec web php artisan migrate --force
    echo -e "${GREEN}更新完成！${NC}"
}

uninstall_shop() {
    if [ ! -d "$INSTALL_DIR" ]; then echo -e "${RED}[错误] 目录不存在${NC}"; return; fi
    read -p "确定卸载？(y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" ]]; then return; fi
    cd "$INSTALL_DIR"
    docker-compose down
    cd ..
    rm -rf "$INSTALL_DIR"
    echo -e "${GREEN}卸载完成。${NC}"
}

clear
echo -e "${GREEN}====================================================${NC}"
echo -e "1. 安装独角数卡"
echo -e "2. 更新"
echo -e "3. 卸载"
echo -e "0. 退出"
read -p "请输入: " CHOICE
case $CHOICE in
    1) install_shop ;;
    2) update_shop ;;
    3) uninstall_shop ;;
    0) exit 0 ;;
esac
