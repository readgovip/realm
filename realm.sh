#!/bin/bash

# 定义颜色变量
red="\033[0;31m"
green="\033[0;32m"
plain="\033[0m"

# 脚本版本
sh_ver="2.1"

# 初始化环境目录
init_env() {
    mkdir -p /root/realm
    mkdir -p /root/.realm
}

# 配置文件路径
CONFIG_PATH="/root/.realm/config.toml"

# 处理命令行参数
while getopts "l:r:" opt; do
  case $opt in
    l)
      listen_ip_port="$OPTARG"
      ;;
    r)
      remote_ip_port="$OPTARG"
      ;;
    *)
      echo "Usage: $0 [-l listen_ip:port] [-r remote_ip:port]"
      exit 1
      ;;
  esac
done

# 如果提供了 -l 和 -r 参数，追加配置到 config.toml
if [ -n "$listen_ip_port" ] && [ -n "$remote_ip_port" ]; then
    echo "配置中转机 IP 和端口为: $listen_ip_port"
    echo "配置落地机 IP 和端口为: $remote_ip_port"

    cat <<EOF >> "$CONFIG_PATH"

[[endpoints]]
listen = "$listen_ip_port"
remote = "$remote_ip_port"
EOF
    echo "配置已追加，listen = $listen_ip_port，remote = $remote_ip_port"
    exit 0
fi

# 更新realm状态
update_realm_status() {
    if [ -f "/root/realm/realm" ]; then
        realm_status="已安装"
        realm_status_color=$green
    else
        realm_status="未安装"
        realm_status_color=$red
    fi
}

# 检查realm服务状态
check_realm_service_status() {
    if systemctl is-active --quiet realm; then
        realm_service_status="启用"
        realm_service_status_color=$green
    else
        realm_service_status="未启用"
        realm_service_status_color=$red
    fi
}

# 更新面板状态
update_panel_status() {
    if [ -f "/root/realm/web/realm_web" ]; then
        panel_status="已安装"
        panel_status_color=$green
    else
        panel_status="未安装"
        panel_status_color=$red
    fi
}

# 检查面板服务状态
check_panel_service_status() {
    if systemctl is-active --quiet realm-panel; then
        panel_service_status="启用"
        panel_service_status_color=$green
    else
        panel_service_status="未启用"
        panel_service_status_color=$red
    fi
}

# 更新脚本
Update_Shell() {
    echo -e "当前脚本版本为 [ ${sh_ver} ]，开始检测最新版本..."
    sh_new_ver=$(wget --no-check-certificate -qO- "https://raw.githubusercontent.com/readgovip/realm/main/realm.sh" | grep 'sh_ver="' | awk -F "=" '{print $NF}' | sed 's/\"//g' | head -1)
    if [[ -z ${sh_new_ver} ]]; then
        echo -e "${red}检测最新版本失败！请检查网络或稍后再试。${plain}"
        return 1
    fi
    
    if [[ ${sh_new_ver} == ${sh_ver} ]]; then
        echo -e "当前已是最新版本 [ ${sh_new_ver} ]！"
        return 0
    fi
    
    echo -e "发现新版本 [ ${sh_new_ver} ]，是否更新？[Y/n]"
    read -p "(默认: y): " yn
    yn=${yn:-y}
    if [[ ${yn} =~ ^[Yy]$ ]]; then
        wget -N --no-check-certificate https://raw.githubusercontent.com/readgovip/realm/main/realm.sh -O realm.sh
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载脚本失败，请检查网络连接！${plain}"
            return 1
        fi
        chmod +x realm.sh
        echo -e "脚本已更新为最新版本 [ ${sh_new_ver} ]！"
        exec bash realm.sh
    else
        echo -e "已取消更新。"
    fi
}

# 检查依赖
check_dependencies() {
    echo "正在检查当前环境依赖"
    local dependencies=("wget" "tar" "systemctl" "sed" "grep" "curl" "unzip")

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "正在安装 $dep..."
            if [ -x "$(command -v apt-get)" ]; then
                apt-get update && apt-get install -y "$dep"
            elif [ -x "$(command -v yum)" ]; then
                yum install -y "$dep"
            else
                echo "无法安装 $dep。请手动安装后重试。"
                exit 1
            fi
        fi
    done

    echo "所有依赖已满足。"
}

# 显示菜单的函数
show_menu() {
    clear
    update_realm_status
    check_realm_service_status
    update_panel_status
    check_panel_service_status
    echo "欢迎使用realm一键转发脚本"
    echo "================="
    echo "1. 部署环境"
    echo "2. 添加转发"
    echo "3. 添加端口段转发"
    echo "4. 删除转发"
    echo "5. 启动服务"
    echo "6. 停止服务"
    echo "7. 重启服务"
    echo "8. 检测更新"
    echo "9. 一键卸载"
    echo "10. 更新脚本"
    echo "11. 面板管理"
    echo "0. 退出脚本"
    echo "================="
    echo -e "realm 状态：${realm_status_color}${realm_status}${plain}"
    echo -e "realm 转发状态：${realm_service_status_color}${realm_service_status}${plain}"
    echo -e "面板状态：${panel_status_color}${panel_status}${plain}"
    echo -e "面板服务状态：${panel_service_status_color}${panel_service_status}${plain}"
}

# 部署环境的函数
deploy_realm() {
    mkdir -p /root/realm
    cd /root/realm

    _version=$(curl -s https://api.github.com/repos/zhboner/realm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$_version" ]; then
        echo "获取版本号失败，请检查本机能否链接 https://api.github.com/repos/zhboner/realm/releases/latest"
        return 1
    else
        echo "当前最新版本为: ${_version}"
    fi

    arch=$(uname -m)
    os=$(uname -s | tr '[:upper:]' '[:lower:]')

    case "$arch-$os" in
        x86_64-linux)
            download_url="https://github.com/zhboner/realm/releases/download/${_version}/realm-x86_64-unknown-linux-gnu.tar.gz"
            ;;
        x86_64-darwin)
            download_url="https://github.com/zhboner/realm/releases/download/${_version}/realm-x86_64-apple-darwin.tar.gz"
            ;;
        aarch64-linux)
            download_url="https://github.com/zhboner/realm/releases/download/${_version}/realm-aarch64-unknown-linux-gnu.tar.gz"
            ;;
        aarch64-darwin)
            download_url="https://github.com/zhboner/realm/releases/download/${_version}/realm-aarch64-apple-darwin.tar.gz"
            ;;
        arm-linux)
            download_url="https://github.com/zhboner/realm/releases/download/${_version}/realm-arm-unknown-linux-gnueabi.tar.gz"
            ;;
        armv7-linux)
            download_url="https://github.com/zhboner/realm/releases/download/${_version}/realm-armv7-unknown-linux-gnueabi.tar.gz"
            ;;
        *)
            echo "不支持的架构: $arch-$os"
            return
            ;;
    esac

    wget -O "/root/realm/realm-${_version}.tar.gz" "$download_url"
    tar -xvf "/root/realm/realm-${_version}.tar.gz" -C /root/realm/
    chmod +x /root/realm/realm

    # 创建 config.toml 模板
    mkdir -p /root/.realm    
    cat <<EOF > "$CONFIG_PATH"
[network]
no_tcp = false #是否关闭tcp转发
use_udp = true #是否开启udp转发

#参考模板
# [[endpoints]]
# listen = "0.0.0.0:本地端口"
# remote = "落地鸡ip:目标端口"

[[endpoints]]
listen = "0.0.0.0:1234"
remote = "0.0.0.0:5678"
EOF

    echo "[Unit]
Description=realm
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
DynamicUser=true
WorkingDirectory=/root/realm
ExecStart=/root/realm/realm -c /root/.realm/config.toml

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/realm.service

    systemctl daemon-reload
    update_realm_status
    echo "部署完成。"
}

# 卸载realm
uninstall_realm() {
    systemctl stop realm
    systemctl disable realm
    rm -f /etc/systemd/system/realm.service
    systemctl daemon-reload

    rm -f /root/realm/realm
    echo "realm已被卸载。"

    read -e -p "是否删除配置文件 (Y/N, 默认N): " delete_config
    delete_config=${delete_config:-N}

    if [[ $delete_config == "Y" || $delete_config == "y" ]]; then
        rm -rf /root/realm
        rm -rf /root/.realm
        echo "配置文件已删除。"
    else
        echo "配置文件保留。"
    fi

    update_realm_status
}

# 删除转发规则的函数
delete_forward() {
    echo "当前转发规则："
    local lines=($(grep -n 'remote =' /root/.realm/config.toml | grep -v '#' | awk -F: '{print $1}'))
    if [ ${#lines[@]} -eq 0 ]; then
        echo "没有发现任何转发规则。"
        return
    fi
    local index=1
    for line_num in "${lines[@]}"; do
        listen_line=$((line_num - 1))
        listen_port=$(sed -n "${listen_line}p" /root/.realm/config.toml | cut -d '"' -f 2)
        remote_port=$(sed -n "${line_num}p" /root/.realm/config.toml | cut -d '"' -f 2)
        echo "${index}. 本地监听: ${listen_port} --> 远程目标: ${remote_port}"
        let index+=1
    done

    echo "请输入要删除的转发规则序号，直接按回车返回主菜单。"
    read -p "选择: " choice
    if [ -z "$choice" ]; then
        echo "返回主菜单。"
        return
    fi

    if ! [[ $choice =~ ^[0-9]+$ ]]; then
        echo "无效输入，请输入数字。"
        return
    fi

    if [ $choice -lt 1 ] || [ $choice -gt ${#lines[@]} ]; then
        echo "选择超出范围，请输入有效序号。"
        return
    fi

    local line_number=${lines[$((choice-1))]}

    # 找到 [[endpoints]] 的起始行
    local start_line=$line_number
    while [ $start_line -ge 1 ]; do
        local line_content=$(sed -n "${start_line}p" /root/.realm/config.toml)
        if [[ $line_content =~ $$\[endpoints$$\] ]]; then
            break
        fi
        ((start_line--))
    done

    # 删除从 start_line 开始的 3 行
    sed -i "${start_line},$(($start_line+3))d" /root/.realm/config.toml

    echo "转发规则已删除。"
}

# 添加转发规则
add_forward() {
    while true; do
        read -e -p "请输入落地鸡的IP: " ip
        read -e -p "请输入本地中转鸡的端口（port1）: " port1
        read -e -p "请输入落地鸡端口（port2）: " port2
        echo "
[[endpoints]]
listen = \"0.0.0.0:$port1\"
remote = \"$ip:$port2\"" >> /root/.realm/config.toml

        read -e -p "是否继续添加转发规则(Y/N)? " answer
        if [[ $answer != "Y" && $answer != "y" ]]; then
            break
        fi
    done
}

# 添加端口段转发
add_port_range_forward() {
    read -e -p "请输入落地鸡的IP: " ip
    read -e -p "请输入本地中转鸡的起始端口: " start_port
    read -e -p "请输入本地中转鸡的截止端口: " end_port
    read -e -p "请输入落地鸡端口: " remote_port

    for ((port=$start_port; port<=$end_port; port++)); do
        echo "
[[endpoints]]
listen = \"0.0.0.0:$port\"
remote = \"$ip:$remote_port\"" >> /root/.realm/config.toml
    done

    echo "端口段转发规则已添加。"
}

# 启动服务
start_service() {
    systemctl unmask realm.service
    systemctl daemon-reload
    systemctl restart realm.service
    systemctl enable realm.service
    echo "realm服务已启动并设置为开机自启。"
    check_realm_service_status
}

# 停止服务
stop_service() {
    systemctl stop realm.service
    systemctl disable realm.service
    echo "realm服务已停止并已禁用开机自启。"
    check_realm_service_status
}

# 重启服务
restart_service() {
    systemctl daemon-reload
    systemctl restart realm.service
    echo "realm服务已重启。"
    check_realm_service_status
}

# 更新realm
update_realm() {
    echo "> 检测并更新 realm"

    current_version=$(/root/realm/realm --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    tag_version=$(curl -Ls "https://api.github.com/repos/zhboner/realm/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [[ -z "$tag_version" ]]; then
        echo -e "${red}获取 realm 版本失败，可能是由于 GitHub API 限制，请稍后再试${plain}"
        exit 1
    fi

    if [[ "$current_version" == "$tag_version" ]]; then
        echo "当前已经是最新版本: ${current_version}"
        return
    fi

    echo -e "获取到 realm 最新版本: ${tag_version}，开始安装..."

    arch=$(uname -m)
    wget -N --no-check-certificate -O /root/realm/realm.tar.gz "https://github.com/zhboner/realm/releases/download/${tag_version}/realm-${arch}-unknown-linux-gnu.tar.gz"
    
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载 realm 失败，请确保您的服务器可以访问 GitHub${plain}"
        exit 1
    fi

    cd /root/realm
    tar -xvf realm.tar.gz
    chmod +x realm

    echo -e "realm 更新成功。"
    update_realm_status
}

# 面板管理函数
panel_management() {
    clear
    echo "==========================="
    echo "Realm 面板管理"
    echo "==========================="
    echo "1. 启动面板"
    echo "2. 暂停面板" 
    echo "3. 安装面板"
    echo "4. 卸载面板"
    echo "5. 修改面板配置"
    echo "0. 返回主菜单"
    echo "==========================="
    read -p "请选择操作 [0-5]: " panel_choice

    case $panel_choice in
        1) start_panel ;;
        2) stop_panel ;;
        3) install_panel ;;
        4) uninstall_panel ;;
        5) modify_panel_config ;;
        0) return ;;
        *) echo "无效的选择" ;;
    esac
}

install_panel() {
    echo "开始安装 Realm 面板..."
    
    # 检测系统架构
    arch=$(uname -m)
    case "$arch" in
        x86_64)
            panel_file="realm-panel-linux-amd64.zip"
            ;;
        aarch64|arm64)
            panel_file="realm-panel-linux-arm64.zip"
            ;;
        *)
            echo "不支持的系统架构: $arch"
            return 1
            ;;
    esac

    cd /root/realm 

    # 从 GitHub 下载面板文件
    echo "正在从 GitHub 下载面板文件..."
    echo "检测到系统架构: $arch，将下载: $panel_file"
    
    # 下载面板文件
    download_url="https://github.com/wcwq98/realm/releases/download/v2.1/${panel_file}"
    if ! wget -O "${panel_file}" "$download_url"; then
    echo "下载失败，请检查网络连接或稍后再试。"
    return 1
    fi
    
	mkdir web
    # 解压并设置权限
    unzip "${panel_file}" -d /root/realm/web

    cd web
    # 设置权限
    chmod +x realm_web
    


    # 创建服务文件
    echo "[Unit]
Description=Realm Web Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/realm/web
ExecStart=/root/realm/web/realm_web
Restart=on-failure

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/realm-panel.service

    # 重新加载 systemd 并启动服务
    systemctl daemon-reload
    systemctl enable realm-panel
    systemctl start realm-panel

    update_panel_status
    echo "Realm 面板安装完成。"
}

# 启动面板
start_panel() {
    systemctl start realm-panel
    echo "面板服务已启动。"
    check_panel_service_status
}

# 停止面板
stop_panel() {
    systemctl stop realm-panel
    echo "面板服务已停止。"
    check_panel_service_status
}

# 卸载面板
uninstall_panel() {
    systemctl stop realm-panel
    systemctl disable realm-panel
    rm -f /etc/systemd/system/realm-panel.service
    systemctl daemon-reload

    rm -f /root/realm/realm_web
    echo "面板已被卸载。"

    update_panel_status
}

# 修改面板配置
modify_panel_config() {
    echo "修改面板配置..."
    # 在此添加修改配置的具体逻辑
    echo "配置已修改。"
}

# 主程序
main() {
    check_dependencies
    init_env

    while true; do
        show_menu
        read -p "请输入选项 [0-11]: " choice

        case $choice in
            1) deploy_realm ;;
            2) add_forward ;;
            3) add_port_range_forward ;;
            4) delete_forward ;;
            5) start_service ;;
            6) stop_service ;;
            7) restart_service ;;
            8) update_realm ;;
            9) uninstall_realm ;;
            10) Update_Shell ;;
            11) panel_management ;;
            0) exit 0 ;;
            *) echo "无效的选项，请重新输入。" ;;
        esac
    done
}

main
