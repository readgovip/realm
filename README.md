## 参考自https://www.nodeseek.com/post-183613-1 ，在此感谢大佬的教程

说明：在大佬的基础上添加了检测更新和重启服务等功能

## 脚本界面预览：

```
欢迎使用realm一键转发脚本
=================
1. 部署环境
2. 添加转发
3. 添加端口段转发
4. 删除转发
5. 启动服务
6. 停止服务
7. 重启服务
8. 检测更新
9. 一键卸载
10. 更新脚本
11. 面板管理
0. 退出脚本
=================
realm 状态：已安装
realm 转发状态：启用
面板状态：已安装
面板服务状态：启用
```
## 一键脚本：
国内或v6 only可用（推荐）
```
curl -L https://host.wxgwxha.eu.org/https://github.com/wcwq98/realm/releases/download/v2.1/realm.sh -o realm.sh && chmod +x realm.sh &&  ./realm.sh
```
或
```
curl -L https://github.com/wcwq98/realm/releases/download/v2.1/realm.sh -o realm.sh && chmod +x realm.sh &&  ./realm.sh
```
或
```
curl -L https://raw.githubusercontent.com/wcwq98/realm/refs/heads/main/realm.sh -o realm.sh && chmod +x realm.sh &&  ./realm.sh
```
## 默认配置文件（脚本在首次部署环境时会自动添加）
```
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
```
## 可视化面板配置文件路径：/root/realm/web/config.toml
```
[auth]
password = "123456" # 面板密码

[server]
port = 8081 # 面板端口

[https]
enabled = false #是否开启HTTPS(强烈建议开启HTTPS)若certificate下没有证书不要开启此功能
cert_file = "./certificate/cert.pem"
key_file = "./certificate/private.key"

```
## 如需其他更多配置请参考官方文档： https://github.com/zhboner/realm
