#!/bin/bash

# Xray SOCKS5 一键安装脚本
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/xy83953441-hue/xy1/main/install.sh)"

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 安装口令
INSTALL_PASSWORD="socks"

# 默认配置参数
SOCKS_PORT="87"
SOCKS_USER="xy8395"
SOCKS_PASS="xy8395"
XRAY_VERSION="1.8.11"

# 全局变量
IP_COUNT=0
declare -a IP_ARRAY

# 输出颜色信息
info() { echo -e "${BLUE}[信息]${NC} $1"; }
success() { echo -e "${GREEN}[成功]${NC} $1"; }
warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1"; }

# 验证安装口令
verify_password() {
    local attempts=0
    local max_attempts=3
    
    echo "==============================================================="
    echo "               Xray SOCKS5 代理一键安装脚本"
    echo "==============================================================="
    echo ""
    warning "此安装程序需要验证口令才能继续"
    echo ""
    
    while [ $attempts -lt $max_attempts ]; do
        read -sp "请输入安装口令: " input_password
        echo
        
        if [ "$input_password" == "$INSTALL_PASSWORD" ]; then
            success "口令验证成功，开始安装..."
            echo ""
            return 0
        else
            attempts=$((attempts + 1))
            remaining=$((max_attempts - attempts))
            error "口令错误！剩余尝试次数: $remaining"
            
            if [ $remaining -eq 0 ]; then
                error "验证失败，安装程序退出"
                exit 1
            fi
        fi
    done
}

# 检查系统IP数量
check_ip_count() {
    info "检测服务器IP地址..."
    
    # 获取所有IP地址
    ALL_IPS=$(hostname -I)
    IP_ARRAY=($ALL_IPS)
    IP_COUNT=${#IP_ARRAY[@]}
    
    info "检测到 $IP_COUNT 个IP地址:"
    for i in "${!IP_ARRAY[@]}"; do
        echo "  IP$((i+1)): ${IP_ARRAY[i]}"
    done
    echo ""
    
    # 检查IP数量限制
    if [ $IP_COUNT -gt 10 ]; then
        warning "检测到超过10个IP地址，这可能影响性能"
        read -p "是否继续安装? (y/N): " confirm
        if [[ $confirm != [yY] ]]; then
            info "安装已取消"
            exit 0
        fi
    fi
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 检查系统
check_system() {
    info "检测系统信息..."
    if [[ -f /etc/redhat-release ]]; then
        SYSTEM="centos"
    elif grep -Eqi "debian" /etc/issue; then
        SYSTEM="debian"
    elif grep -Eqi "ubuntu" /etc/issue; then
        SYSTEM="ubuntu"
    else
        error "不支持的系统"
        exit 1
    fi
    info "检测到系统: $SYSTEM"
}

# 安装依赖
install_dependencies() {
    info "安装必要依赖..."
    if [[ $SYSTEM == "centos" ]]; then
        yum update -y
        yum install -y wget curl unzip iptables
    else
        apt update -y
        apt install -y wget curl unzip iptables
    fi
}

# 清理防火墙规则
clean_iptables() {
    info "清理防火墙规则..."
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -t nat -F
    iptables -t mangle -F
    iptables -F
    iptables -X
    iptables-save
}

# 下载 Xray
download_xray() {
    info "下载 Xray v${XRAY_VERSION}..."
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="64" ;;
        aarch64) ARCH="arm64-v8a" ;;
        armv7l) ARCH="arm32-v7a" ;;
        *) error "不支持的架构: $ARCH"; exit 1 ;;
    esac
    
    XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-${ARCH}.zip"
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    cd $TEMP_DIR
    
    # 下载
    if ! wget -q -O xray.zip $XRAY_URL; then
        error "下载 Xray 失败"
        exit 1
    fi
    
    # 解压
    if ! unzip -q xray.zip xray geoip.dat geosite.dat; then
        error "解压失败"
        exit 1
    fi
    
    # 安装文件
    mkdir -p /usr/local/bin /usr/local/share/xray
    cp xray /usr/local/bin/
    cp geoip.dat geosite.dat /usr/local/share/xray/
    chmod +x /usr/local/bin/xray
    
    # 清理
    cd /
    rm -rf $TEMP_DIR
}

# 创建系统服务
create_service() {
    info "创建系统服务..."
    
    cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray
}

# 生成配置文件
create_config() {
    info "生成配置文件..."
    
    # 重新获取IP信息
    ALL_IPS=$(hostname -I)
    IP_ARRAY=($ALL_IPS)
    IP_COUNT=${#IP_ARRAY[@]}
    
    # 获取公网IP
    PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || echo "${IP_ARRAY[0]}")
    
    mkdir -p /etc/xray
    
    # 创建多IP配置文件
    if [ $IP_COUNT -gt 1 ]; then
        info "检测到多个IP，创建多IP配置..."
        create_multi_ip_config
    else
        info "创建单IP配置..."
        create_single_ip_config
    fi

    # 设置配置文件权限，保护密码
    chmod 600 /etc/xray/config.json
}

# 创建单IP配置
create_single_ip_config() {
    cat <<EOF > /etc/xray/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "socks-in",
      "port": $SOCKS_PORT,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "$SOCKS_USER",
            "pass": "$SOCKS_PASS"
          }
        ],
        "udp": true,
        "ip": "0.0.0.0"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF
}

# 创建多IP配置
create_multi_ip_config() {
    # 获取所有IP
    ALL_IPS=$(hostname -I)
    IP_ARRAY=($ALL_IPS)
    
    # 开始创建配置文件
    echo '{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [' > /etc/xray/config.json
    
    # 为每个IP创建inbound配置
    for i in "${!IP_ARRAY[@]}"; do
        if [ $i -gt 0 ]; then
            echo "," >> /etc/xray/config.json
        fi
        cat <<EOF >> /etc/xray/config.json
    {
      "tag": "socks-in-${IP_ARRAY[i]//./_}",
      "port": $((SOCKS_PORT + i)),
      "listen": "${IP_ARRAY[i]}",
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "$SOCKS_USER",
            "pass": "$SOCKS_PASS"
          }
        ],
        "udp": true,
        "ip": "${IP_ARRAY[i]}"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
EOF
    done
    
    # 添加outbounds和routing
    cat <<EOF >> /etc/xray/config.json
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF
}

# 启动服务
start_service() {
    info "启动 Xray 服务..."
    systemctl stop xray 2>/dev/null || true
    systemctl start xray
    sleep 2
    
    if systemctl is-active --quiet xray; then
        success "Xray 服务启动成功"
    else
        error "Xray 服务启动失败"
        systemctl status xray
        exit 1
    fi
}

# 显示安装信息
show_info() {
    ALL_IPS=$(hostname -I)
    IP_ARRAY=($ALL_IPS)
    IP_COUNT=${#IP_ARRAY[@]}
    PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || echo "${IP_ARRAY[0]}")
    
    echo ""
    echo "==============================================================="
    echo "                  Xray SOCKS5 安装完成！"
    echo "==============================================================="
    echo "默认配置:"
    echo "  - 端口: $SOCKS_PORT"
    echo "  - 用户名: $SOCKS_USER"
    echo "  - 密码: $SOCKS_PASS"
    echo ""
    
    if [ $IP_COUNT -gt 1 ]; then
        echo "多IP配置详情:"
        for i in "${!IP_ARRAY[@]}"; do
            echo "  - IP$((i+1)): ${IP_ARRAY[i]} : $((SOCKS_PORT + i))"
        done
    else
        echo "服务器IP: $PUBLIC_IP"
    fi
    
    echo ""
    echo "协议: SOCKS5"
    echo "支持UDP: 是"
    echo ""
    echo "==============================================================="
    echo "                   使用方法"
    echo "==============================================================="
    echo "在代理客户端中配置:"
    if [ $IP_COUNT -gt 1 ]; then
        echo "多IP选择:"
        for i in "${!IP_ARRAY[@]}"; do
            echo "- 服务器: ${IP_ARRAY[i]}"
            echo "- 端口: $((SOCKS_PORT + i))"
            echo "- 用户名: $SOCKS_USER"
            echo "- 密码: $SOCKS_PASS"
            echo "- 协议: SOCKS5"
            echo ""
        done
    else
        echo "- 服务器: $PUBLIC_IP"
        echo "- 端口: $SOCKS_PORT"
        echo "- 用户名: $SOCKS_USER"
        echo "- 密码: $SOCKS_PASS"
        echo "- 协议: SOCKS5"
    fi
    echo ""
    echo "==============================================================="
    echo "                   管理命令"
    echo "==============================================================="
    echo "启动: systemctl start xray"
    echo "停止: systemctl stop xray"
    echo "重启: systemctl restart xray"
    echo "状态: systemctl status xray"
    echo "日志: journalctl -u xray -f"
    echo ""
    echo "==============================================================="
    echo "                   IP 数量分析"
    echo "==============================================================="
    echo "当前服务器IP数量: $IP_COUNT"
    if [ $IP_COUNT -gt 10 ]; then
        warning "高IP数量警告: 检测到 $IP_COUNT 个IP，这可能会影响性能"
        echo "建议: 考虑使用负载均衡或减少使用的IP数量"
    elif [ $IP_COUNT -gt 5 ]; then
        info "中等IP数量: $IP_COUNT 个IP，性能正常"
    else
        success "低IP数量: $IP_COUNT 个IP，性能最佳"
    fi
    echo ""
    echo "卸载: bash -c \"\$(wget -q -O- https://raw.githubusercontent.com/xy83953441-hue/xy1/main/uninstall.sh)\""
    echo "==============================================================="
}

# 主函数
main() {
    clear
    
    # 验证安装口令
    verify_password
    
    # 显示默认配置
    info "使用默认SOCKS5配置:"
    echo "  - 端口: $SOCKS_PORT"
    echo "  - 用户名: $SOCKS_USER"
    echo "  - 密码: $SOCKS_PASS"
    echo ""
    
    # 检查IP数量
    check_ip_count
    
    # 确认安装
    read -p "是否开始安装? (y/N): " confirm
    if [[ $confirm != [yY] ]]; then
        info "安装已取消"
        exit 0
    fi
    
    # 执行安装步骤
    check_root
    check_system
    install_dependencies
    clean_iptables
    download_xray
    create_config
    create_service
    start_service
    show_info
}

# 运行主函数
main "$@"
