#!/bin/bash

# Xray SOCKS5 卸载脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

info() { echo -e "${GREEN}[信息]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1"; }

uninstall_xray() {
    info "停止 Xray 服务..."
    systemctl stop xray 2>/dev/null || true
    systemctl disable xray 2>/dev/null || true
    rm -f /etc/systemd/system/xray.service
    systemctl daemon-reload
    
    info "删除 Xray 文件..."
    rm -f /usr/local/bin/xray
    rm -rf /etc/xray
    rm -rf /usr/local/share/xray
    
    info "清理日志..."
    journalctl --vacuum-time=1d
    
    info "Xray 已完全卸载"
}

main() {
    echo "==============================================================="
    echo "               Xray SOCKS5 代理卸载脚本"
    echo "==============================================================="
    
    read -p "确定要卸载 Xray 吗？此操作不可逆！(y/N): " confirm
    if [[ $confirm == [yY] ]]; then
        uninstall_xray
    else
        info "卸载已取消"
    fi
}

main "$@"
