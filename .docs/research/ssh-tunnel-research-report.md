# SSH/Telnet 远程连接的现代替代与隧道方案调研报告（事实清单）

## 调研说明

- 调研日期：2026-09-03。调研方式：以直接抓取一手来源为主，每条事实后附来源 URL 与来源类型标注。

- 来源类型定义：

  - **官方文档**：厂商/项目官方网站的正式文档页面。

  - **官方仓库**：项目官方 GitHub 仓库（README、代码、Release）。

  - **官方白皮书/演讲**：作者本人撰写的一手材料（含镜像站）。

  - **发行版文档**：Debian Wiki 等发行方维护的文档（交叉验证用）。

  - **搜索快照**：目标官网在调研环境中无法直连时，通过搜索引擎返回的官网内容片段。

- 不确定性标注：**\[未验证]**（本次未直接核实）、**\[推导]**（由官方通用文档推导的组合用法，未见官方专门示例）、**\[注意]**（时效性/易变信息）。

- 已知环境限制：`www.wireguard.com` 与 `openvpn.net` 在调研沙箱内无法直连（连接被重置/超时），WireGuard 官网内容改用白皮书镜像、作者演讲材料与搜索快照交叉验证；OpenVPN 事实全部取自其官方 GitHub 仓库（含源码头文件）。

***

## 一、gost（GO Simple Tunnel）

1. gost 是 GO 语言实现的安全隧道（GO Simple Tunnel），采用 MIT 许可证；当前主版本 v3，GitHub 最新 Release 为 v3.2.6（2025-11-22）。【来源类型：官方仓库】<https://github.com/go-gost/gost>
2. 官方 README 列出三种主要使用方式：**正向代理**（组合多种协议组成转发链）、**端口转发**（将一个服务的端口映射到另一个服务）、**反向代理**（利用隧道与内网穿透将内网服务暴露到公网）。【来源类型：官方仓库】<https://github.com/go-gost/gost>
3. 功能特性（官方 README）：多端口监听、多级转发链、多协议支持、TCP/UDP 端口转发、反向代理与隧道、TCP/UDP 透明代理、DNS 解析与代理、TUN/TAP 设备与 TUN2SOCKS、负载均衡、路由控制（bypass）、准入控制、限速限流、插件系统、Prometheus 监控指标、动态配置、Web API，另有 GUI（gostctl）与 WebUI（gost-ui）配套工具。【来源类型：官方仓库】<https://github.com/go-gost/gost>
4. TCP 本地端口转发基本用法：`gost -L tcp://:8080/192.168.1.1:80`，将本地 8080 端口数据转发到 192.168.1.1:80（可用于转发 SSH 等 TCP 服务端口）；支持多目标地址 + 节点选择器实现一对多转发（`?strategy=round&maxFails=1&failTimeout=30s`，即轮询负载均衡与故障转移）。【来源类型：官方文档】<https://gost.run/tutorials/port-forwarding/>
5. 转发 TCP 端口可配合转发链（如 SOCKS5）间接转发：`gost -L tcp://:8080/192.168.1.1:80 -F socks5://192.168.1.2:1080`；也可借助**标准 SSH 协议的端口转发功能**：`gost -L tcp://:8080/192.168.1.1:80 -F sshd://user:pass@192.168.1.2:22`——远端 192.168.1.2:22 可以是系统本身的标准 SSH 服务，也可以是 gost 的 sshd 类型服务（`gost -L sshd://user:pass@:22`）。【来源类型：官方文档】<https://gost.run/tutorials/port-forwarding/>
6. 远程端口转发（类似 ssh -R）：`gost -L rtcp://:8080/192.168.1.1:80`；远程转发配合转发链时，转发链末端节点必须是开启了 BIND 功能的服务（如 `gost -L socks5://:1080?bind=true` 或 `relay://:8421?bind=true`）。远程端口转发也支持借助于标准 SSH 远程转发：`gost -L rtcp://:8080/192.168.1.1:80 -F sshd://user:pass@192.168.1.2:22`。【来源类型：官方文档】<https://gost.run/tutorials/port-forwarding/>
7. 支持端口范围（多对一/多对多）转发：`gost -L tcp://:8000-8003/192.168.1.1:8000-8010`，按顺序一对一映射。【来源类型：官方文档】<https://gost.run/tutorials/port-forwarding/>
8. 协议体系分两层（数据处理层 + 数据通道层），任意组合：

   - 数据处理-代理：`http`、`http2`、`socks4`/`socks4a`、`socks5`、`ss`（Shadowsocks）、`ssu`、`sni`、`relay`；

   - 数据处理-转发：`tcp`、`udp`、`rtcp`、`rudp`；

   - 数据通道：`tcp`、`mtcp`、`udp`、`tls`、`dtls`、`mtls`、`ws`、`mws`、`wss`、`mwss`、`h2`、`h2c`、`grpc`、`pht`、`ssh`/`sshd`、`kcp`、`quic`、`h3`、`wt`（WebTransport）、`ohttp`、`otls`、`icmp`/`icmp6`、`ftcp`（Fake TCP）；

   - 特殊协议：`file`、`https`、`http3`、`dns`、`red/redir`（TCP 透明代理）、`redu`、`tun`、`tap`、`router`、`tungo`、`forward`、`virtual`、`unix`、`serial`。
     【来源类型：官方文档】<https://gost.run/tutorials/protocols/overview/>
9. 限制：所有基于 UDP 的数据通道（如 kcp、quic、h3、wt，包括 icmp）仅能用于转发链的第一层级节点。【来源类型：官方文档】<https://gost.run/tutorials/protocols/overview/>
10. UDP 本地端口转发使用转发链时，转发链末端最后一个节点必须是开启 UDP 转发（UDP-over-TCP 方式）的 GOST HTTP/SOCKS5 代理、Relay 服务或 SSU 服务。【来源类型：官方文档】<https://gost.run/tutorials/port-forwarding/>
11. 官方文档/Wiki 站点为 gost.run（v2 旧版文档在 v2.gost.run）；提供二进制、安装脚本、Docker 镜像（`docker run --rm gogost/gost -V`）。【来源类型：官方仓库】<https://github.com/go-gost/gost>

## 二、proxychains / proxychains-ng

1. 工作原理（原版与 NG 版一致）：proxychains 是 UNIX 程序，**通过预加载 DLL（dlsym()、LD\_PRELOAD）hook 动态链接程序中网络相关的 libc 函数**，将连接重定向到 SOCKS4a/5 或 HTTP 代理。【来源类型：官方仓库】<https://github.com/rofl0r/proxychains-ng> 、<https://github.com/haad/proxychains>
2. 仅支持 TCP：明确说明"supports TCP only (no UDP/ICMP etc)"。【来源类型：官方仓库】<https://github.com/rofl0r/proxychains-ng>
3. 官方自述其机制本质是 HACK："The way it works is basically a HACK"，可能与部分程序不兼容——尤其是脚本程序、会启动大量后台守护进程的程序、或用 dlopen() 加载"模块"的程序（glibc 动态链接器缺陷）。对简单编译型（C/C++）动态链接程序应当可用；官方建议不兼容时改用基于 iptables 的方案（更稳健）。【来源类型：官方仓库】<https://github.com/rofl0r/proxychains-ng>
4. 支持平台：Linux、BSD、Mac、Haiku。【来源类型：官方仓库】<https://github.com/rofl0r/proxychains-ng>
5. 已知限制（官方 README"Known Problems"）：

   - macOS 10.11+ 的 SIP 阻止 hook 系统应用（需部分关闭 SIP 或将系统二进制复制到用户目录运行）；

   - glibc 动态链接器的缺陷/安全特性导致 dlopen() 加载的模块不受同样的 dlsym hook 影响，主要影响 perl、python 等重度依赖 dlopen 的脚本语言（musl libc 不受影响）；

   - 新版 nmap 的网络接口探测会出错（变通：禁用 proxy\_dns、用数字 IP，或使用 nmap 原生 SOCKS 支持）。
     【来源类型：官方仓库】<https://github.com/rofl0r/proxychains-ng>
6. 与 OpenSSH 的兼容性历史：v4.5 起 hook close() 以防 OpenSSH 干扰内部结构导致 ssh 客户端被代理时段错误；v4.17（2024-01-22 发布）增加 close\_range 函数 hook，修复较新版本的 OpenSSH。【来源类型：官方仓库】<https://github.com/rofl0r/proxychains-ng>
7. 与 ssh 组合的官方示例（原版 README）：`ssh -fN -D 4321 some.example.com` 建立 OpenSSH 动态（SOCKS5）代理后，用 `PROXYCHAINS_SOCKS5_HOST=127.0.0.1 PROXYCHAINS_SOCKS5_PORT=4321 proxychains zsh` 让整个 shell 的流量走该代理。【来源类型：官方仓库】<https://github.com/haad/proxychains>
8. 配置文件查找顺序：`-f` 参数或 `PROXYCHAINS_CONF_FILE` 环境变量指定的文件 → `./proxychains.conf` → `~/.proxychains/proxychains.conf` → `$(sysconfdir)/proxychains.conf`（通常 /etc/proxychains.conf）。原版还支持 `PROXYCHAINS_SOCKS5_HOST/PORT` 环境变量直接指定 SOCKS5 代理。【来源类型：官方仓库】<https://github.com/rofl0r/proxychains-ng> 、<https://github.com/haad/proxychains>
9. 支持代理链与混合代理类型：同一链中可混合 socks5/http/socks4（`your_host <--> socks5 <--> http <--> socks4 <--> target_host`），链策略支持随机、按序、动态（自动剔除失效代理 round\_robin）；DNS 可通过代理解析（v4.0 起改为远程 DNS 查询，支持 Tor .onion）。【来源类型：官方仓库】<https://github.com/rofl0r/proxychains-ng>
10. 版本现状：proxychains-ng 当前版本 4.17（Release 日期 2024-01-22，GPL-2.0）；原版 haad/proxychains README 标注版本 4.3.0。**\[未验证]** 两者"原版/延续版（fork）"的关系属社区常识，两份 README 均未明示该关系。【来源类型：官方仓库】<https://github.com/rofl0r/proxychains-ng> 、<https://github.com/haad/proxychains>
11. 安全提醒（官方 README）：可用于绕过审查，在某些国家可能非常危险；用于正事之前务必先验证代理是否按预期工作（如通过 ifconfig.me 类服务确认真实 IP 未泄露），并给出泄漏检查链接清单。【来源类型：官方仓库】<https://github.com/rofl0r/proxychains-ng>

## 三、Cloudflare Tunnel + Cloudflare Access（cloudflared / WARP）

1. 官方总述：通过 Cloudflare Zero Trust 可以**在不于服务器开放入站端口的风险下**将 SSH 服务暴露到互联网；官方列出四种接入方式：①SSH with Access for Infrastructure（**推荐**）②自管 SSH 密钥（WARP + Tunnel）③浏览器渲染的 SSH 终端 ④客户端 cloudflared（**legacy，不推荐用于新部署**）。【来源类型：官方文档】<https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/use-cases/ssh/>
2. 方式④（legacy，`cloudflared access ssh`）官方步骤：

   - 服务端：创建 Cloudflare Tunnel，在 Published application routes 中选择域名（如 `ssh.example.com`），Service 选 *SSH* 并填 `localhost:22`（若 SSH 服务在别的机器则填 `<server IP>:22`）；

   - 客户端：安装 cloudflared，在 `~/.ssh/config` 中一次性配置 `ProxyCommand /usr/local/bin/cloudflared access ssh --hostname %h`；

   - 之后执行 `ssh <username>@ssh.example.com` 时，cloudflared 会弹出浏览器窗口要求用身份提供商（IdP）认证后再建立连接；

   - 该方式要求服务器与客户端**两端都安装 cloudflared**，且需要 Cloudflare 上的有效 zone。
     【来源类型：官方文档】<https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/use-cases/ssh/ssh-cloudflared-authentication/>
3. 方式②（自管 SSH 密钥，WARP + Tunnel）官方说明：在服务器（或私网内任意主机）上运行 `cloudflared` 守护进程，建立到 Cloudflare 全球网络的**仅出站（outbound-only）安全连接**；用户设备安装 **Cloudflare WARP 客户端**并注册到 Zero Trust 组织，远程设备即可像处于私网一样连接；WARP 默认排除 RFC 1918 私网地址，必须配置 Split Tunnels（Include 模式加入目标 IP/CIDR，或 Exclude 模式精细拆分 RFC 1918 段）才能让目标私网 IP 走 WARP；随后 `ssh -i ~/.ssh/gcp_ssh <username>@<server IP>` 使用普通密钥登录。【来源类型：官方文档】<https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/use-cases/ssh/ssh-warp-to-tunnel/>
4. 方式①（Access for Infrastructure，推荐）关键事实：

   - 部署模型与 WARP-to-Tunnel 相同（Tunnel + WARP），额外提供更细粒度策略与命令日志；

   - **以短时效 SSH 证书替代传统长期 SSH 密钥**：用户凭 Access 登录令牌获得临时证书，消除在服务器上长期部署公钥的管理负担；

   - 配置流程：Tunnel 的 Private Networks 中登记服务器 IP/CIDR → 创建 Target（协议无关，表示一台服务器/集群/数据库/容器）→ 创建 Infrastructure Access 应用（指定目标主机名、协议 SSH、端口、策略及允许的 UNIX 用户名）；

   - 服务器侧配置：生成 Cloudflare SSH CA，将公钥写入 `/etc/ssh/ca.pub`，并在 `sshd_config` 顶部添加 `PubkeyAuthentication yes` 与 `TrustedUserCAKeys /etc/ssh/ca.pub`，重载 sshd；

   - 用户侧：只要设备 WARP 客户端处于登录状态，即可用**任意 SSH 客户端**直接 `ssh <username>@<target IP>`，无需修改本地任何 SSH 配置；支持 scp 与 rsync（部分 SSH 命令/特性有已知限制）；

   - SSH 命令日志：所有被代理的 SSH 命令可用客户提供的 HPKE 公钥加密后存于 Cloudflare（Cloudflare 不可见），可下载解密查看；Enterprise 可用 Logpush 保证投递。
     【来源类型：官方文档】<https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/use-cases/ssh/ssh-infrastructure-access/>
5. WARP 方案的网络要点（两种方式通用）：WARP 默认 **Exclude RFC 1918** 私网地址段，因此需要调整 Split Tunnels 才能把发往私网（如 172.31.0.0/16）的流量导入 WARP 隧道；官方提供 CIDR 拆分计算器示例（删除 172.16.0.0/12 后补回 172.16.0.0/13、172.24.0.0/14、172.28.0.0/15、172.30.0.0/16）。【来源类型：官方文档】<https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/use-cases/ssh/ssh-warp-to-tunnel/>
6. 客户端 cloudflared 方式可与 WARP 路由、Access for Infrastructure 并存，复用同一条 Cloudflare Tunnel。【来源类型：官方文档】<https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/use-cases/ssh/ssh-cloudflared-authentication/>

## 四、SSH over WebSocket（websockify / Nginx / Apache）

### 4.1 websockify

1. 原理（官方 README 原文）：websockify 最基本的层面**只是把 WebSocket 流量翻译成普通 socket 流量**——接受 WebSocket 握手、解析，然后开始双向转发客户端与目标之间的流量。【来源类型：官方仓库】<https://github.com/novnc/websockify>
2. 协议支持：自 0.5.0 起仅支持 HyBi / IETF 6455 WebSocket 协议，不支持旧的 Base64 编码数据格式；最新版本 v0.13.0，LGPL-3.0 许可。【来源类型：官方仓库】<https://github.com/novnc/websockify>
3. 加密（wss\://）：需要为 websockify 生成证书与私钥（默认加载 `self.pem`，可用 `--cert=CERT`、`--key=KEY` 覆盖）；官方给出 openssl 自签证书命令。【来源类型：官方仓库】<https://github.com/novnc/websockify>
4. 附加能力：守护进程化（-D）、会话录制（--record）、同端口迷你 web 服务器（--web DIR）、日志文件、认证插件（--auth-plugin/--auth-source）、Token 插件（按 token/hostname 连接到不同目标）。【来源类型：官方仓库】<https://github.com/novnc/websockify>
5. "Wrap a Program"能力：websockify 可以在本地启动一个程序并把 WebSocket 流量代理到该程序占用的 TCP 端口——通过 LD\_PRELOAD 库 `rebind.so` **拦截程序的 bind() 系统调用**，把指定端口挪到本地高位回环端口；用法如 `./run 5901 --wrap-mode=ignore -- vncserver ...`。【来源类型：官方仓库】<https://github.com/novnc/websockify>
6. Telnet 相关（与本次主题直接相关）：官方 README 给出包装 telnetd 的示例 `sudo ./run 2023 --wrap-mode=respawn -- telnetd -debug 2023`，并说明 websockify-js 项目中的 `wstelnet.html` 演示了一个基于 WebSocket 的简单 telnet 客户端。【来源类型：官方仓库】<https://github.com/novnc/websockify>
7. 实现生态：主实现为 Python（可选 numpy 提升性能），另有姊妹仓库 websockify-js（JavaScript/Node.js）与 websockify-other（C、Clojure、Ruby）。【来源类型：官方仓库】<https://github.com/novnc/websockify>

### 4.2 Nginx 反向代理 WebSocket（用于承载 SSH over WebSocket 的前置层）

1. 机制（官方文档）：自 **1.3.13 版**起，nginx 支持特殊工作模式——当被代理服务器返回 101（Switching Protocols）响应且客户端通过请求中的 "Upgrade" 头请求协议切换时，在客户端与被代理服务器之间建立隧道。【来源类型：官方文档】<https://nginx.org/en/docs/http/websocket.html>
2. 配置要点：由于 "Upgrade" 与 "Connection" 属 hop-by-hop 头，不会自动传给被代理服务器，必须显式设置：`proxy_set_header Upgrade $http_upgrade;` 与 `proxy_set_header Connection "upgrade";`（官方进阶示例用 map 映射 `$connection_upgrade`）；`proxy_http_version 1.1` 在 1.29.7 之前的版本为必需（官方文档注释注明该行在 1.29.7 版本前需要）。【来源类型：官方文档】<https://nginx.org/en/docs/http/websocket.html>
3. 超时：默认情况下被代理服务器 60 秒无数据传输即关闭连接，可用 `proxy_read_timeout` 增大，或由被代理端定期发送 WebSocket ping 帧重置超时并探活。【来源类型：官方文档】<https://nginx.org/en/docs/http/websocket.html>
4. **\[推导]** 将 SSH 承载于 WebSocket 并用 Nginx 反代的常见思路：Nginx 在 443 端口终结 TLS 并完成 WebSocket 升级（Upgrade/Connection 头透传），后端为 websockify（或 gost 的 ws/wss 通道）等 WebSocket↔TCP 转换器，再由其落到 sshd:22。该组合中 Nginx 的职责有上述官方文档支撑，但"SSH over WebSocket"整体方案无 Nginx 官方专门文档，属社区通用实践，本报告未实测验证。

### 4.3 Apache mod\_proxy\_wstunnel

1. 定位：`mod_proxy_wstunnel` 是 `mod_proxy` 的 WebSocket 支持模块，**httpd 2.4.5 及以后可用**，提供到后端 WebSocket 服务器的隧道化；连接自动升级（响应头 `Upgrade: WebSocket` / `Connection: Upgrade`）。【来源类型：官方文档】<https://httpd.apache.org/docs/2.4/mod/mod_proxy_wstunnel.html>
2. **弃用状态**：自 **2.4.47** 起，协议升级（隧道化）可由 `mod_proxy_http` 更好地处理（见 mod\_proxy 的 Protocol Upgrade 章节，符合 RFC 7230），mod\_proxy\_wstunnel 被标记为 **Deprecated**；`ProxyWebsocketFallbackToProxyHttp` 指令（2.4.48+，默认 On）控制是否回退给 mod\_proxy\_http 处理。【来源类型：官方文档】<https://httpd.apache.org/docs/2.4/mod/mod_proxy_wstunnel.html>
3. 用法示例（官方）：`ProxyPass "/ws2/" "ws://echo.websocket.org/"`、`ProxyPass "/wss2/" "wss://echo.websocket.org/"`；HTTP 与 WebSocket 混合代理可用 `ProxyPassMatch ^/(myApp/ws)$ ws://backend.example.com:9080/$1` 或 RewriteRule（RewriteCond 匹配 `%{HTTP:Upgrade} websocket`）实现；多后端可用 mod\_proxy\_balancer 负载均衡。【来源类型：官方文档】<https://httpd.apache.org/docs/2.4/mod/mod_proxy_wstunnel.html>
4. 通用升级参数：可通过 ProxyPass 的 `upgrade` 参数升级到 WebSocket 之外的协议；特殊值 `upgrade=NONE` 与 `upgrade=ANY` 仅用于测试/强制升级，**官方明确不建议在生产环境使用**（安全原因）。【来源类型：官方文档】<https://httpd.apache.org/docs/2.4/mod/mod_proxy_wstunnel.html>

## 五、sslh（同一端口多路复用 SSH/HTTPS）

1. 定位与原理（官方 README）：sslh 是 ssl/ssh 多路复用器——**在指定端口接受连接，并根据远端客户端发送的第一个数据包所做的测试（探测）进行转发**；官方称其为协议多路分解器/交换机（protocol demultiplexer / switchboard）。【来源类型：官方仓库】<https://github.com/yrutschle/sslh>
2. 内置探测协议：HTTP、TLS/SSL（含 **SNI 与 ALPN** 探测）、**SSH**、WireGuard、OpenVPN、tinc、XMPP、SOCKS5；任何能用正则表达式测试的协议也可被识别。【来源类型：官方仓库】<https://github.com/yrutschle/sslh>
3. 典型用例（官方原文）：在 **443 端口**同时提供多种服务（例如从几乎从不封 443 的公司防火墙内部连接 SSH），同时仍在该端口提供 HTTPS；借助 SNI/ALPN 探测可作为单 IP 后虚拟主机集群的前端。【来源类型：官方仓库】<https://github.com/yrutschle/sslh>
4. 成熟守护进程特性：权限与能力丢弃、inetd 支持、systemd 支持、透明代理（transparent proxying）、HAProxy proxyprotocol 支持、chroot、日志、IPv4/IPv6、TCP 与 UDP，以及 fork 型、select 型、libev 型三种并发模型（libev 适合更大规模部署）。【来源类型：官方仓库】<https://github.com/yrutschle/sslh>
5. 透明代理价值：让后端服务（Apache、sshd 等）看到真实客户端 IP/端口，如同外部直连——简化（或使可行）基于 IP 的访问控制，并可用 fail2ban 等基于 IP 的封禁工具；两种实现方法：额外虚拟网络接口法与 iptables 包标记法（后者高度依赖网络环境）；若后端支持 proxyprotocol，配置更简单，建议优先尝试。【来源类型：官方仓库】<https://github.com/yrutschle/sslh>
6. 安全审计：OpenSUSE 的 Matthias Gerstner 对 sslh 做过安全视角代码审查，发现包括**两个 CVE** 在内的若干问题（较关键者已部分修复）；官方建议生产用户阅读该审查并配置连接限制。**\[未验证]** 具体 CVE 编号本次未展开核对，原文链接：<https://security.opensuse.org/2025/06/13/sslh-denial-of-service-vulnerabilities.html> 【来源类型：官方仓库（转引第三方审查）】<https://github.com/yrutschle/sslh>
7. Docker 运行示例（官方 README）：`docker run --cap-add CAP_NET_RAW --cap-add CAP_NET_BIND_SERVICE --rm -it ghcr.io/yrutschle/sslh:latest --foreground --listen=0.0.0.0:443 --ssh=hostname:22 --tls=hostname:443`；docker-compose 示例中同一 443 端口同时分发 `--tls=nginx:443` 与 `--openvpn=openvpn:1194`。【来源类型：官方仓库】<https://github.com/yrutschle/sslh>
8. 许可与活跃度：GPL-2.0；仓库持续维护（README 最近更新于 2026 年，涉及 WireGuard 探测说明）。【来源类型：官方仓库】<https://github.com/yrutschle/sslh>

## 六、stunnel（将 SSH 包装成 TLS）

1. 定位（官网首页原文）：stunnel 是**为现有客户端和服务器添加 TLS 加密功能而不改变其代码**的代理；架构面向安全、可移植与可扩展（含负载均衡），适合大规模部署；基于 OpenSSL 加密库（支持库内编译的任何算法），可选 OpenSSL FIPS Provider 的 FIPS 140-3 验证。【来源类型：官方文档】<https://www.stunnel.org/>
2. 两种工作模式（功能页原文）：

   - **Server mode**：接受 TLS 并把明文转发给应用程序；

   - **Client mode**：为无法直接使用 TLS 的应用程序加上 TLS。
     【来源类型：官方文档】<https://www.stunnel.org/features.html>
3. **\[推导] 包装 SSH 成 TLS 的标准模式**：在 SSH 服务器同机运行 stunnel 服务端（accept 一个 TLS 端口 → connect 到 127.0.0.1:22 的 sshd），客户端运行 stunnel 客户端（accept 本地明文端口 → connect 到远端 TLS 端口），随后 `ssh -p <本地端口> user@localhost` 即在 TLS 隧道内承载 SSH。该模式的两个组成环节（server mode / client mode）有官方功能页直接支撑，但 stunnel 官方页面未提供专门的 SSH 配置样例，具体配方属社区通用实践，本报告未实测验证。
4. 认证与信任能力：X.509 服务器/客户端证书、verifyChain PKI 校验、checkHost/checkIP/checkEmail 身份检查、mTLS 客户端认证、verifyPeer 证书锁定、TLS 预共享密钥（PSK）、CRL/OCSP、客户端 SNI 与服务端基于 SNI 的虚拟服务。【来源类型：官方文档】<https://www.stunnel.org/features.html>
5. 路由/负载均衡/网络集成：多个 connect 目标、轮询分发或基于优先级的故障转移、延迟 DNS 解析、绑定出口源地址、HAProxy PROXY protocol v1 传递原始客户端地址、透明源/目的代理（支持的 Unix 平台）、TLS 内的 SOCKS 4/4a/5。【来源类型：官方文档】<https://www.stunnel.org/features.html>
6. 连接后端方式：`connect` 指向远端后端，`exec` 启动本地程序；一个进程可跑多个独立服务。【来源类型：官方文档】<https://www.stunnel.org/features.html>
7. 隔离与运维：setuid/setgid 权限丢弃、可选 chroot、Unix 特权模式下前台/后台、Windows 服务/GUI、systemd socket activation、不停连接的热重载配置、各类超时可配置。【来源类型：官方文档】<https://www.stunnel.org/features.html>
8. 许可与商业模式：GPL-2+ with OpenSSL exception，作者 Michał Trojnara；官方声明 stunnel **不是社区项目**（保留源码版权），提供商业支持与非 GPL 许可选项。【来源类型：官方文档】<https://www.stunnel.org/>

## 七、内网穿透工具（frp / ngrok / Tailscale / ZeroTier）

### 7.1 frp（fatedier/frp）

1. 定位（官方 README）：frp 是一个**快速反向代理（fast reverse proxy）**，用于把位于 NAT 或防火墙后的本地服务器暴露到互联网；目前支持 **TCP、UDP、HTTP、HTTPS** 四种协议，另提供 **P2P 直连模式**。【来源类型：官方仓库】<https://github.com/fatedier/frp>
2. 架构与角色分工（官方示例）：`frps`（服务端）部署在有公网 IP 的服务器 A，`frpc`（客户端）部署在公网不可直达的局域网服务器 B；官方示例配置为 TOML 文件（`frps.toml` / `frpc.toml`）。【来源类型：官方仓库】<https://github.com/fatedier/frp>
3. 官方"通过 SSH 访问局域网电脑"示例：

   - 服务端：`frps.toml` 设置 `bindPort = 7000`，运行 `./frps -c ./frps.toml`；

   - 客户端：`frpc.toml` 设置 `serverAddr = "x.x.x.x"`、`serverPort = 7000`，并声明 `[[proxies]] name = "ssh" type = "tcp" localIP = "127.0.0.1" localPort = 22 remotePort = 6000`；

   - 在其他机器上执行 `ssh -oPort=6000 test@x.x.x.x` 即可经服务器 A 访问内网机器 B；

   - 官方特别区分三个端口的语义：`localPort`（客户端侧监听）与 `remotePort`（服务端侧暴露）承载进出 frp 系统的业务流量，`serverPort` 仅用于 frps 与 frpc 之间通信。
     【来源类型：官方仓库】<https://github.com/fatedier/frp>
4. 多个 SSH 服务共享同一端口（官方示例）：使用 `tcpmux` 类型代理 + `multiplexer = "httpconnect"` + 自定义域名（`customDomains`），服务端设置 `tcpmuxHTTPConnectPort = 5002`；只要客户端支持 HTTP CONNECT 代理连接方式即可复用端口，官方给出的访问方式为 `ssh -o 'proxycommand socat - PROXY:x.x.x.x:%h:%p,proxyport=5002' test@machine-a.example.com`（机器 A/B 仅域名不同）。【来源类型：官方仓库】<https://github.com/fatedier/frp>
5. README 完整特性清单（目录结构直接反映）：配置文件（含环境变量、拆分配置）、服务端 Dashboard、客户端 Admin UI 与动态代理管理（store）、Prometheus 监控、客户端认证（**Token / OIDC**）、加密与压缩（含 **TLS**）、frpc 配置热重载、从客户端获取代理状态、服务端端口白名单、端口复用、带宽限制（每代理粒度）、**TCP 流多路复用**、**KCP 协议支持**、**QUIC 协议支持**、连接池、负载均衡、服务健康检查、HTTP Host 头重写与其他 HTTP 头设置、获取真实 IP（X-Forwarded-For / Proxy Protocol）、Web 服务 HTTP Basic Auth、自定义子域名、URL 路由、TCP 端口多路复用、通过代理连接 frps、端口范围映射、客户端插件、服务端管理插件、**SSH Tunnel Gateway**、虚拟网络（VirtualNet）。【来源类型：官方仓库】<https://github.com/fatedier/frp>
6. UDP 与 Unix socket 转发（官方示例）：`type = "udp"` 可把 DNS 查询转发到 `8.8.8.8:53`（`localIP = "8.8.8.8"`, `localPort = 53`, `remotePort = 6000`）；Unix domain socket（如 Docker daemon socket）可通过 `unix_domain_socket` 插件以 TCP 形式对外暴露。【来源类型：官方仓库】<https://github.com/fatedier/frp>
7. 许可与版本：Apache-2.0 许可证；README 最近版本更新提交为 **0.71.0（2026-08-03）**。**\[注意]** 官方明确 V2 正在开发且**与 V1 不兼容**：V2 的构想基于作者在 K8s/ServiceMesh 领域的经验，核心是类似 Envoy 的现代化四层/七层可扩展代理；官方同时表示"会持续优化当前版本直到有更多时间进行大版本重构"。【来源类型：官方仓库】<https://github.com/fatedier/frp>
8. 已知部署问题（官方 README）：部分杀毒软件会把 frpc 误报为恶意软件并删除（因 frp 具备创建反向代理、绕过防火墙端口限制的能力），官方引用 issue #3637 说明并建议加白名单。【来源类型：官方仓库】<https://github.com/fatedier/frp>

### 7.2 ngrok TCP 隧道

1. 工作原理（官方文档）：ngrok agent 在本机运行后向 ngrok 云服务发起**出站 TLS 连接（443 端口）**，ngrok 分配公共 URL 并把入站请求经加密隧道路由到本地端口——因此**无需防火墙变更或端口转发**，云与 agent 之间全部流量 TLS 加密。【来源类型：官方文档】<https://ngrok.com/docs/share-localhost/tunnels>
2. 支持的隧道协议（官方表格）：`ngrok http 8080`（HTTP/S：Web 应用、API、webhook）、`ngrok tls 8443`（TLS 透传：自定义证书）、**`ngrok tcp 3389`（TCP：数据库、RDP、游戏服务器等——SSH 即属此类）**。【来源类型：官方文档】<https://ngrok.com/docs/share-localhost/tunnels>
3. 官方《Secure Remote Access with ngrok for SSH and RDP》指南核心架构：

   - **每个远程网络只需一个 ngrok agent**：部署在网络内可达服务器上充当 edge gateway，作为中心网关可达本地网络任意服务，无需每台设备安装 agent；

   - **Internal Endpoint（内部端点）**：使网络内服务在 ngrok 平台内可达但**不公开暴露**，只能接收来自 Cloud Endpoint 或明确路由到它的内部服务流量；

   - **Cloud Endpoint（云端点）**：经 API/仪表盘集中管理的永久外部入口，始终在线、不随 agent 生命周期，默认不转发流量、必须显式配置路由到内部端点；

   - 需先通过 API **预留 TCP 地址**（`reserved_addrs`，可指定 region）；

   - 通过 **Traffic Policy** 附加 `forward-internal` 动作把云端 TCP 流量转发到内部端点，用 `restrict-ips` 动作配置来源 IP 白名单（官方称可防端口扫描等恶意访问者）；

   - **Endpoint Pooling**：多个 agent 配置同一内部 URL 自动形成端点池，流量在健康端点间分配，单个 agent 掉线时无缝切换，实现冗余/高可用。
     【来源类型：官方文档】<https://ngrok.com/docs/guides/ssh-rdp>
4. agent 配置形态（官方指南）：`ngrok.yml`（`version: 3`）中以 `endpoints` 列表定义隧道，内部端点如 `url: 'tcp://device1.gateway1.internal:443'` + `upstream: url: 22`（把端点接到设备 22 端口的 SSH 服务，RDP 用 3389）；后台服务安装：`ngrok service install --config /etc/ngrok.yml`。【来源类型：官方文档】<https://ngrok.com/docs/guides/ssh-rdp>
5. Agent Endpoint 与安全补充：每个隧道创建一个 Agent Endpoint（仅当 agent 运行时存在），可配置 Traffic Policy 加认证、限流、头操作等；官方指南还提供 Service User + 独立 authtoken（带 ACL `bind:*.gateway1.internal`）实现 agent 隔离管理，以及自定义 connect URL（`connect.example.com` 代替默认 connect.ngrok-agent.com）作为付费功能。【来源类型：官方文档】<https://ngrok.com/docs/share-localhost/tunnels> 、<https://ngrok.com/docs/guides/ssh-rdp>

### 7.3 Tailscale（overlay 网络跑 SSH：Tailscale SSH）

1. 定位（官方文档）：Tailscale SSH 让 Tailscale 管理 tailnet 中 SSH 连接的**认证与授权**；官方标注适用于所有付费计划（all plans）。【来源类型：官方文档】<https://tailscale.com/docs/features/tailscale-ssh>
2. 工作原理：开启后 Tailscale **接管该设备 Tailscale IP 的 22 端口**（仅拦截来自 tailnet 的流量），把 SSH 流量路由到 Tailscale 自带的 SSH 服务器而非系统 sshd；连接由 **WireGuard + Tailscale 节点密钥**完成认证与加密；SSH 客户端/服务器仍会建立加密的 SSH 连接，但在 SSH 协议认证阶段 Tailscale SSH 服务器已知对端身份并接管（使用 SSH 认证类型 `none`，不再要求客户端进一步证明）。【来源类型：官方文档】同上
3. 与原生 SSH 的兼容性：不修改 `/etc/ssh/sshd_config` 与 `~/.ssh/authorized_keys`，因此不经 Tailscale 的其他 SSH 连接照常工作；通过 **netstack 端口拦截 + 即时自动配置客户端 known\_hosts**，让 `ssh myhost` 无需任何新二进制或新配置文件；实现 SSH File Transfer Protocol（SFTP），使较新 SSH 客户端的 SCP/SFTP 可用。【来源类型：官方文档】同上
4. 密钥与撤销管理收益：使用自动生成、会话结束即过期的 WireGuard 密钥，减少 SSH 密钥管理负担；控制平面同时分发节点密钥与 SSH 主机公钥（私钥留在本地）；撤销用户只需修改访问控制策略，保存后客户端数秒内响应新规则，且**会切断用户已建立的 SSH 连接**。【来源类型：官方文档】同上
5. 平台要求：服务端组件仅支持 **Linux** 与 **macOS（开源** **`tailscale`** **+** **`tailscaled`** **CLI 变体）**，需 Tailscale v1.24 或更高；发起连接的客户端可为任意运行 Tailscale 的平台；macOS 上需用开源 tailscaled 变体而非 App Store 版。【来源类型：官方文档】同上
6. 配置要点：目标主机执行 `tailscale set --ssh`（一次性操作：生成主机密钥对、把公钥共享给控制平面、配置 tailscaled 拦截 22 端口；执行会使现有到该机 Tailscale IP 的 SSH 连接挂起）；访问控制策略需同时包含网络放行规则与 `ssh` 规则，SSH 规则字段包括：`action`（`accept` / `check`）、`src`、`dst`（**仅允许 22 端口且不可显式指定端口**）、`users`（目标主机上的 UNIX 用户名，支持 `autogroup:nonroot`、`localpart:*@domain`）、`checkPeriod`（默认 12 小时，最小 1 分钟、最大 168 小时，可 `always`）、`acceptEnv`（v1.76.0+，支持 `*`/`?` 通配符的环境变量白名单）。【来源类型：官方文档】同上
7. check 模式：可对指定连接（如以 root 登录）要求用户先在身份提供商（IdP）重新认证，通过后 12 小时（或指定周期）内免重复认证；默认访问控制策略即对"任何用户 → 自己的设备"启用 check 模式（允许 root 与非 root）。【来源类型：官方文档】同上
8. 审计能力：支持 SSH 会话记录（SSH recording），用于审计、排障与合规。【来源类型：官方文档】同上
9. 底层网络：Tailscale 官方在 Tailscale SSH 页面多处表述连接"over WireGuard / using WireGuard"进行认证与加密，即 Tailscale 构建于 WireGuard 之上；MagicDNS 名称可直接用于 SSH（DNS 解析失败时因自定义 known\_hosts 用主机名而可能报错，官方列为限制）。【来源类型：官方文档】同上

### 7.4 ZeroTier（overlay 网络跑 SSH）

1. 定位（官方协议文档）：ZeroTier 是"地球规模的智能可编程以太网交换机（smart programmable Ethernet switch for planet Earth）"——构建于密码学安全的全球 P2P 网络之上的**分布式网络 hypervisor**，让所有设备、VM、容器与应用像处于同一物理数据中心/云区域一样通信。【来源类型：官方文档】<https://docs.zerotier.com/protocol/>
2. 协议分层：**VL1**（底层加密 P2P 传输层，"虚拟线缆"）+ **VL2**（类 VXLAN 的以太网仿真层，包含企业级 SDN 特性：用于网络微分段与安全监控的细粒度访问控制规则）。【来源类型：官方文档】同上
3. 加密与传输：所有 ZeroTier 流量使用**仅用户掌控的密钥**端到端加密（Curve25519/Ed25519 非对称密钥、Salsa20 加密 + Poly1305 认证，encrypt-then-MAC，组合与 NaCl 参考实现一致）；**大部分流量 P2P 直连**，无法建立直连时提供免费（但慢）的中继。【来源类型：官方文档】同上
4. 标识符体系：40 位（10 位十六进制）**ZeroTier 地址**（节点/设备身份，由公钥推导，不编码路由信息）+ 64 位（16 位十六进制）**network ID**（虚拟以太网网络，可理解为 VLAN）；network ID = 该网络主控制器的 ZeroTier 地址（40 位）+ 24 位网络编号。【来源类型：官方文档】同上
5. 拓扑与连接建立（VL1）：零配置、组织方式类似 DNS——**根服务器（root servers）** 分为唯一的 **planet**（由 ZeroTier Inc. 作为免费服务运营，目前 4 个、分布全球多个网络提供商，几乎所有用户 100ms 网络延迟内可达）与用户可自建的 **moons**（moon 可置于本地机房，即使断网也能正常运行）；节点初始仅与根有上游连接，发包"向上"的过程中触发机会式直连建立（官方称为 *transport triggered link provisioning*）：根服务器向双方回送 *rendezvous* 消息，双端据此尝试 **UDP hole punching** 打洞建立直连；直连失败则通信**永久经中继进行**且永不放弃周期性重试；另支持 LAN 对等发现、对称 NAT 的端口预测、uPnP/NAT-PMP 显式端口映射。【来源类型：官方文档】同上
6. 与 SSH 的组合（官方原文建议）：VL1 目前**不实现前向保密**（出于简单性、可靠性、代码体积及集群/故障转移复杂度考虑，官方附 GitHub 讨论 #204）；官方明确建议需要该级别安全性的用户"使用在 ZeroTier 上层运行的其他加密协议如 SSL 或 **SSH**"——这类协议通常实现前向保密，且在 ZeroTier 上叠加形成纵深防御（两个安全传输同时存在关键漏洞的概率极低，双重加密的 CPU 开销对多数负载不显著）。【来源类型：官方文档】同上
7. 控制器与证书：网络控制器（controller）是 VL2 虚拟网络的**证书颁发机构**（类比 OpenFlow 的 SDN 控制器但协议不同），向成员节点签发由控制器私钥签名的证书/凭据；可使用官方 SaaS 托管控制器（my.zerotier.com）或自建；根服务器（VL1 连接促进者）与网络控制器（VL2 配置管理/CA）是不同角色，官方专门澄清不可混淆；控制器 `identity.secret` 被攻破可导致签发伪造网络配置或放入未授权成员，丢失则网络失控。【来源类型：官方文档】同上
8. 设计哲学：目标与设计原则受 Google **BeyondCorp** 论文与 **Jericho Forum**（"deperimeterization"）启发。【来源类型：官方文档】同上
9. Trusted paths（性能选项）：可为指定物理路径跳过加密认证以降低 CPU 开销（面向物理安全网络上的高性能 SDN/NFV 场景），官方明确不推荐、并提醒谨慎用于云供应商私网。【来源类型：官方文档】同上
10. 跑 SSH 的方式：**\[推导]** 设备加入同一 ZeroTier 网络（join 后获得受管 IP）即可像局域网一样直接 `ssh user@<受管 IP>`；该用法与官方"在 ZeroTier 上层使用 SSH"的建议（第 6 条）一致，但受管 IP 直连 SSH 的具体操作细节官方协议文档未逐步展开，本报告未实测。

## 八、Teleport（Gravitational，零信任 SSH 访问网关）

1. 定位（官方仓库 README 首句）：Teleport 为基础设施提供**连接（connectivity）、认证（authentication）、访问控制（access controls）与审计（audit）**；官方列举的典型用途包括：为全部云与本地基础设施设置 SSO；**无需长期密钥或密码**保护服务器、K8s 集群、数据库、Windows 桌面、Web 应用与云 API 的访问；**不依赖 VPN 或堡垒机**、经安全隧道访问 NAT 与防火墙后的资源；记录并审计 SSH、Kubernetes、数据库、RDP、Web 会话；对用户/机器/工作负载/资源类型施加一致的 RBAC/ABAC；最小权限与 Just-in-Time（JIT）访问请求；人与工作负载统一身份层。【来源类型：官方仓库】<https://github.com/gravitational/teleport>
2. 组成（官方 README"Introduction"）：Teleport = **身份感知访问代理（identity-aware access proxy）+ 签发短时效证书的 CA + 统一访问控制系统 + 访问防火墙后资源的隧道系统**；以**单个 Go 二进制**交付。【来源类型：官方仓库】同上
3. 协议/资源支持：SSH 节点、Kubernetes 集群、PostgreSQL/MongoDB/CockroachDB/MySQL 数据库、MCP（Model Context Protocol）、内部 Web 应用、Windows 主机、联网服务器；可部署为 Linux 守护进程或 Kubernetes 部署。【来源类型：官方仓库】同上
4. 安全实践（官方 README）：无 SSH 密钥/Kubernetes token 之类共享秘密——所有协议统一使用**证书认证 + 自动过期**；对一切启用 MFA；对一切启用 SSO（GitHub Auth、OpenID Connect、SAML，兼容 Okta、Microsoft Entra ID 等端点）；支持会话共享协作排障；经 CLI 或 Web UI 对每个 SSH 节点、数据库实例、K8s 集群、内部 Web 应用做基础设施自省。【来源类型：官方仓库】同上
5. OpenSSH 兼容性（官方 README 原文）："It is *fully compatible with OpenSSH*, `sshd` servers, and `ssh` clients, Kubernetes clusters and more."【来源类型：官方仓库】同上
6. 集群最小架构（官方架构文档）：**最小 Teleport 集群只需运行两个服务——Teleport Auth Service 与 Teleport Proxy Service**（家庭实验环境两者可作为同一二进制同一进程运行）。【来源类型：官方文档】<https://goteleport.com/docs/architecture/proxy/>
7. Proxy Service 职责（官方架构文档）：带 Web UI 的身份感知代理，关键功能：用户以 SSO 身份提供商或本地凭据经 Web UI 访问 SSH 与 Windows 桌面；**拦截多协议流量（SSH、Kubernetes、HTTPS、数据库）并确保只有已认证客户端能连接目标资源**；记录命令、API 调用与查询并流式写入审计日志；为防火墙后的服务器提供网络连接（反向隧道）；TLS routing 功能可把所有协议的所有端口压缩到一个 TLS 端口。【来源类型：官方文档】同上
8. 三种接入模式（官方架构文档，均默认开启、无需特殊配置）：

   - **Web UI 模式**：Proxy 实现 **WSS（secure web sockets）** 代理目标资源（如 SSH 服务器或桌面），Proxy 终结流量并为客户端连接重新编码数据；

   - **IAP（身份感知代理）模式**：用户发起 SSO/登录流程为其客户端机器上的公钥签名；官方认为 IAP 模式比 Web UI 访问**更安全**——私钥从不离开用户客户端、与资源的连接双向认证，且因较少使用浏览器而更不易受 CSRF、cookie 劫持等 Web 攻击；

   - **Tunnel 模式**：防火墙后的资源向 Proxy 建立**反向隧道**（reverse tunnels），Proxy 经由这些隧道把客户端连接转发到目标资源（官方示例：Alice 经两条隧道连接防火墙后的 K8s 集群）。
     【来源类型：官方文档】同上
9. 客户端用法（官方指南）：

   - Teleport CLI（`tsh`）：`tsh login --proxy=teleport.example.com --user=<user>`（默认触发多因素认证提示），随后以 `tsh ssh` 访问节点；

   - **OpenSSH 客户端**：使用凭据产物中的 `ssh_config`（示例：`ssh -F /opt/machine-id/ssh_config root@my-host.example.teleport.sh hostname`，节点名后需追加集群名）；配套 `known_hosts` 内含 Teleport SSH 主机 CA 用于校验主机证书；官方注明该 ssh\_config **要求本机安装** **`tsh`**（用于使 OpenSSH 客户端兼容 Teleport 的端口多路复用）；

   - 其他工具的集成前提（官方原文）：工具须**支持 SSH 客户端证书，并支持 ProxyCommand 或 ProxyJump 功能**（如 Ansible，另有专门指南）；

   - 端口约定：TLS routing（`proxy_listener_mode: multiplex`）下 `tsh`/`tctl` 全部经 Proxy 的 Web 地址 443 端口访问所有服务；未启用时 `tsh` 走 Proxy 的 3080（负载均衡后也可 443），Auth Service 的 gRPC 监听在 3025。
     【来源类型：官方文档】<https://goteleport.com/docs/machine-workload-identity/access-guides/ssh>
10. 许可与运营：仓库许可证 **AGPL-3.0**；公司 Gravitational Inc.（2026）；文档按 OpenSource/Team/Cloud/Enterprise 标注功能可用性；文档站当前默认版本线 18.x（本报告抓取期间 README 示例 tag 为 v18.5.0、`tctl status` 输出示例为 18.11.0）。**\[注意]** 版本号随时间快速演进，且文档 URL 结构在 14.x–18.x 间有变动（如 `/docs/connect-your-client/ssh/` 已 404 迁移至 `/docs/machine-workload-identity/access-guides/ssh`），引用建议以 docs 站内搜索为准。【来源类型：官方仓库/官方文档】<https://github.com/gravitational/teleport>
11. 场景归纳（官方用途描述的直接映射）：统一 SSO 入口、替代"VPN + 堡垒机 + 长期密钥"模式、JIT 最小权限访问、全协议会话记录与合规审计——即官方文档所述"Stop wrangling SSH keys, VPNs, and bastion hosts"的定位。【来源类型：官方文档】<https://goteleport.com/docs/>

## 九、WireGuard / OpenVPN overlay 方式的定位

### 9.1 WireGuard

1. 定位（作者论文摘要，NDSS 2017）：WireGuard 是**工作在第 3 层（layer 3）的安全网络隧道**，以 Linux **内核虚拟网络接口**形式实现，目标是在大多数用例中**取代 IPsec，以及 OpenVPN 等流行的用户态/TLS 方案**，同时做到更安全、更高性能、更易用。【来源类型：官方白皮书（NDSS 2017 论文页）】<https://www.ndss-symposium.org/ndss2017/ndss-2017-programme/wireguard-next-generation-kernel-network-tunnel/>
2. 设计要点（同论文摘要）：隧道基于"**对端公钥 ↔ 隧道源 IP 地址**关联"这一安全隧道基本原则；基于 NoiseIK 的**单轮密钥交换**；新颖的定时器状态机对用户透明地处理全部会话创建；Curve25519 预共享静态密钥点用于 OpenSSH 风格的双向认证；ChaCha20Poly1305 认证加密封装 UDP 报文实现传输速度；强前向保密 + 高身份隐藏；改进的 IP-binding cookies 抗 DoS（优于 IKEv2 与 DTLS 的 cookie 机制）；整体设计使**收到报文时不分配任何资源**。【来源类型：官方白皮书】同上
3. 代码规模（论文摘要）：Linux 实现可在**少于 4000 行代码**内完成，易于审计与验证。【来源类型：官方白皮书】同上
4. 内核主线事实（作者官方邮件列表公告）：2020 年 3 月 29 日 Linus 发布的 **Linux 5.6** 首次包含 WireGuard 的发布版（WireGuard 1.0.0 for Linux 5.6），作者原文称"从此以后的内核将**默认内置 WireGuard**（built-in by default）"。【来源类型：官方邮件列表公告（作者本人发布）】<https://lists.zx2c4.com/pipermail/wireguard/2020-March/005206.html>
5. 用户态工具（官方仓库）：wireguard-tools 是 WireGuard 的主要用户态工具集，提供 `wg(8)` 与 `wg-quick(8)`；支持 Linux、OpenBSD、FreeBSD、macOS、Windows、Android；GPL-2.0 许可；除 C 编译器与健全的 libc 外无依赖。【来源类型：官方仓库】<https://github.com/WireGuard/wireguard-tools>
6. wg-quick 的定位（官方 README 原文）："a very quick and dirty bash script"，从 wg(8) 风格配置文件读取少量额外变量并自动配置接口；官方建议已有可用网络管理工具或配置时，将 `wg(8)` 或直接 WireGuard API 集成进网络管理器，而非使用 wg-quick。【来源类型：官方仓库】同上
7. 生态采用（交叉验证）：Tailscale 官方文档在 Tailscale SSH 页面多处表述其连接"以 WireGuard 认证与加密"，即 Tailscale 构建于 WireGuard 之上；ZeroTier 官方文档则将自身与 SSL/SSH 等其他安全协议并列讨论。【来源类型：官方文档（第三方厂商文档，交叉验证）】<https://tailscale.com/docs/features/tailscale-ssh>
8. **环境限制说明**：`www.wireguard.com` 在调研沙箱内无法直连（ERR\_CONNECTION\_CLOSED），官网首页/quickstart 内容未直接核实；上述事实改由作者 NDSS 论文页、官方邮件列表与 GitHub 官方仓库交叉验证。

### 9.2 OpenVPN

1. 定位（官方仓库 README）：**"OpenVPN -- A secure tunneling daemon"**；版权 2002–2026 OpenVPN Inc.；GPL-2.0 许可；仓库语言构成 C 占 94.5%。【来源类型：官方仓库】<https://github.com/OpenVPN/openvpn>
2. 版本现状：GitHub 最新 Release **v2.7.5（2026-07-02）**；master 分支 2026-02-13 起开始 2.8 开发周期（ChangeLog 与 version.m4 的提交记录）。【来源类型：官方仓库】同上
3. 官方资源指引（README）：详细文档与示例见 man 页（openvpn.net/man.html）与 HOWTO（openvpn.net/howto.html）；样例配置位于 `sample/sample-config-files`（来自 HOWTO）；底层协议描述见源码发行版中的 `ssl.h` 文件。**\[未验证]** openvpn.net 在调研环境无法直连，man/HOWTO 页面本次未打开核实，此处仅为官方仓库 README 的指引转述。【来源类型：官方仓库】同上
4. 加密库可插拔：主线支持 OpenSSL，另提供 Mbed TLS 4、wolfSSL、AWS-LC 的构建支持与说明（README.mbedtls / README.wolfssl / README.awslc）。【来源类型：官方仓库】同上
5. 子项目拆分：easy-rsa 与 tap-windows 已移至独立子项目维护（github.com/OpenVPN/easy-rsa、github.com/OpenVPN/tap-windows6）；社区提供的 Windows MSI 安装器与 Debian 包由 openvpn-build 仓库构建。【来源类型：官方仓库】同上
6. 内核卸载演进：仓库包含 README.dco.md（Data Channel Offload 文档），2026-04-11 的提交强调"从旧 ovpn-dco 到新 ovpn（内核）模块的过渡"。**\[未验证]** 该内核模块在主线内核的具体合入状态本次未展开核对。【来源类型：官方仓库】同上
7. 与 WireGuard 的对比定位（WireGuard 侧来源）：WireGuard 作者论文明确把 OpenVPN 列为其替代对象——原文将其描述为"popular user space and/or TLS-based solutions like OpenVPN"（流行的用户态和/或基于 TLS 的方案）。【来源类型：官方白皮书（WireGuard 侧）】<https://www.ndss-symposium.org/ndss2017/ndss-2017-programme/wireguard-next-generation-kernel-network-tunnel/>

### 9.3 overlay 方式定位小结

1. 层次定位：WireGuard 与 OpenVPN 提供的是**网络层（L3/L2）overlay**——隧道建立后整个 IP 网段可达，SSH 只是众多受益应用之一；frp/ngrok 更接近**单服务端口映射/反向代理**；sslh/stunnel/websockify 属于**单端口协议适配层**；Teleport 则是**应用层身份网关 + CA**。**\[推导]** 该分层归纳为本报告的综合判断，非任一官方来源的直接表述。【依据见以上各节】
2. 官方来源的对照事实：Tailscale 基于 WireGuard 加密连接（Tailscale SSH 官方页面）；ZeroTier 采用自有 VL1/VL2 协议并官方建议在其上叠加 SSH/SSL 以获得前向保密（官方协议文档）；Cloudflare WARP-to-Tunnel 方案以 WARP 客户端 + cloudflared 出站隧道实现私网访问（Cloudflare 官方文档）——三者均为"overlay 网络上跑 SSH"路线的代表。
3. 性能与复杂度定位（各有官方表述）：WireGuard 以 <4000 行内核实现、单轮握手、收到报文不分配资源的设计对比 IPsec/OpenVPN 的复杂度与开销（NDSS 论文）；OpenVPN 则以用户态守护进程、多加密库（OpenSSL/Mbed TLS/wolfSSL/AWS-LC）可插拔为特点（官方仓库）。二者定位差异由此可直接溯源。【来源类型：官方白皮书/官方仓库】

***

## 附一：横向速查表（各条依据见上文对应小节）

| 工具                       | 原理（官方表述摘要）                             | SSH 接入方式（官方）                                                                                  | 依赖的入口/控制面                 |
| ------------------------ | -------------------------------------- | --------------------------------------------------------------------------------------------- | ------------------------- |
| gost                     | 多协议代理与 TCP/UDP 端口转发，转发链任意组合            | `gost -L tcp://:8080/<目标>:22` 转发；亦可经 sshd 通道                                                  | 无强制（可完全自组）                |
| proxychains-ng           | LD\_PRELOAD hook 网络相关 libc 函数          | `proxychains ssh ...` 走 SOCKS4a/5/HTTP 代理                                                     | 自备代理服务器                   |
| Cloudflare Tunnel/Access | cloudflared 仅出站隧道 + Access 策略          | `ProxyCommand cloudflared access ssh`（legacy）/ WARP 直连 / 任意客户端（Infrastructure Access + 短时效证书） | Cloudflare 全球网络 + 有效 zone |
| websockify               | 把 WebSocket 流量翻译成普通 socket 流量          | WebSocket 客户端（如 wstelnet）落到 TCP                                                               | 自备（可经 Nginx/Apache 反代）    |
| sslh                     | 按客户端首包探测分发协议                           | 与 HTTPS 等共享同一端口（如 443）                                                                        | 自备（透明代理可保真实 IP）           |
| stunnel                  | 为现有服务加 TLS（server/client 两种模式）         | 客户端连本地明文端口，TLS 到服务端                                                                           | 自备证书/PSK 体系               |
| frp                      | frps/frpc 反向代理暴露 NAT 后服务               | `ssh -oPort=6000 user@<frps 公网 IP>`                                                           | 自备公网 frps                 |
| ngrok                    | agent 出站 TLS(443) 隧道到 ngrok 云          | SSH 客户端连预留 TCP 地址（经 Cloud Endpoint 转发）                                                        | ngrok 云服务                 |
| Tailscale                | WireGuard 加密 + 接管 Tailscale IP 的 22 端口 | 任意 SSH 客户端直接 `ssh user@<tailnet IP>`（netstack 拦截 + known\_hosts 自动配置）                         | Tailscale 控制平面            |
| ZeroTier                 | VL1 加密 P2P + VL2 以太网仿真                 | 照常 `ssh user@<受管 IP>`（官方建议叠加 SSH 获得前向保密）                                                      | ZeroTier 根服务器 + 控制器（可自建）  |
| Teleport                 | 身份感知代理 + 短时效证书 CA + 审计                 | `tsh ssh` 或 OpenSSH（ssh\_config + ProxyCommand/ProxyJump）                                     | 自建集群或 Teleport Cloud      |
| WireGuard                | L3 内核虚拟网络接口隧道（NoiseIK 单轮握手）            | 照常 `ssh user@<隧道内 IP>`                                                                        | 自备（对等手动配置）                |
| OpenVPN                  | 用户态安全隧道守护进程（TLS 系）                     | 照常 `ssh user@<隧道内 IP>`                                                                        | 自备（CA/证书体系）               |

## 附二：不确定内容汇总

**\[未验证]**

1. sslh 安全审查涉及的两个具体 CVE 编号（第五节第 6 条，原文链接已附，未展开核对）。
2. proxychains 与 proxychains-ng 的"原版/延续版"关系（两份 README 均未明示，属社区常识）。
3. OpenVPN 官网 man/HOWTO 页面内容（openvpn.net 无法直连，仅转述官方仓库 README 指引）。
4. OpenVPN 新 ovpn 内核模块在 Linux 主线的合入状态（第九节 9.2 第 6 条）。
5. WireGuard 官网（wireguard.com）首页与 quickstart 正文（无法直连；核心事实已用 NDSS 论文页 + 官方邮件列表 + GitHub 官方仓库交叉验证）。

**\[推导]**

1. Nginx 反代"SSH over WebSocket"的整体组合方案（各组件行为有官方文档，组合无官方专门文档，未实测）。
2. stunnel 双端包装 SSH 的完整配置配方（两种模式有官方功能页支撑，官方无 SSH 专门样例，未实测）。
3. ZeroTier 受管 IP 直接 `ssh` 的操作细节（与官方"在 ZeroTier 上层使用 SSH"建议一致，协议文档未逐步展开，未实测）。
4. 附一速查表与 9.3 第 1 条的分层归纳（报告综合判断）。
5. ngrok 文档中 `ngrok tcp <port>` 的最简形态与本报告 SSH/RDP 指南中的 Cloud Endpoint 形态并存，具体计费/可用性差异未逐一核对。

**\[注意]**（时效性/易变信息）

1. 各项目版本号：gost v3.2.6（2025-11-22）、proxychains-ng 4.17（2024-01-22）、websockify v0.13.0、frp 0.71.0（2026-08-03）、OpenVPN v2.7.5（2026-07-02）、Teleport 18.x、Tailscale SSH 要求 v1.24+（服务端）/ v1.76.0+（acceptEnv）——均为调研当时抓取值。
2. Cloudflare `cloudflared access ssh` 客户端方案官方标注 legacy、不推荐用于新部署；Access for Infrastructure 为官方推荐方式。
3. Apache mod\_proxy\_wstunnel 自 2.4.47 起弃用（推荐改用 mod\_proxy\_http 的协议升级处理）。
4. Teleport 文档 URL 结构随大版本变动，引用时建议以官方站内搜索为准。

