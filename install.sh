#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}      独角数卡 (Dujiaoka) 智能互动安装脚本 v1.0      ${NC}"
echo -e "${GREEN}   集成 HTTPS 修复、Caddy 配置与 Docker 环境搭建   ${NC}"
echo -e "${GREEN}====================================================${NC}"

# 1. 收集信息
echo -e "${YELLOW}[Step 1] 配置基本信息${NC}"

# 安装目录
read -p "请输入安装目录 (默认: /root/data/docker_data/shop): " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-/root/data/docker_data/shop}

# 域名
read -p "请输入您的域名 (例如 shop.sijuly.nyc.mn): " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}错误：域名不能为空！${NC}"
    exit 1
fi

# 数据库密码
read -p "请设置数据库密码 (尽量复杂): " DB_PASS
if [ -z "$DB_PASS" ]; then
    echo -e "${RED}错误：密码不能为空！${NC}"
    exit 1
fi

# Caddy配置
read -p "请输入 Caddyfile 文件的绝对路径 (默认: /opt/cloud_manager/Caddyfile): " CADDY_FILE
CADDY_FILE=${CADDY_FILE:-/opt/cloud_manager/Caddyfile}

read -p "请输入 Caddy 反代指向的宿主机 IP (默认: 10.0.0.192): " HOST_IP
HOST_IP=${HOST_IP:-10.0.0.192}

# 2. 创建目录
echo -e "${YELLOW}[Step 2] 创建目录与设置权限...${NC}"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
mkdir -p storage uploads
chmod -R 777 storage uploads
touch env.conf
chmod -R 777 env.conf

# 3. 生成 docker-compose.yml
echo -e "${YELLOW}[Step 3] 生成 docker-compose.yml...${NC}"
cat > docker-compose.yml <<EOF
version: "3"

services:
  web:
    image: stilleshan/dujiaoka
    container_name: shop_web
    environment:
        - INSTALL=true
        - MODIFY=true
    volumes:
      - ./env.conf:/dujiaoka/.env
      - ./uploads:/dujiaoka/public/uploads
      - ./storage:/dujiaoka/storage
    ports:
      - 8090:80
    restart: always
    networks:
      - shop_net

  db:
    image: mariadb:focal
    container_name: shop_db
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=${DB_PASS}
      - MYSQL_DATABASE=dujiaoka
      - MYSQL_USER=dujiaoka
      - MYSQL_PASSWORD=${DB_PASS}
    volumes:
      - ./mysql:/var/lib/mysql
    networks:
      - shop_net

  redis:
    image: redis:alpine
    container_name: shop_redis
    restart: always
    volumes:
      - ./redis:/data
    networks:
      - shop_net

networks:
  shop_net:
    driver: bridge
EOF

# 4. 生成 env.conf
echo -e "${YELLOW}[Step 4] 生成 env.conf (预设 HTTPS 修复配置)...${NC}"
cat > env.conf <<EOF
APP_NAME=独角数卡
APP_ENV=local
APP_KEY=base64:rKwRuI6eRpCw/9e2XZKKGj/Yx3iZy5e7+FQ6+aQl8Zg=
APP_DEBUG=true
APP_URL=https://${DOMAIN}

LOG_CHANNEL=stack

# 数据库配置
DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=dujiaoka
DB_USERNAME=dujiaoka
DB_PASSWORD=${DB_PASS}

# Redis配置
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

# 强制开启后台 HTTPS (解决 0 Error)
ADMIN_HTTPS=true
# 信任所有代理 (解决重定向问题)
TRUSTPROXIES=*
EOF

# 5. 启动 Docker
echo -e "${YELLOW}[Step 5] 启动容器...${NC}"
docker-compose up -d

# 等待几秒确保容器启动
echo "等待容器初始化 (5秒)..."
sleep 5

# 6. 代码级修复 (核心步骤)
echo -e "${YELLOW}[Step 6] 执行代码级修复 (解决 405 Method Not Allowed)...${NC}"

# 修复 AppServiceProvider.php
docker exec shop_web bash -c "cat > /dujiaoka/app/Providers/AppServiceProvider.php <<EOF
<?php
namespace App\Providers;
use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Facades\Schema;

class AppServiceProvider extends ServiceProvider
{
    public function register() {}
    public function boot()
    {
        \URL::forceScheme('https');
        \Schema::defaultStringLength(191);
    }
}
EOF"

# 修复 TrustProxies.php
docker exec shop_web bash -c "cat > /dujiaoka/app/Http/Middleware/TrustProxies.php <<EOF
<?php
namespace App\Http\Middleware;
use Illuminate\Http\Request;
use Fideloper\Proxy\TrustProxies as Middleware;

class TrustProxies extends Middleware
{
    protected \$proxies = '*';
    protected \$headers = Request::HEADER_X_FORWARDED_ALL;
}
EOF"

# 清理缓存
echo -e "${YELLOW}[Step 7] 清理 Laravel 缓存...${NC}"
docker exec shop_web php artisan optimize:clear
docker exec shop_web php artisan config:clear

# 7. 配置 Caddy
echo -e "${YELLOW}[Step 8] 配置 Caddy...${NC}"
if [ -f "$CADDY_FILE" ]; then
    # 检查域名是否已存在，防止重复添加
    if grep -q "$DOMAIN" "$CADDY_FILE"; then
        echo -e "${RED}警告：Caddyfile 中似乎已存在该域名，跳过添加。${NC}"
    else
        echo -e "\n# === 站点: 独角数卡 (Auto Added) ===" >> "$CADDY_FILE"
        echo -e "${DOMAIN} {" >> "$CADDY_FILE"
        echo -e "    reverse_proxy ${HOST_IP}:8090" >> "$CADDY_FILE"
        echo -e "}" >> "$CADDY_FILE"
        echo "已将配置追加到 $CADDY_FILE"
        
        # 尝试重载 Caddy
        CADDY_DIR=$(dirname "$CADDY_FILE")
        echo "正在尝试重载 Caddy (目录: $CADDY_DIR)..."
        # 尝试 docker compose 方式
        if [ -f "$CADDY_DIR/docker-compose.yml" ]; then
            cd "$CADDY_DIR" && docker compose exec caddy caddy reload || docker compose restart
        else
            # 尝试系统命令
            systemctl reload caddy 2>/dev/null || echo -e "${RED}无法自动重载 Caddy，请稍后手动重载！${NC}"
        fi
    fi
else
    echo -e "${RED}未找到 Caddyfile，请手动配置反向代理！${NC}"
fi

# 8. 生成锁定脚本
cd "$INSTALL_DIR"
cat > lock_shop.sh <<EOF
#!/bin/bash
# 独角数卡安全加固脚本
echo "正在执行安全加固..."
sed -i 's/INSTALL=true/INSTALL=false/g' docker-compose.yml
sed -i 's/APP_DEBUG=true/APP_DEBUG=false/g' env.conf
docker-compose up -d
docker exec shop_web php artisan config:clear
echo "加固完成！安装模式已关闭，调试模式已关闭。"
EOF
chmod +x lock_shop.sh

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}                  安装准备就绪！                     ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "1. 请立即访问: ${YELLOW}https://${DOMAIN}${NC}"
echo -e "2. 填写数据库信息："
echo -e "   - 地址: ${YELLOW}db${NC}"
echo -e "   - 数据库名: ${YELLOW}dujiaoka${NC}"
echo -e "   - 用户名: ${YELLOW}dujiaoka${NC}"
echo -e "   - 密码: ${YELLOW}${DB_PASS}${NC}"
echo -e "   - Redis地址: ${YELLOW}redis${NC}"
echo -e "3. 点击安装，记录管理员账号密码。"
echo -e "4. ${RED}【非常重要】${NC}安装完成后，回到这里运行: ${YELLOW}./lock_shop.sh${NC}"
echo -e "${GREEN}====================================================${NC}"
