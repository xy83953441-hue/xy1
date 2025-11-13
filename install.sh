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
INSTALL_PASSWORD="sock5"

# 配置参数（将在安装过程中设置）
SOCKS_PORT=""
SOCKS_USER=""
SOCKS_PASS=""
XRAY_VERSION="1.8.11"

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

# 配置 SOCKS5 认证信息
configure_socks5() {
    echo ""
    info "请配置 SOCKS5 代理认证信息"
    echo "==============================================================="
    
    # 端口配置
    while true; do
        read -p "请输入 SOCKS5 端口 [默认: 87]: " input_port
        if [[ -z "$input_port" ]]; then
            SOCKS_PORT="87"
            break
        elif [[ "$input_port" =~ ^[0-9]+$ ]] && [ "$input_port" -ge 1 ] && [ "$input_port" -le 65535 ]; then
            SOCKS_PORT="$input_port"
            break
        else
            error "端口必须是 1-65535 之间的数字"
        fi
    done
    
    # 用户名配置
    while true; do
        read -p "请输入 SOCKS5 用户名 [默认: 8888]: " input_user
        if [[ -z "$input_user" ]]; then
            SOCKS_USER="8888"
            break
        elif [[ -n "$input_user" ]]; then
            SOCKS_USER="$input_user"
            break
        else
            error "用户名不能为空"
        fi
    done
    
    # 密码配置（安全输入）
    while true; do
        read -sp "请输入 SOCKS5 密码 [默认: 8888]: " input_pass
        echo
        if [[ -z "$input_pass" ]]; then
            SOCKS_PASS="8888"
            break
        else
            read -sp "请再次输入密码确认: " input_pass_confirm
            echo
            if [[ "$input_pass" == "$input_pass_confirm" ]]; then
                SOCKS_PASS="$input_pass"
                break
            else
                error "两次输入的密码不一致，请重新输入"
            fi
        fi
    done
    
    # 显示配置摘要（密码用*号隐藏）
    echo ""
    info "配置摘要:"
    echo "  - 端口: $SOCKS_PORT"
    echo "  - 用户名: $SOCKS_USER"
    echo "  - 密码: $(echo "$SOCKS_PASS" | sed 's/./*/g')"
    echo ""
    
    read -p "确认使用以上配置? (y/N): " confirm
    if [[ $confirm != [yY] ]]; then
        info "重新配置..."
        configure_socks5
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

    # 设置配置文件权限，保护密码
    chmod 600 /etc/xray/config.json
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
    echo "密码: *** (已安全保存)"
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
    echo "- 密码: (您设置的密码)"
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
    echo "==============================================================="
    echo "                   安全提示"
    echo "==============================================================="
    echo "- 密码已安全保存在配置文件中"
    echo "- 配置文件权限已设置为 600 (仅root可访问)"
    echo "- 请妥善保管您的认证信息"
    echo ""
    echo "卸载: bash -c \"\$(wget -q -O- https://raw.githubusercontent.com/xy83953441-hue/xy1/main/uninstall.sh)\""
    echo "==============================================================="
}

# 主函数
main() {
    clear
    
    # 验证安装口令
    verify_password
    
    # 配置 SOCKS5 认证信息
    configure_socks5
    
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
