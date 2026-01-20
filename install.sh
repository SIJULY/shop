#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}     独角数卡 (SIJULY版) 极速部署脚本 v2.2     ${NC}"
echo -e "${GREEN}====================================================${NC}"

# 0. 检查基础工具
if ! command -v wget &> /dev/null; then
    echo -e "${YELLOW}[系统] 正在安装 wget...${NC}"
    if [ -f /etc/redhat-release ]; then
        yum install -y wget
    elif [ -f /etc/debian_version ]; then
        apt-get update && apt-get install -y wget
    else
        echo -e "${RED}[错误] 无法安装 wget，请手动安装后重试。${NC}"
        exit 1
    fi
fi

if ! command -v openssl &> /dev/null; then
    echo -e "${YELLOW}[系统] 正在安装 openssl (用于生成安全密钥)...${NC}"
    if [ -f /etc/redhat-release ]; then
        yum install -y openssl
    elif [ -f /etc/debian_version ]; then
        apt-get update && apt-get install -y openssl
    fi
fi

# 1. 检查 Docker 环境
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}[系统] 检测到未安装 Docker，正在安装...${NC}"
    curl -fsSL https://get.docker.com | bash -s docker
    systemctl enable docker
    systemctl start docker
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}[系统] 检测到未安装 Docker Compose，正在安装...${NC}"
    curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# 2. 收集用户输入
echo -e "${YELLOW}[配置] 请输入站点配置信息：${NC}"
read -p "请输入您的域名或IP (例如 192.168.1.1 或 shop.test.com): " USER_DOMAIN_INPUT
read -p "请设置数据库密码 (尽量复杂): " USER_DB_PASS

if [ -z "$USER_DOMAIN_INPUT" ] || [ -z "$USER_DB_PASS" ]; then
    echo -e "${RED}[错误] 域名或密码不能为空！${NC}"
    exit 1
fi

# --- 智能处理域名 (移除 http:// 或 https:// 前缀) ---
USER_DOMAIN=$(echo "$USER_DOMAIN_INPUT" | sed 's~http[s]*://~~g')

# 3. 创建目录并下载配置文件
INSTALL_DIR="/root/dujiaoka_sijuly"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo -e "${GREEN}[1/4] 正在从 GitHub 下载配置文件...${NC}"
wget -O docker-compose.yml https://raw.githubusercontent.com/SIJULY/shop/main/docker-compose.yml
wget -O env.conf https://raw.githubusercontent.com/SIJULY/shop/main/env.conf

if [ ! -f "docker-compose.yml" ] || [ ! -f "env.conf" ]; then
    echo -e "${RED}[错误] 配置文件下载失败，请检查 GitHub 仓库地址是否正确。${NC}"
    exit 1
fi

# 4. 替换配置文件中的占位符
echo -e "${GREEN}[2/4] 正在配置环境参数...${NC}"

# --- 核心修改：生成随机安全 APP_KEY ---
echo -e "${YELLOW}[安全] 正在生成随机 APP_KEY...${NC}"
if command -v openssl &> /dev/null; then
    NEW_APP_KEY="base64:$(openssl rand -base64 32)"
else
    # 如果系统没有openssl，使用备用方案生成随机字符串
    NEW_APP_KEY="base64:$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 44)"
fi
# 使用 regex 替换 env.conf 里的默认 Key
sed -i "s|APP_KEY=.*|APP_KEY=${NEW_APP_KEY}|g" env.conf
# ------------------------------------

# 替换 域名 和 密码
sed -i "s|APP_URL=http://你的域名或者IP|APP_URL=http://${USER_DOMAIN}|g" env.conf
sed -i "s|DB_PASSWORD=你的数据库密码|DB_PASSWORD=${USER_DB_PASS}|g" env.conf

# 替换 docker-compose.yml 中的密码
sed -i "s|MYSQL_ROOT_PASSWORD=你的数据库密码|MYSQL_ROOT_PASSWORD=${USER_DB_PASS}|g" docker-compose.yml
sed -i "s|MYSQL_PASSWORD=你的数据库密码|MYSQL_PASSWORD=${USER_DB_PASS}|g" docker-compose.yml

# 5. 设置权限
echo -e "${GREEN}[3/4] 初始化目录权限...${NC}"
mkdir -p storage uploads redis-data mysql-data
chmod -R 777 storage uploads
chmod 777 env.conf

# 6. 启动容器
echo -e "${GREEN}[4/4] 正在启动容器...${NC}"
docker-compose up -d

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}                部署完成！                  ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "访问地址: http://${USER_DOMAIN}:8080"
echo -e "数据库密码: ${USER_DB_PASS}"
echo -e "安装目录: ${INSTALL_DIR}"
echo -e "${YELLOW}请记得在云服务器防火墙放行 8080 端口！${NC}"
