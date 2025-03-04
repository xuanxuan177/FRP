#!/bin/bash
#
# FRP内网穿透管理脚本 v1.0
# 支持Mac和Linux系统，适用于服务器端和客户端配置
# 可以管理多个端口和多应用
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

# 全局变量
OS_TYPE=""
IS_SERVER=false
FRP_VERSION=""
FRP_DIR=""
FRP_CONFIG=""
FRP_BINARY=""
SERVICE_NAME=""

# 检测系统类型
detect_os() {
    echo -e "${CYAN}正在检测系统类型...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="mac"
        FRP_DIR="$HOME/frp"
        echo -e "${GREEN}检测到Mac系统${NC}"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS_TYPE="linux"
        if [ "$(id -u)" -ne 0 ]; then
            echo -e "${RED}错误: 在Linux系统上需要root权限，请使用sudo运行此脚本${NC}"
            exit 1
        fi
        FRP_DIR="/etc/frp"
        echo -e "${GREEN}检测到Linux系统${NC}"
    else
        echo -e "${RED}错误: 不支持的系统类型 $OSTYPE${NC}"
        exit 1
    fi
}

# 检查工具是否已安装
check_command() {
    command -v "$1" >/dev/null 2>&1
}

# 安装依赖工具
install_dependencies() {
    echo -e "${CYAN}正在检查必要的依赖...${NC}"
    
    if ! check_command curl; then
        echo -e "${YELLOW}未检测到curl，正在安装...${NC}"
        if [[ "$OS_TYPE" == "mac" ]]; then
            if check_command brew; then
                brew install curl
            else
                echo -e "${RED}请先安装Homebrew: https://brew.sh${NC}"
                exit 1
            fi
        elif [[ "$OS_TYPE" == "linux" ]]; then
            if check_command apt-get; then
                apt-get update && apt-get install -y curl
            elif check_command yum; then
                yum install -y curl
            else
                echo -e "${RED}未找到包管理器，请手动安装curl${NC}"
                exit 1
            fi
        fi
    fi
    
    if ! check_command jq; then
        echo -e "${YELLOW}未检测到jq，正在安装...${NC}"
        if [[ "$OS_TYPE" == "mac" ]]; then
            if check_command brew; then
                brew install jq
            fi
        elif [[ "$OS_TYPE" == "linux" ]]; then
            if check_command apt-get; then
                apt-get update && apt-get install -y jq
            elif check_command yum; then
                yum install -y jq
            fi
        fi
    fi
    
    if ! check_command nc; then
        echo -e "${YELLOW}未检测到netcat，正在安装...${NC}"
        if [[ "$OS_TYPE" == "mac" ]]; then
            if check_command brew; then
                brew install netcat
            fi
        elif [[ "$OS_TYPE" == "linux" ]]; then
            if check_command apt-get; then
                apt-get update && apt-get install -y netcat
            elif check_command yum; then
                yum install -y nc
            fi
        fi
    fi
    
    echo -e "${GREEN}所有依赖已安装${NC}"
}

# 获取最新版FRP
get_latest_frp_version() {
    echo -e "${CYAN}正在获取FRP最新版本...${NC}"
    if check_command curl && check_command jq; then
        FRP_VERSION=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | jq -r .tag_name)
        if [[ -z "$FRP_VERSION" || "$FRP_VERSION" == "null" ]]; then
            FRP_VERSION="v0.51.3" # 回退到默认版本
            echo -e "${YELLOW}无法获取最新版本，使用默认版本 ${FRP_VERSION}${NC}"
        else
            echo -e "${GREEN}获取到最新版本: ${FRP_VERSION}${NC}"
        fi
    else
        FRP_VERSION="v0.51.3" # 默认版本
        echo -e "${YELLOW}缺少curl或jq，使用默认版本 ${FRP_VERSION}${NC}"
    fi
}

# 下载并安装FRP
download_and_install_frp() {
    local role=$1 # server或client
    local arch="amd64"
    local os_name=""
    
    echo -e "${CYAN}准备下载并安装FRP ${role}...${NC}"
    
    # 确定操作系统名称
    if [[ "$OS_TYPE" == "mac" ]]; then
        os_name="darwin"
    elif [[ "$OS_TYPE" == "linux" ]]; then
        os_name="linux"
    fi
    
    # 确定架构
    if [[ "$(uname -m)" == "arm64" ]]; then
        arch="arm64"
    fi
    
    # 确定目标目录和权限
    if [[ "$OS_TYPE" == "mac" ]]; then
        mkdir -p "$FRP_DIR"
    elif [[ "$OS_TYPE" == "linux" ]]; then
        mkdir -p "$FRP_DIR"
        chmod 755 "$FRP_DIR"
    fi
    
    # 下载文件
    local download_url="https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/frp_${FRP_VERSION:1}_${os_name}_${arch}.tar.gz"
    local temp_file="/tmp/frp.tar.gz"
    
    echo -e "${CYAN}正在从 ${download_url} 下载FRP...${NC}"
    if ! curl -L "$download_url" -o "$temp_file"; then
        echo -e "${RED}下载失败，请检查网络连接或版本号${NC}"
        exit 1
    fi
    
    # 解压文件
    echo -e "${CYAN}正在解压文件...${NC}"
    mkdir -p "/tmp/frp_temp"
    tar -xzf "$temp_file" -C "/tmp/frp_temp" --strip-components 1
    
    # 复制相关文件
    if [[ "$role" == "server" ]]; then
        IS_SERVER=true
        if [[ "$OS_TYPE" == "linux" ]]; then
            cp "/tmp/frp_temp/frps" "/usr/local/bin/frps"
            chmod +x "/usr/local/bin/frps"
            FRP_BINARY="/usr/local/bin/frps"
        else
            cp "/tmp/frp_temp/frps" "$FRP_DIR/frps"
            chmod +x "$FRP_DIR/frps"
            FRP_BINARY="$FRP_DIR/frps"
        fi
        cp "/tmp/frp_temp/frps.toml" "$FRP_DIR/frps.toml.example"
        FRP_CONFIG="$FRP_DIR/frps.toml"
        SERVICE_NAME="frps"
    else
        IS_SERVER=false
        if [[ "$OS_TYPE" == "linux" ]]; then
            cp "/tmp/frp_temp/frpc" "/usr/local/bin/frpc"
            chmod +x "/usr/local/bin/frpc"
            FRP_BINARY="/usr/local/bin/frpc"
        else
            cp "/tmp/frp_temp/frpc" "$FRP_DIR/frpc"
            chmod +x "$FRP_DIR/frpc"
            FRP_BINARY="$FRP_DIR/frpc"
        fi
        cp "/tmp/frp_temp/frpc.toml" "$FRP_DIR/frpc.toml.example"
        FRP_CONFIG="$FRP_DIR/frpc.toml"
        SERVICE_NAME="frpc"
    fi
    
    # 清理临时文件
    rm -rf "/tmp/frp_temp" "$temp_file"
    
    echo -e "${GREEN}FRP ${role} 安装完成${NC}"
}

# 生成随机密码
generate_random_password() {
    local length=$1
    if check_command openssl; then
        openssl rand -base64 48 | head -c "$length"
    else
        head /dev/urandom | tr -dc A-Za-z0-9 | head -c "$length"
    fi
}

# 配置服务器
configure_server() {
    echo -e "${CYAN}配置FRP服务器...${NC}"
    
    # 请求服务器端口
    local bind_port
    while true; do
        read -rp "$(echo -e $YELLOW)请输入FRP服务器监听端口 [7000]: $(echo -e $NC)" bind_port
        bind_port=${bind_port:-7000}
        if [[ "$bind_port" =~ ^[0-9]+$ ]] && [ "$bind_port" -ge 1 ] && [ "$bind_port" -le 65535 ]; then
            if check_port_available "$bind_port"; then
                break
            else
                echo -e "${RED}端口 $bind_port 已被占用，请选择其他端口${NC}"
            fi
        else
            echo -e "${RED}请输入有效的端口号 (1-65535)${NC}"
        fi
    done
    
    # 请求控制面板端口
    local dashboard_port
    while true; do
        read -rp "$(echo -e $YELLOW)请输入控制面板端口 [7500]: $(echo -e $NC)" dashboard_port
        dashboard_port=${dashboard_port:-7500}
        if [[ "$dashboard_port" =~ ^[0-9]+$ ]] && [ "$dashboard_port" -ge 1 ] && [ "$dashboard_port" -le 65535 ]; then
            if [ "$dashboard_port" -ne "$bind_port" ]; then
                if check_port_available "$dashboard_port"; then
                    break
                else
                    echo -e "${RED}端口 $dashboard_port 已被占用，请选择其他端口${NC}"
                fi
            else
                echo -e "${RED}控制面板端口不能与服务器监听端口相同${NC}"
            fi
        else
            echo -e "${RED}请输入有效的端口号 (1-65535)${NC}"
        fi
    done
    
    # 请求控制面板用户名和密码
    local dashboard_user
    read -rp "$(echo -e $YELLOW)请输入控制面板用户名 [admin]: $(echo -e $NC)" dashboard_user
    dashboard_user=${dashboard_user:-admin}
    
    local dashboard_pwd
    local default_pwd=$(generate_random_password 12)
    read -rp "$(echo -e $YELLOW)请输入控制面板密码 [$default_pwd]: $(echo -e $NC)" dashboard_pwd
    dashboard_pwd=${dashboard_pwd:-$default_pwd}
    
    # 请求身份验证令牌
    local auth_token
    local default_token=$(generate_random_password 16)
    read -rp "$(echo -e $YELLOW)请输入身份验证令牌 [$default_token]: $(echo -e $NC)" auth_token
    auth_token=${auth_token:-$default_token}
    
    # 请求允许的端口范围
    local allow_ports
    read -rp "$(echo -e $YELLOW)请输入允许的端口范围 [6000-7000]: $(echo -e $NC)" allow_ports
    allow_ports=${allow_ports:-6000-7000}
    
    # 创建配置文件
    cat > "$FRP_CONFIG" << EOL
# FRP服务器端配置文件 (frps.toml)
# 由FRP管理脚本生成

[common]
# 基础配置
bind_port = ${bind_port}
bind_addr = "0.0.0.0"

# 控制面板配置
dashboard_port = ${dashboard_port}
dashboard_addr = "0.0.0.0"
dashboard_user = "${dashboard_user}"
dashboard_pwd = "${dashboard_pwd}"

# 认证配置
authentication_method = "token"
token = "${auth_token}"

# 日志配置
log_file = "/var/log/frps.log"
log_level = "info"
log_max_days = 3

# 端口配置
allow_ports = [${allow_ports}]
EOL
    
    echo -e "${GREEN}服务器配置文件已创建: $FRP_CONFIG${NC}"
    
    # 配置防火墙
    configure_firewall "$bind_port" "$dashboard_port" "$allow_ports"
    
    # 创建系统服务
    create_system_service "server"
    
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${GREEN}FRP服务器配置完成!${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${YELLOW}服务器端口:${NC} $bind_port"
    echo -e "${YELLOW}控制面板:${NC} http://服务器IP:$dashboard_port"
    echo -e "${YELLOW}用户名:${NC} $dashboard_user"
    echo -e "${YELLOW}密码:${NC} $dashboard_pwd"
    echo -e "${YELLOW}身份验证令牌:${NC} $auth_token"
    echo -e "${YELLOW}允许的端口范围:${NC} $allow_ports"
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${YELLOW}请保存上述信息，客户端配置需要使用这些参数${NC}"
    echo -e "${BLUE}=============================================${NC}"
}

# 配置客户端
configure_client() {
    echo -e "${CYAN}配置FRP客户端...${NC}"
    
    # 请求服务器地址和端口
    local server_addr
    read -rp "$(echo -e $YELLOW)请输入FRP服务器IP地址: $(echo -e $NC)" server_addr
    if [[ -z "$server_addr" ]]; then
        echo -e "${RED}服务器地址不能为空${NC}"
        return
    fi
    
    local server_port
    read -rp "$(echo -e $YELLOW)请输入FRP服务器端口 [7000]: $(echo -e $NC)" server_port
    server_port=${server_port:-7000}
    
    # 请求身份验证令牌
    local auth_token
    read -rp "$(echo -e $YELLOW)请输入身份验证令牌: $(echo -e $NC)" auth_token
    if [[ -z "$auth_token" ]]; then
        echo -e "${RED}身份验证令牌不能为空${NC}"
        return
    fi
    
    # 创建配置文件
    cat > "$FRP_CONFIG" << EOL
# FRP客户端配置文件 (frpc.toml)
# 由FRP管理脚本生成

[common]
# 服务器配置
server_addr = "${server_addr}"
server_port = ${server_port}

# 认证配置
authentication_method = "token"
token = "${auth_token}"

# 日志配置
log_file = "$FRP_DIR/frpc.log"
log_level = "info"
log_max_days = 3
EOL
    
    echo -e "${GREEN}客户端基础配置文件已创建: $FRP_CONFIG${NC}"
    
    # 创建系统服务
    create_system_service "client"
    
    # 添加第一个代理
    add_proxy
    
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${GREEN}FRP客户端配置完成!${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${YELLOW}服务器地址:${NC} $server_addr:$server_port"
    echo -e "${YELLOW}客户端配置文件:${NC} $FRP_CONFIG"
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${YELLOW}您可以随时使用此脚本管理代理${NC}"
    echo -e "${BLUE}=============================================${NC}"
}

# 添加代理
add_proxy() {
    echo -e "${CYAN}添加新的代理配置...${NC}"
    
    # 请求代理名称
    local proxy_name
    while true; do
        read -rp "$(echo -e $YELLOW)请输入代理名称(英文字母和数字): $(echo -e $NC)" proxy_name
        if [[ $proxy_name =~ ^[a-zA-Z0-9_]+$ ]]; then
            # 检查是否已存在
            if grep -q "^\[${proxy_name}\]" "$FRP_CONFIG"; then
                echo -e "${RED}代理名称 '$proxy_name' 已存在，请使用其他名称${NC}"
            else
                break
            fi
        else
            echo -e "${RED}代理名称只能包含英文字母、数字和下划线${NC}"
        fi
    done
    
    # 请求代理类型
    local proxy_type
    echo -e "${BLUE}选择代理类型:${NC}"
    echo -e "1) TCP - 适用于大多数应用"
    echo -e "2) HTTP - 适用于网站"
    echo -e "3) HTTPS - 适用于安全网站"
    echo -e "4) UDP - 适用于游戏、视频通话等"
    
    while true; do
        read -rp "$(echo -e $YELLOW)请输入选项 [1-4]: $(echo -e $NC)" proxy_type_option
        case $proxy_type_option in
            1) proxy_type="tcp"; break ;;
            2) proxy_type="http"; break ;;
            3) proxy_type="https"; break ;;
            4) proxy_type="udp"; break ;;
            *) echo -e "${RED}请输入有效的选项 (1-4)${NC}" ;;
        esac
    done
    
    # 本地配置
    local local_ip
    read -rp "$(echo -e $YELLOW)请输入本地IP地址 [127.0.0.1]: $(echo -e $NC)" local_ip
    local_ip=${local_ip:-127.0.0.1}
    
    local local_port
    while true; do
        read -rp "$(echo -e $YELLOW)请输入本地端口: $(echo -e $NC)" local_port
        if [[ "$local_port" =~ ^[0-9]+$ ]] && [ "$local_port" -ge 1 ] && [ "$local_port" -le 65535 ]; then
            break
        else
            echo -e "${RED}请输入有效的端口号 (1-65535)${NC}"
        fi
    done
    
    # 远程配置
    if [[ "$proxy_type" == "tcp" || "$proxy_type" == "udp" ]]; then
        local remote_port
        while true; do
            read -rp "$(echo -e $YELLOW)请输入远程端口: $(echo -e $NC)" remote_port
            if [[ "$remote_port" =~ ^[0-9]+$ ]] && [ "$remote_port" -ge 1 ] && [ "$remote_port" -le 65535 ]; then
                break
            else
                echo -e "${RED}请输入有效的端口号 (1-65535)${NC}"
            fi
        done
        
        # 添加代理配置
        cat >> "$FRP_CONFIG" << EOL

[${proxy_name}]
type = "${proxy_type}"
local_ip = "${local_ip}"
local_port = ${local_port}
remote_port = ${remote_port}
EOL
        
        echo -e "${GREEN}添加了${proxy_type}代理: ${proxy_name}${NC}"
        echo -e "${YELLOW}本地: ${local_ip}:${local_port} -> 远程: 服务器IP:${remote_port}${NC}"
        
    elif [[ "$proxy_type" == "http" || "$proxy_type" == "https" ]]; then
        local custom_domains
        read -rp "$(echo -e $YELLOW)请输入自定义域名(多个域名用逗号分隔): $(echo -e $NC)" custom_domains
        
        # 添加代理配置
        cat >> "$FRP_CONFIG" << EOL

[${proxy_name}]
type = "${proxy_type}"
local_ip = "${local_ip}"
local_port = ${local_port}
custom_domains = "${custom_domains}"
EOL
        
        echo -e "${GREEN}添加了${proxy_type}代理: ${proxy_name}${NC}"
        echo -e "${YELLOW}本地: ${local_ip}:${local_port} -> 远程: ${custom_domains}${NC}"
    fi
    
    # 重启服务以应用更改
    if check_service_status; then
        restart_service
        echo -e "${GREEN}服务已重启，新代理配置已生效${NC}"
    else
        echo -e "${YELLOW}请手动启动服务以应用新配置${NC}"
    fi
}

# 列出代理
list_proxies() {
    echo -e "${CYAN}当前配置的代理:${NC}"
    
    if [[ ! -f "$FRP_CONFIG" ]]; then
        echo -e "${RED}配置文件 $FRP_CONFIG 不存在${NC}"
        return
    fi
    
    local in_proxy=false
    local proxy_count=0
    local proxy_name=""
    
    echo -e "${BLUE}+------------------+--------+----------------+----------------+${NC}"
    echo -e "${BLUE}| 代理名称         | 类型   | 本地地址       | 远程地址       |${NC}"
    echo -e "${BLUE}+------------------+--------+----------------+----------------+${NC}"
    
    while IFS= read -r line; do
        # 检查是否是代理段落开始
        if [[ $line =~ ^\[(.*)\]$ && ! $line =~ ^\[common\]$ ]]; then
            in_proxy=true
            proxy_count=$((proxy_count + 1))
            proxy_name=$(echo "$line" | sed -E 's/^\[(.*)\]$/\1/')
            proxy_type=""
            local_ip=""
            local_port=""
            remote_port=""
            custom_domains=""
        elif [[ $in_proxy == true ]]; then
            if [[ $line =~ ^type\ *=\ *\"(.*)\"$ ]]; then
                proxy_type="${BASH_REMATCH[1]}"
            elif [[ $line =~ ^local_ip\ *=\ *\"(.*)\"$ ]]; then
                local_ip="${BASH_REMATCH[1]}"
            elif [[ $line =~ ^local_port\ *=\ *([0-9]+)$ ]]; then
                local_port="${BASH_REMATCH[1]}"
            elif [[ $line =~ ^remote_port\ *=\ *([0-9]+)$ ]]; then
                remote_port="${BASH_REMATCH[1]}"
            elif [[ $line =~ ^custom_domains\ *=\ *\"(.*)\"$ ]]; then
                custom_domains="${BASH_REMATCH[1]}"
            elif [[ $line =~ ^\[.*\]$ || $line =~ ^$ ]]; then
                # 处理完一个代理，输出信息
                if [[ -n "$proxy_name" && -n "$proxy_type" ]]; then
                    local local_addr="${local_ip}:${local_port}"
                    local remote_addr=""
                    
                    if [[ "$proxy_type" == "tcp" || "$proxy_type" == "udp" ]]; then
                        remote_addr="服务器:${remote_port}"
                    elif [[ "$proxy_type" == "http" || "$proxy_type" == "https" ]]; then
                        remote_addr="${custom_domains}"
                    fi
                    
                    printf "${NC}| %-16s | %-6s | %-14s | %-14s |${NC}\n" "$proxy_name" "$proxy_type" "$local_addr" "$remote_addr"
                fi
                
                in_proxy=false
                proxy_name=""
            fi
        fi
    done < "$FRP_CONFIG"
    
    # 处理最后一个代理
    if [[ $in_proxy == true && -n "$proxy_name" && -n "$proxy_type" ]]; then
        local local_addr="${local_ip}:${local_port}"
        local remote_addr=""
        
        if [[ "$proxy_type" == "tcp" || "$proxy_type" == "udp" ]]; then
            remote_addr="服务器:${remote_port}"
        elif [[ "$proxy_type" == "http" || "$proxy_type" == "https" ]]; then
            remote_addr="${custom_domains}"
        fi
        
        printf "${NC}| %-16s | %-6s | %-14s | %-14s |${NC}\n" "$proxy_name" "$proxy_type" "$local_addr" "$remote_addr"
    fi
    
    echo -e "${BLUE}+------------------+--------+----------------+----------------+${NC}"
    
    if [[ $proxy_count -eq 0 ]]; then
        echo -e "${YELLOW}未找到任何代理配置${NC}"
    else
        echo -e "${GREEN}共找到 $proxy_count 个代理配置${NC}"
    fi
}

# 删除代理
delete_proxy() {
    if [[ ! -f "$FRP_CONFIG" ]]; then
        echo -e "${RED}配置文件 $FRP_CONFIG 不存在${NC}"
        return
    fi
    
    list_proxies
    
    echo -e "${CYAN}删除代理配置${NC}"
    read -rp "$(echo -e $YELLOW)请输入要删除的代理名称: $(echo -e $NC)" proxy_name
    
    if [[ -z "$proxy_name" ]]; then
        echo -e "${RED}代理名称不能为空${NC}"
        return
    fi
    
    if ! grep -q "^\[${proxy_name}\]$" "$FRP_CONFIG"; then
        echo -e "${RED}代理 '$proxy_name' 不存在${NC}"
        return
    fi
    
    # 创建临时文件
    local temp_file=$(mktemp)
    
    # 删除代理配置
    local in_proxy=false
    while IFS= read -r line; do
        if [[ $line =~ ^\[${proxy_name}\]$ ]]; then
            in_proxy=true
        elif [[ $in_proxy == true && ($line =~ ^\[.*\]$ || $line =~ ^$) ]]; then
            in_proxy=false
            # 只有当下一行是新的配置段或空行时，才将该行写入临时文件
            if [[ $line =~ ^\[.*\]$ ]]; then
                echo "$line" >> "$temp_file"
            fi
            continue
        fi
        
        if [[ $in_proxy == false ]]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$FRP_CONFIG"
    
    # 用临时文件替换原配置文件
    mv "$temp_file" "$FRP_CONFIG"
    
    echo -e "${GREEN}已删除代理 '$proxy_name'${NC}"
    
    # 重启服务以应用更改
    if check_service_status; then
        restart_service
        echo -e "${GREEN}服务已重启，配置更改已生效${NC}"
    else
        echo -e "${YELLOW}请手动启动服务以应用新配置${NC}"
    fi
}

# 检查端口是否可用
check_port_available() {
    local port=$1
    if [[ "$OS_TYPE" == "mac" ]]; then
        nc -z localhost "$port" 2>/dev/null
        if [ $? -eq 0 ]; then
            return 1
        else
            return 0
        fi
    elif [[ "$OS_TYPE" == "linux" ]]; then
        netstat -tuln | grep -q ":$port "
        if [ $? -eq 0 ]; then
            return 1
        else
            return 0
        fi
    fi
}

# 配置防火墙
configure_firewall() {
    if [[ "$OS_TYPE" != "linux" ]]; then
        return
    fi
    
    local bind_port=$1
    local dashboard_port=$2
    local port_range=$3
    
    echo -e "${CYAN}配置防火墙规则...${NC}"
    
    # 检查使用的防火墙类型
    if command -v ufw >/dev/null 2>&1; then
        echo -e "${CYAN}检测到UFW防火墙...${NC}"
        
        # 添加端口规则
        ufw allow "$bind_port/tcp" comment "FRP服务器端口"
        ufw allow "$dashboard_port/tcp" comment "FRP控制面板端口"
        
        # 添加端口范围
        if [[ -n "$port_range" ]]; then
            local start_port=$(echo "$port_range" | cut -d'-' -f1)
            local end_port=$(echo "$port_range" | cut -d'-' -f2)
            ufw allow "$start_port:$end_port/tcp" comment "FRP允许的端口范围"
            ufw allow "$start_port:$end_port/udp" comment "FRP允许的端口范围(UDP)"
        fi
        
        # 确保UFW已启用
        if ! ufw status | grep -q "Status: active"; then
            echo -e "${YELLOW}UFW防火墙当前未启用${NC}"
            read -rp "$(echo -e $YELLOW)是否启用UFW防火墙? (y/n): $(echo -e $NC)" enable_ufw
            if [[ "$enable_ufw" == "y" || "$enable_ufw" == "Y" ]]; then
                ufw --force enable
                echo -e "${GREEN}UFW防火墙已启用${NC}"
            fi
        fi
        
    elif command -v firewall-cmd >/dev/null 2>&1; then
        echo -e "${CYAN}检测到firewalld防火墙...${NC}"
        
        # 添加端口规则
        firewall-cmd --permanent --add-port="$bind_port/tcp" --zone=public
        firewall-cmd --permanent --add-port="$dashboard_port/tcp" --zone=public
        
        # 添加端口范围
        if [[ -n "$port_range" ]]; then
            local start_port=$(echo "$port_range" | cut -d'-' -f1)
            local end_port=$(echo "$port_range" | cut -d'-' -f2)
            firewall-cmd --permanent --add-port="$start_port-$end_port/tcp" --zone=public
            firewall-cmd --permanent --add-port="$start_port-$end_port/udp" --zone=public
        fi
        
        # 重新加载防火墙
        firewall-cmd --reload
        
    elif command -v iptables >/dev/null 2>&1; then
        echo -e "${CYAN}使用iptables配置防火墙...${NC}"
        
        # 添加端口规则
        iptables -A INPUT -p tcp --dport "$bind_port" -j ACCEPT
        iptables -A INPUT -p tcp --dport "$dashboard_port" -j ACCEPT
        
        # 添加端口范围
        if [[ -n "$port_range" ]]; then
            local start_port=$(echo "$port_range" | cut -d'-' -f1)
            local end_port=$(echo "$port_range" | cut -d'-' -f2)
            iptables -A INPUT -p tcp --match multiport --dports "$start_port:$end_port" -j ACCEPT
            iptables -A INPUT -p udp --match multiport --dports "$start_port:$end_port" -j ACCEPT
        fi
        
        # 提示保存规则
        echo -e "${YELLOW}请注意: iptables规则在重启后会丢失，请确保保存规则${NC}"
        echo -e "${YELLOW}您可以使用 'iptables-save > /etc/iptables/rules.v4' 保存规则${NC}"
    else
        echo -e "${YELLOW}未检测到支持的防火墙系统，请手动配置防火墙规则${NC}"
    fi
    
    echo -e "${GREEN}防火墙配置完成${NC}"
}

# 创建系统服务
create_system_service() {
    local role=$1  # server or client
    
    if [[ "$OS_TYPE" == "linux" ]]; then
        # 创建systemd服务
        if [[ -d "/etc/systemd/system" ]]; then
            echo -e "${CYAN}创建systemd服务...${NC}"
            
            local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
            local service_desc="FRP Server"
            local exec_cmd="$FRP_BINARY -c $FRP_CONFIG"
            
            if [[ "$role" == "client" ]]; then
                service_desc="FRP Client"
            fi
            
            cat > "$service_file" << EOL
[Unit]
Description=${service_desc}
After=network.target

[Service]
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=${exec_cmd}
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOL
            
            # 重新加载systemd
            systemctl daemon-reload
            systemctl enable "${SERVICE_NAME}.service"
            systemctl start "${SERVICE_NAME}.service"
            
            echo -e "${GREEN}systemd服务已创建并启动${NC}"
            
        elif [[ -d "/etc/init.d" ]]; then
            # 创建init.d服务脚本
            echo -e "${CYAN}创建init.d服务...${NC}"
            
            local service_file="/etc/init.d/${SERVICE_NAME}"
            local service_desc="FRP Server"
            local exec_cmd="$FRP_BINARY -c $FRP_CONFIG"
            
            if [[ "$role" == "client" ]]; then
                service_desc="FRP Client"
            fi
            
            cat > "$service_file" << EOL
#!/bin/sh
### BEGIN INIT INFO
# Provides:          ${SERVICE_NAME}
# Required-Start:    $network $remote_fs $local_fs
# Required-Stop:     $network $remote_fs $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: ${service_desc}
# Description:       Start or stop the ${service_desc}
### END INIT INFO

NAME="${SERVICE_NAME}"
DAEMON="${exec_cmd}"
PIDFILE="/var/run/${SERVICE_NAME}.pid"

[ -x "\$DAEMON" ] || exit 0

case "\$1" in
  start)
    echo "Starting \$NAME"
    start-stop-daemon --start --background --make-pidfile --pidfile \$PIDFILE --exec \$DAEMON
    ;;
  stop)
    echo "Stopping \$NAME"
    start-stop-daemon --stop --pidfile \$PIDFILE
    rm -f \$PIDFILE
    ;;
  restart)
    \$0 stop
    \$0 start
    ;;
  *)
    echo "Usage: \$0 {start|stop|restart}"
    exit 1
    ;;
esac

exit 0
EOL
            
            chmod +x "$service_file"
            update-rc.d "${SERVICE_NAME}" defaults
            service "${SERVICE_NAME}" start
            
            echo -e "${GREEN}init.d服务已创建并启动${NC}"
        else
            echo -e "${YELLOW}未找到systemd或init.d，无法创建系统服务${NC}"
            echo -e "${YELLOW}请手动运行：${exec_cmd}${NC}"
        fi
        
    elif [[ "$OS_TYPE" == "mac" ]]; then
        # 创建Mac的launchd服务
        echo -e "${CYAN}创建macOS启动服务...${NC}"
        
        local plist_path="$HOME/Library/LaunchAgents/com.frp.${SERVICE_NAME}.plist"
        local plist_label="com.frp.${SERVICE_NAME}"
        local program_path="$FRP_BINARY"
        local program_args=("-c" "$FRP_CONFIG")
        
        mkdir -p "$HOME/Library/LaunchAgents"
        
        cat > "$plist_path" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${plist_label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${program_path}</string>
        <string>-c</string>
        <string>${FRP_CONFIG}</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>${FRP_DIR}/${SERVICE_NAME}.err</string>
    <key>StandardOutPath</key>
    <string>${FRP_DIR}/${SERVICE_NAME}.log</string>
</dict>
</plist>
EOL
        
        launchctl unload "$plist_path" 2>/dev/null || true
        launchctl load -w "$plist_path"
        
        echo -e "${GREEN}macOS启动服务已创建并启动${NC}"
    fi
}

# 检查服务状态
check_service_status() {
    if [[ "$OS_TYPE" == "linux" ]]; then
        if command -v systemctl >/dev/null 2>&1; then
            systemctl is-active --quiet "${SERVICE_NAME}.service"
            return $?
        elif [[ -f "/etc/init.d/${SERVICE_NAME}" ]]; then
            service "${SERVICE_NAME}" status >/dev/null 2>&1
            return $?
        else
            pgrep -f "$FRP_BINARY" >/dev/null 2>&1
            return $?
        fi
    elif [[ "$OS_TYPE" == "mac" ]]; then
        local plist_label="com.frp.${SERVICE_NAME}"
        launchctl list | grep -q "$plist_label"
        return $?
    fi
}

# 启动服务
start_service() {
    echo -e "${CYAN}启动FRP服务...${NC}"
    
    if [[ "$OS_TYPE" == "linux" ]]; then
        if command -v systemctl >/dev/null 2>&1; then
            systemctl start "${SERVICE_NAME}.service"
        elif [[ -f "/etc/init.d/${SERVICE_NAME}" ]]; then
            service "${SERVICE_NAME}" start
        else
            nohup "$FRP_BINARY" -c "$FRP_CONFIG" >/dev/null 2>&1 &
        fi
    elif [[ "$OS_TYPE" == "mac" ]]; then
        local plist_path="$HOME/Library/LaunchAgents/com.frp.${SERVICE_NAME}.plist"
        launchctl load -w "$plist_path"
    fi
    
    # 检查服务是否成功启动
    sleep 2
    if check_service_status; then
        echo -e "${GREEN}FRP服务已成功启动${NC}"
    else
        echo -e "${RED}FRP服务启动失败，请检查日志${NC}"
    fi
}

# 停止服务
stop_service() {
    echo -e "${CYAN}停止FRP服务...${NC}"
    
    if [[ "$OS_TYPE" == "linux" ]]; then
        if command -v systemctl >/dev/null 2>&1; then
            systemctl stop "${SERVICE_NAME}.service"
        elif [[ -f "/etc/init.d/${SERVICE_NAME}" ]]; then
            service "${SERVICE_NAME}" stop
        else
            pkill -f "$FRP_BINARY"
        fi
    elif [[ "$OS_TYPE" == "mac" ]]; then
        local plist_path="$HOME/Library/LaunchAgents/com.frp.${SERVICE_NAME}.plist"
        launchctl unload "$plist_path"
    fi
    
    # 检查服务是否成功停止
    sleep 2
    if ! check_service_status; then
        echo -e "${GREEN}FRP服务已成功停止${NC}"
    else
        echo -e "${RED}FRP服务停止失败${NC}"
    fi
}

# 重启服务
restart_service() {
    echo -e "${CYAN}重启FRP服务...${NC}"
    
    if [[ "$OS_TYPE" == "linux" ]]; then
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart "${SERVICE_NAME}.service"
        elif [[ -f "/etc/init.d/${SERVICE_NAME}" ]]; then
            service "${SERVICE_NAME}" restart
        else
            pkill -f "$FRP_BINARY"
            sleep 1
            nohup "$FRP_BINARY" -c "$FRP_CONFIG" >/dev/null 2>&1 &
        fi
    elif [[ "$OS_TYPE" == "mac" ]]; then
        local plist_path="$HOME/Library/LaunchAgents/com.frp.${SERVICE_NAME}.plist"
        launchctl unload "$plist_path"
        sleep 1
        launchctl load -w "$plist_path"
    fi
    
    # 检查服务是否成功重启
    sleep 2
    if check_service_status; then
        echo -e "${GREEN}FRP服务已成功重启${NC}"
    else
        echo -e "${RED}FRP服务重启失败，请检查日志${NC}"
    fi
}

# 显示服务状态
show_service_status() {
    echo -e "${CYAN}FRP服务状态:${NC}"
    
    if [[ ! -f "$FRP_CONFIG" ]]; then
        echo -e "${RED}未找到配置文件 $FRP_CONFIG${NC}"
        return
    fi
    
    local status="未运行"
    if check_service_status; then
        status="${GREEN}正在运行${NC}"
    else
        status="${RED}已停止${NC}"
    fi
    
    echo -e "服务状态: $status"
    
    if [[ "$IS_SERVER" == true ]]; then
        local bind_port=$(grep -oP "bind_port\s*=\s*\K[0-9]+" "$FRP_CONFIG")
        local dashboard_port=$(grep -oP "dashboard_port\s*=\s*\K[0-9]+" "$FRP_CONFIG")
        
        echo -e "服务器端口: ${YELLOW}$bind_port${NC}"
        echo -e "控制面板地址: ${YELLOW}http://$(get_public_ip):$dashboard_port${NC}"
    else
        local server_addr=$(grep -oP "server_addr\s*=\s*\"*\K[^\"]*" "$FRP_CONFIG")
        local server_port=$(grep -oP "server_port\s*=\s*\K[0-9]+" "$FRP_CONFIG")
        
        echo -e "服务器地址: ${YELLOW}$server_addr:$server_port${NC}"
    fi
    
    # 显示日志的最后几行
    if [[ "$IS_SERVER" == true && -f "/var/log/frps.log" ]]; then
        echo -e "\n${CYAN}最新日志:${NC}"
        tail -n 10 "/var/log/frps.log"
    elif [[ -f "$FRP_DIR/${SERVICE_NAME}.log" ]]; then
        echo -e "\n${CYAN}最新日志:${NC}"
        tail -n 10 "$FRP_DIR/${SERVICE_NAME}.log"
    fi
}

# 获取公共IP
get_public_ip() {
    local public_ip
    
    if check_command curl; then
        public_ip=$(curl -s https://api.ipify.org)
    elif check_command wget; then
        public_ip=$(wget -qO- https://api.ipify.org)
    else
        public_ip="无法获取"
    fi
    
    echo "$public_ip"
}

# 检查FRP配置是否存在
check_frp_config() {
    if [[ "$IS_SERVER" == true ]]; then
        if [[ -f "$FRP_CONFIG" ]]; then
            return 0
        else
            return 1
        fi
    else
        if [[ -f "$FRP_CONFIG" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

# 检查FRP是否已安装
check_frp_installed() {
    if [[ "$IS_SERVER" == true ]]; then
        if [[ "$OS_TYPE" == "linux" && -f "/usr/local/bin/frps" ]]; then
            FRP_BINARY="/usr/local/bin/frps"
            return 0
        elif [[ "$OS_TYPE" == "mac" && -f "$FRP_DIR/frps" ]]; then
            FRP_BINARY="$FRP_DIR/frps"
            return 0
        else
            return 1
        fi
    else
        if [[ "$OS_TYPE" == "linux" && -f "/usr/local/bin/frpc" ]]; then
            FRP_BINARY="/usr/local/bin/frpc"
            return 0
        elif [[ "$OS_TYPE" == "mac" && -f "$FRP_DIR/frpc" ]]; then
            FRP_BINARY="$FRP_DIR/frpc"
            return 0
        else
            return 1
        fi
    fi
}

# 确定角色
determine_role() {
    echo -e "${CYAN}请选择要配置的角色:${NC}"
    echo -e "1) 服务器端 - 在具有公网IP的服务器上运行"
    echo -e "2) 客户端 - 在需要被访问的本地计算机上运行"
    
    local choice
    while true; do
        read -rp "$(echo -e $YELLOW)请输入选项 [1-2]: $(echo -e $NC)" choice
        case $choice in
            1)
                IS_SERVER=true
                SERVICE_NAME="frps"
                if [[ "$OS_TYPE" == "linux" ]]; then
                    FRP_CONFIG="$FRP_DIR/frps.toml"
                    if check_frp_installed; then
                        FRP_BINARY="/usr/local/bin/frps"
                    fi
                else
                    FRP_CONFIG="$FRP_DIR/frps.toml"
                    if check_frp_installed; then
                        FRP_BINARY="$FRP_DIR/frps"
                    fi
                fi
                break
                ;;
            2)
                IS_SERVER=false
                SERVICE_NAME="frpc"
                if [[ "$OS_TYPE" == "linux" ]]; then
                    FRP_CONFIG="$FRP_DIR/frpc.toml"
                    if check_frp_installed; then
                        FRP_BINARY="/usr/local/bin/frpc"
                    fi
                else
                    FRP_CONFIG="$FRP_DIR/frpc.toml"
                    if check_frp_installed; then
                        FRP_BINARY="$FRP_DIR/frpc"
                    fi
                fi
                break
                ;;
            *)
                echo -e "${RED}请输入有效的选项 (1-2)${NC}"
                ;;
        esac
    done
}

# 显示主菜单
show_main_menu() {
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${PURPLE}        FRP 内网穿透管理脚本 v1.0${NC}"
    echo -e "${BLUE}=============================================${NC}"
    
    local role_str="客户端"
    if [[ "$IS_SERVER" == true ]]; then
        role_str="服务器端"
    fi
    
    echo -e "${CYAN}当前角色:${NC} $role_str"
    
    if check_frp_config; then
        echo -e "${GREEN}配置文件已存在:${NC} $FRP_CONFIG"
    else
        echo -e "${YELLOW}配置文件不存在${NC}"
    fi
    
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${CYAN}请选择操作:${NC}"
    
    echo -e "1) 全新安装FRP"
    
    if check_frp_installed; then
        if [[ "$IS_SERVER" == false ]]; then
            echo -e "2) 管理代理配置"
            echo -e "3) 查看代理列表"
            echo -e "4) 添加新代理"
            echo -e "5) 删除代理"
        fi
        
        echo -e "6) 启动FRP服务"
        echo -e "7) 停止FRP服务"
        echo -e "8) 重启FRP服务"
        echo -e "9) 查看服务状态"
    fi
    
    echo -e "c) 切换角色"
    echo -e "q) 退出"
    echo -e "${BLUE}=============================================${NC}"
}

# 管理代理配置菜单
proxy_management_menu() {
    while true; do
        echo -e "${BLUE}=============================================${NC}"
        echo -e "${PURPLE}        FRP 代理管理${NC}"
        echo -e "${BLUE}=============================================${NC}"
        echo -e "${CYAN}请选择操作:${NC}"
        echo -e "1) 查看代理列表"
        echo -e "2) 添加新代理"
        echo -e "3) 删除代理"
        echo -e "4) 返回主菜单"
        echo -e "${BLUE}=============================================${NC}"
        
        local choice
        read -rp "$(echo -e $YELLOW)请输入选项: $(echo -e $NC)" choice
        case $choice in
            1)
                list_proxies
                ;;
            2)
                add_proxy
                ;;
            3)
                delete_proxy
                ;;
            4|b|back)
                return
                ;;
            *)
                echo -e "${RED}请输入有效的选项${NC}"
                ;;
        esac
        
        echo
        read -rp "$(echo -e $YELLOW)按Enter键继续...$(echo -e $NC)" _
    done
}

# 主入口函数
main() {
    clear
    echo -e "${PURPLE}欢迎使用FRP内网穿透管理脚本${NC}"
    echo -e "${CYAN}此脚本将帮助您设置和管理FRP服务${NC}"
    
    detect_os
    install_dependencies
    determine_role
    
    while true; do
        clear
        show_main_menu
        
        local choice
        read -rp "$(echo -e $YELLOW)请输入选项: $(echo -e $NC)" choice
        case $choice in
            1)
                # 全新安装
                get_latest_frp_version
                if [[ "$IS_SERVER" == true ]]; then
                    download_and_install_frp "server"
                    configure_server
                else
                    download_and_install_frp "client"
                    configure_client
                fi
                ;;
            2)
                # 管理代理配置
                if [[ "$IS_SERVER" == false && -f "$FRP_CONFIG" ]]; then
                    proxy_management_menu
                else
                    echo -e "${RED}此选项仅适用于客户端${NC}"
                    sleep 2
                fi
                ;;
            3)
                # 查看代理列表
                if [[ "$IS_SERVER" == false && -f "$FRP_CONFIG" ]]; then
                    list_proxies
                    read -rp "$(echo -e $YELLOW)按Enter键继续...$(echo -e $NC)" _
                else
                    echo -e "${RED}此选项仅适用于客户端${NC}"
                    sleep 2
                fi
                ;;
            4)
                # 添加新代理
                if [[ "$IS_SERVER" == false && -f "$FRP_CONFIG" ]]; then
                    add_proxy
                    read -rp "$(echo -e $YELLOW)按Enter键继续...$(echo -e $NC)" _
                else
                    echo -e "${RED}此选项仅适用于客户端${NC}"
                    sleep 2
                fi
                ;;
            5)
                # 删除代理
                if [[ "$IS_SERVER" == false && -f "$FRP_CONFIG" ]]; then
                    delete_proxy
                    read -rp "$(echo -e $YELLOW)按Enter键继续...$(echo -e $NC)" _
                else
                    echo -e "${RED}此选项仅适用于客户端${NC}"
                    sleep 2
                fi
                ;;
            6)
                # 启动FRP服务
                if check_frp_installed; then
                    start_service
                    read -rp "$(echo -e $YELLOW)按Enter键继续...$(echo -e $NC)" _
                else
                    echo -e "${RED}FRP尚未安装${NC}"
                    sleep 2
                fi
                ;;
            7)
                # 停止FRP服务
                if check_frp_installed; then
                    stop_service
                    read -rp "$(echo -e $YELLOW)按Enter键继续...$(echo -e $NC)" _
                else
                    echo -e "${RED}FRP尚未安装${NC}"
                    sleep 2
                fi
                ;;
            8)
                # 重启FRP服务
                if check_frp_installed; then
                    restart_service
                    read -rp "$(echo -e $YELLOW)按Enter键继续...$(echo -e $NC)" _
                else
                    echo -e "${RED}FRP尚未安装${NC}"
                    sleep 2
                fi
                ;;
            9)
                # 查看服务状态
                if check_frp_installed; then
                    show_service_status
                    read -rp "$(echo -e $YELLOW)按Enter键继续...$(echo -e $NC)" _
                else
                    echo -e "${RED}FRP尚未安装${NC}"
                    sleep 2
                fi
                ;;
            c)
                # 切换角色
                determine_role
                ;;
            q|quit|exit)
                echo -e "${GREEN}感谢使用FRP内网穿透管理脚本，再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}请输入有效的选项${NC}"
                sleep 2
                ;;
        esac
    done
}

# 启动脚本
main