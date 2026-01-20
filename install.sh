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

    # 清洗输入，移除 http/https 前缀
    RAW_INPUT=$(echo "$USER_INPUT" | sed 's~http[s]*://~~g')
    
    # 判断是 IP 还是 域名
    # 使用正则判断是否符合 IP 格式 (简单判断)
    if [[ $RAW_INPUT =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        IS_IP_MODE="true"
        echo -e "${YELLOW}[识别] 检测到您使用的是 IP 模式。${NC}"
        read -p "请输入访问端口 (默认 8080): " USER_PORT
        USER_PORT=${USER_PORT:-8080}
        
        # IP 模式配置
        FINAL_URL="http://${RAW_INPUT}:${USER_PORT}"
        HTTPS_STATE="false"
        CADDY_CONFIG=":80" # 容器内部 Caddy 监听 80 (HTTP)
        
        echo -e "将在端口 ${GREEN}${USER_PORT}${NC} 上部署 HTTP 服务。"
    else
        IS_IP_MODE="false"
        echo -e "${YELLOW}[识别] 检测到您使用的是 域名 模式。${NC}"
        echo -e "${RED}注意：请确保域名已解析到本机，否则 SSL 申请失败！${NC}"
        USER_PORT=80
        
        # 域名模式配置
        FINAL_URL="https://${RAW_INPUT}"
        HTTPS_STATE="true"
        CADDY_CONFIG="${RAW_INPUT}" # Caddy 自动申请 HTTPS
        
        echo -e "将在端口 ${GREEN}80/443${NC} 上部署 HTTPS 服务。"
    fi

    # 检查目录
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${RED}[警告] 检测到安装目录已存在！${NC}"
        read -p "是否覆盖安装？(y/n): " OVERWRITE
        if [[ "$OVERWRITE" != "y" ]]; then
            echo "已取消。"
            return
        fi
        rm -rf "$INSTALL_DIR"
    fi

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    echo -e "${GREEN}[1/5] 下载配置文件...${NC}"
    wget -O docker-compose.yml https://raw.githubusercontent.com/SIJULY/shop/main/docker-compose.yml
    wget -O env.conf https://raw.githubusercontent.com/SIJULY/shop/main/env.conf

    if [ ! -f "docker-compose.yml" ]; then
        echo -e "${RED}[错误] 下载失败。${NC}"
        return
    fi

    echo -e "${GREEN}[2/5] 生成 Caddy 配置...${NC}"
    # 根据模式生成不同的 Caddyfile
    if [ "$IS_IP_MODE" == "true" ]; then
        # IP 模式：监听 :80 (HTTP)，反代到 web
        cat > Caddyfile <<EOF
${CADDY_CONFIG} {
    reverse_proxy web:80
}
EOF
    else
        # 域名模式：监听域名 (自动HTTPS)，开启 gzip
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
    sed -i "s|APP_KEY=.*|APP_KEY=${NEW_APP_KEY}|g" env.conf
    
    # 替换 URL 和 密码
    sed -i "s|APP_URL=http://你的域名或者IP|APP_URL=${FINAL_URL}|g" env.conf
    sed -i "s|DB_PASSWORD=你的数据库密码|DB_PASSWORD=${USER_DB_PASS}|g" env.conf
    sed -i "s|MYSQL_ROOT_PASSWORD=你的数据库密码|MYSQL_ROOT_PASSWORD=${USER_DB_PASS}|g" docker-compose.yml
    sed -i "s|MYSQL_PASSWORD=你的数据库密码|MYSQL_PASSWORD=${USER_DB_PASS}|g" docker-compose.yml

    # ---------------------------------------------------------
    # 动态端口映射修改 (Docker Compose)
    # ---------------------------------------------------------
    if [ "$IS_IP_MODE" == "true" ]; then
        # 如果是 IP 模式，修改 80:80 为 用户端口:80
        sed -i "s|- \"80:80\"|- \"${USER_PORT}:80\"|g" docker-compose.yml
        # 如果是 IP 模式，注释掉 443 端口映射 (防止占用或报错)
        sed -i "s|- \"443:443\"|#- \"443:443\"|g" docker-compose.yml
    fi

    # ---------------------------------------------------------
    # 智能 HTTPS 开关 (解决 0 Error 或 循环重定向)
    # ---------------------------------------------------------
    # 先清除旧配置（如果有）
    sed -i "/ADMIN_HTTPS/d" env.conf
    # 追加新配置
    echo "" >> env.conf
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
    if [ "$IS_IP_MODE" == "true" ]; then
        echo -e "${YELLOW}当前为 IP 模式 (HTTP)，请确保防火墙已放行端口 ${USER_PORT}${NC}"
    fi
    echo -e "${GREEN}==========================================${NC}"
}

# ====================================================
# 函数：更新
# ====================================================
update_shop() {
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}[错误] 未找到安装目录。${NC}"
        return
    fi
    cd "$INSTALL_DIR"
    echo -e "${YELLOW}正在更新...${NC}"
    docker-compose pull
    docker-compose up -d
    echo -e "${YELLOW}清理缓存并迁移数据库...${NC}"
    docker-compose exec web php artisan optimize:clear
    docker-compose exec web php artisan migrate --force
    echo -e "${GREEN}更新完成！${NC}"
}

# ====================================================
# 函数：卸载
# ====================================================
uninstall_shop() {
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}[错误] 未找到安装目录。${NC}"
        return
    fi
    echo -e "${RED}警告：即将卸载独角数卡！${NC}"
    read -p "确定要卸载吗？(y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" ]]; then return; fi
    
    cd "$INSTALL_DIR"
    docker-compose down
    
    read -p "是否删除所有数据？[y/n]: " DEL_DATA
    if [[ "$DEL_DATA" == "y" ]]; then
        cd ..
        rm -rf "$INSTALL_DIR"
        echo -e "${GREEN}数据已清除。${NC}"
    else
        echo -e "${GREEN}数据已保留。${NC}"
    fi
}

# ====================================================
# 主菜单
# ====================================================
clear
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}   独角数卡 (SIJULY版) 智能双模部署脚本 v4.2    ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "1. 安装独角数卡 (支持 域名HTTPS / IP端口模式)"
echo -e "2. 更新独角数卡"
echo -e "3. 卸载独角数卡"
echo -e "0. 退出"
echo -e "${GREEN}====================================================${NC}"

read -p "请输入数字 [0-3]: " CHOICE

case $CHOICE in
    1) install_shop ;;
    2) update_shop ;;
    3) uninstall_shop ;;
    0) exit 0 ;;
    *) echo "无效输入" ;;
esac
