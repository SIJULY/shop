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
    echo -e "${RED}注意：请确保您的域名已解析到本机 IP，否则 SSL 证书将申请失败！${NC}"
    read -p "请输入您的域名 (例如 shop.test.com): " USER_DOMAIN_INPUT
    read -p "请设置数据库密码 (尽量复杂): " USER_DB_PASS

    if [ -z "$USER_DOMAIN_INPUT" ] || [ -z "$USER_DB_PASS" ]; then
        echo -e "${RED}[错误] 域名或密码不能为空！${NC}"
        return
    fi

    # 移除 http 前缀
    USER_DOMAIN=$(echo "$USER_DOMAIN_INPUT" | sed 's~http[s]*://~~g')

    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${RED}[警告] 检测到安装目录已存在！${NC}"
        read -p "是否覆盖安装？这将导致原有配置丢失 [y/n]: " OVERWRITE
        if [[ "$OVERWRITE" != "y" ]]; then
            echo "已取消安装。"
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
        echo -e "${RED}[错误] 下载失败，请检查 GitHub 地址。${NC}"
        return
    fi

    echo -e "${GREEN}[2/5] 生成 Caddy 配置...${NC}"
    cat > Caddyfile <<EOF
${USER_DOMAIN} {
    reverse_proxy web:80
    encode gzip
}
EOF

    echo -e "${GREEN}[3/5] 配置参数...${NC}"
    # 生成随机 Key
    NEW_APP_KEY="base64:$(openssl rand -base64 32)"
    sed -i "s|APP_KEY=.*|APP_KEY=${NEW_APP_KEY}|g" env.conf
    
    # 替换变量
    sed -i "s|APP_URL=http://你的域名或者IP|APP_URL=https://${USER_DOMAIN}|g" env.conf
    sed -i "s|DB_PASSWORD=你的数据库密码|DB_PASSWORD=${USER_DB_PASS}|g" env.conf
    sed -i "s|MYSQL_ROOT_PASSWORD=你的数据库密码|MYSQL_ROOT_PASSWORD=${USER_DB_PASS}|g" docker-compose.yml
    sed -i "s|MYSQL_PASSWORD=你的数据库密码|MYSQL_PASSWORD=${USER_DB_PASS}|g" docker-compose.yml

    echo -e "${GREEN}[4/5] 设置权限...${NC}"
    mkdir -p storage uploads redis-data mysql-data
    chmod -R 777 storage uploads env.conf

    echo -e "${GREEN}[5/5] 启动服务...${NC}"
    # 停止占用 80 端口的容器
    docker-compose down 2>/dev/null
    docker-compose up -d

    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}             安装成功！                   ${NC}"
    echo -e "访问地址: https://${USER_DOMAIN}"
    echo -e "数据库密码: ${USER_DB_PASS}"
    echo -e "${GREEN}==========================================${NC}"
}

# ====================================================
# 函数：更新
# ====================================================
update_shop() {
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}[错误] 未找到安装目录，请先安装。${NC}"
        return
    fi
    
    cd "$INSTALL_DIR"
    echo -e "${YELLOW}正在更新独角数卡...${NC}"
    
    # 1. 拉取最新镜像
    docker-compose pull
    
    # 2. 重建容器
    docker-compose up -d
    
    # 3. 清理缓存和迁移数据库 (重要步骤)
    echo -e "${YELLOW}正在执行数据库迁移和缓存清理...${NC}"
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

    echo -e "${RED}==========================================${NC}"
    echo -e "${RED}             危险操作警告                 ${NC}"
    echo -e "${RED}==========================================${NC}"
    read -p "确定要卸载吗？(y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" ]]; then
        echo "已取消。"
        return
    fi

    cd "$INSTALL_DIR"
    
    # 停止容器
    echo -e "${YELLOW}正在停止并删除容器...${NC}"
    docker-compose down

    # 询问是否删除数据
    read -p "是否同时删除所有数据（数据库、上传的图片）？[y/n]: " DEL_DATA
    if [[ "$DEL_DATA" == "y" ]]; then
        cd ..
        rm -rf "$INSTALL_DIR"
        echo -e "${GREEN}所有数据已清除。${NC}"
    else
        echo -e "${GREEN}容器已删除，但数据目录 ($INSTALL_DIR) 已保留。${NC}"
    fi
}

# ====================================================
# 主菜单
# ====================================================
clear
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}   独角数卡 (SIJULY版) 一键管理脚本 v4.0    ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "1. 安装独角数卡 (Install)"
echo -e "2. 更新独角数卡 (Update)"
echo -e "3. 卸载独角数卡 (Uninstall)"
echo -e "0. 退出 (Exit)"
echo -e "${GREEN}====================================================${NC}"

read -p "请输入数字 [0-3]: " CHOICE

case $CHOICE in
    1)
        install_shop
        ;;
    2)
        update_shop
        ;;
    3)
        uninstall_shop
        ;;
    0)
        exit 0
        ;;
    *)
        echo -e "${RED}无效输入，退出。${NC}"
        exit 1
        ;;
esac
