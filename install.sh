#!/bin/bash

# Xray SOCKS5 一键安装脚本
# GitHub: https://github.com/你的用户名/xray-socks5-installer

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置参数（可自定义）
SOCKS_PORT=${SOCKS_PORT:-87}
SOCKS_USER=${SOCKS_USER:-8888}
SOCKS_PASS=${SOCKS_PASS:-8888}
XRAY_VERSION="1.8.11"

# 输出颜色信息
info() { echo -e "${BLUE}[信息]${NC} $1"; }
success() { echo -e "${GREEN}[成功]${NC} $1"; }
warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1"; }

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
    
    # 获取服务器IP
    SERVER_IP=$(curl -s http://checkip.amazonaws.com || hostname -I | awk '{print $1}')
    
    mkdir -p /etc/xray
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
    SERVER_IP=$(curl -s http://checkip.amazonaws.com || hostname -I | awk '{print $1}')
    
    echo ""
    echo "==============================================================="
    echo "                  Xray SOCKS5 安装完成！"
    echo "==============================================================="
    echo "服务器IP: $SERVER_IP"
    echo "端口: $SOCKS_PORT"
    echo "用户名: $SOCKS_USER"
    echo "密码: $SOCKS_PASS"
    echo "协议: SOCKS5"
    echo "支持UDP: 是"
    echo ""
    echo "==============================================================="
    echo "                   使用方法"
    echo "==============================================================="
    echo "在代理客户端中配置:"
    echo "- 服务器: $SERVER_IP"
    echo "- 端口: $SOCKS_PORT"
    echo "- 用户名: $SOCKS_USER"
    echo "- 密码: $SOCKS_PASS"
    echo "- 协议: SOCKS5"
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
    echo "卸载: bash -c \"\$(wget -q -O- https://raw.githubusercontent.com/你的用户名/xray-socks5-installer/main/uninstall.sh)\""
    echo "==============================================================="
}

# 主函数
main() {
    clear
    echo "==============================================================="
    echo "               Xray SOCKS5 代理一键安装脚本"
    echo "==============================================================="
    
    # 显示配置信息
    info "默认配置:"
    echo "  - 端口: $SOCKS_PORT"
    echo "  - 用户名: $SOCKS_USER"
    echo "  - 密码: $SOCKS_PASS"
    echo ""
    
    # 确认安装
    read -p "是否继续安装? (y/N): " confirm
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
