# SSH/Telnet 过代理连接：坑点（Pitfalls）事实清单

调研时间：2026-09-03。本清单按坑点分组，每条事实附来源 URL 与来源类型，并标注置信度。事实均来自实际检索到的来源，未检索到可靠来源的内容明确标注为"未验证"。

## 来源类型与置信度标记说明

| 标记       | 含义                                                                                                         |
| -------- | ---------------------------------------------------------------------------------------------------------- |
| 官方文档     | 软件/OS 项目的官方手册页、官方用户指南、官方站点（OpenBSD man pages、Nmap Ncat Guide、PuTTY 官方手册、NGINX 官方文档、各项目 GitHub 官方 README 等） |
| RFC/标准   | IETF RFC 原文                                                                                                |
| 厂商资料     | 商业产品官方文档或厂商博客（Termius、MobaXterm、Xshell、JumpServer 等）                                                       |
| 专家文章     | 个人技术博客/演讲材料，有一手配置实践（jfranken.de、dimoulis.net、adangel.org、frost.kiwi、deployer.org 等）                        |
| 社区讨论     | GitHub Issue/Gist 评论、Hacker News、Stack Exchange、CSDN 问答、Qiita 等论坛式内容                                       |
| 镜像/第三方整理 | 第三方对官方文档的整理或镜像（documentation.help、Royal Apps 等）                                                            |

置信度标记：**\[已确认]**（官方文档直接陈述或多源一致）、**\[多数来源]**（≥2 个独立非官方来源一致）、**\[单一来源]**（仅一个来源支持）、**\[未完全验证]**（仅获得搜索摘要、无法核对全文，或来源可信度有限）。

***

## 1. HTTP 代理 CONNECT 端口限制（"只放行 443，拒绝 22"）

**1.1 HTTP 代理通过 CONNECT 方法建立隧道，隧道内可承载任意 TCP 流量（包括 SSH 与 Telnet）。** NGINX 官方文档："The HTTP `CONNECT` method is used to establish a secure tunnel between the client and the proxy server... This tunnel permits the transmission of HTTPS traffic and other protocols, such as SSH or FTP, through the proxy."

- 来源：<https://docs.nginx.com/nginx/admin-guide/web-server/http-connect-proxy/> （官方文档）

- 置信度：**\[已确认]**（另有 Ncat 指南佐证，见 8.x）

**1.2 企业/HTTP 代理普遍只允许 CONNECT 到少数端口（典型为 80/443），SSH 默认的 22 端口会被拒绝。** dimoulis.net："HTTP proxies usually only allow connections to specific ports such as 80 and 443, although they allow arbitrary TCP streams with the CONNECT method."

- 来源：<https://www.dimoulis.net/posts/ssh-over-proxy/> （专家文章）

- 置信度：**\[多数来源]**（与 1.3、1.4 相互印证）

**1.3 代理配置良好或位于防火墙之后时，可能只允许 443 端口的"HTTPS"连接。** Johannes Franken（德国系统管理员的 OpenSSH 演讲材料）："If the proxyserver is well configured or sitting behind a firewall, https-connections might be allowed to port 443 only. In this case, you can start another ssh-demon on port 443 or forward it to your already running sshd on port 22."

- 来源：<https://www.jfranken.de/homepages/johannes/vortraege/ssh3.en.pdf> （专家演讲材料）

- 置信度：**\[单一来源]**（对该现象的明确陈述；与 1.2 经验一致）

**1.4 按"端口白名单"限制 CONNECT 目标，是代理服务器的推荐/常见配置实践。** NGINX 官方文档建议对 CONNECT 代理做访问控制："Access control can be managed in several ways: by ports and port ranges with the `num_map` module"，示例配置中仅 `443 ssl;` 一档被映射为放行值，其余端口为 `default 0`（拒绝）。

- 来源：<https://docs.nginx.com/nginx/admin-guide/web-server/http-connect-proxy/> （官方文档；注意该功能为 NGINX Plus R36+ 商业版）

- 置信度：**\[已确认]**（证明端口限制是代理侧的标准做法，而非偶发现象）

**1.5 常见解法一：让 sshd 监听 443（或使用服务商提供的 443 入口），再配 ProxyCommand 过代理。** GitHub 提供 `ssh.github.com:443` 作为过防火墙/代理的 SSH 入口，社区广泛使用 `Hostname ssh.github.com` + `Port 443` 的写法；juejin 教程演示把 sshd 的 `Port 22` 改为/追加 `Port 443`；dimoulis 的示例配置同样将目标端口写为 443。

- 来源：<https://adangel.org/2020/10/15/github-behind-proxy/> 、<https://www.dimoulis.net/posts/ssh-over-proxy/> 、<https://juejin.cn/post/7618149310454399039> （专家文章/社区）

- 置信度：**\[多数来源]**

**1.6 常见解法二：走"443 + TLS/HTTPS"隧道而非裸 CONNECT。** 可用 `ProxyCommand openssl s_client -proxy 127.0.0.1:3128 -connect your.example.com:443 -quiet` 借 OpenSSL 的 `-proxy` 选项完成 HTTPS 隧道（要求目标侧有反向代理配合）；也有项目（GhostSSH、proxytunnel、sslh）专门解决"直连 22 被封"的场景。

- 来源：<https://gist.github.com/vondraussen/ebf0b33e0210cf35fb895b44f7b7e10c> （社区 Gist）、<https://github.com/ankushT369/GhostSSH> （项目页）、<https://blog.frost.kiwi/ssh-over-https-tunneling/> （专家文章）、<https://articles.manugarg.com/ssh_tunneling.pdf> （专家文章，proxytunnel 示例 `ProxyCommand ./proxytunnel -g http-proxy.xyz.com -G 8080 -d %h -D 443`）

- 置信度：**\[多数来源]**

***

## 2. 代理认证坑（Basic/NTLM 在 ProxyCommand 工具链中的支持）

**2.1 OpenSSH 自身不支持 HTTP 代理认证——认证能力完全取决于 ProxyCommand 所调用的外部工具。** frost.kiwi："OpenSSH supplies ProxyCommand and relies on other tools proxying for it"；且"such a fundamental piece of infrastructure like OpenSSH doesn't support it（OS 代理设置），with the exception of SSH as a proxy itself. SSH clients like Putty do."

- 来源：<https://blog.frost.kiwi/ssh-over-https-tunneling/> （专家文章）

- 置信度：**\[多数来源]**（PuTTY 官方手册 4.16 亦确认 PuTTY 有内建代理支持，见 9.1）

**2.2 corkscrew 支持 HTTP Basic 认证：需把** **`username:password`** **写入文件（建议放** **`~/.ssh`）并** **`chmod 600`，作为 ProxyCommand 的最后一个参数传入。** 官方 README 同时警告："The proxy authentication feature is very new and has not been tested extensively so your mileage may vary"，并明确记录与 Microsoft Proxy Server 存在偶发性认证问题。

- 来源：<https://github.com/patpadgett/corkscrew> （官方文档/项目 README）

- 置信度：**\[已确认]**（README 原文）

**2.3 corkscrew（及多数同类工具）只支持 Basic，不支持 NTLM/Kerberos。** Hacker News 评论："almost all software that can handle authenticated proxies (including corkscrew) can only handle basic auth, but not NTLM"，做法是在本地先跑 cntlm/ntlmaps 把 NTLM 认证转换成本地无认证代理，再让 ssh/corkscrew 连本地代理；geekchamp 文章同样指出 "Corkscrew does not handle NTLM or Kerberos negotiation by itself"。

- 来源：<https://news.ycombinator.com/item?id=3544762> （社区讨论）、<https://geekchamp.com/using-corkscrew-to-tunnel-ssh-over-http-3/> （专家文章）

- 置信度：**\[多数来源]**；其中 geekchamp 全文未能直接抓取（Cloudflare 保护），仅以搜索摘要核对，**\[未完全验证]**

**2.4 密码含冒号时认证可能解析出错。** geekchamp："If the password itself contains a colon, test carefully; some proxy authentication parsers treat the first colon as the separator between username and password."

- 来源：<https://geekchamp.com/using-corkscrew-to-tunnel-ssh-over-http-3/> （专家文章，**仅搜索摘要，\[未完全验证]**）

- 置信度：**\[单一来源]\[未完全验证]**

**2.5 Ncat（Nmap 的 netcat）通过** **`--proxy-auth user:password`** **支持代理认证：HTTP 与 SOCKS5 用** **`user:pass`，SOCKS4 只有用户名。** Ncat 官方指南："If the proxy server requires authentication, use the `--proxy-auth` option. Use `--proxy-auth <username>:<password>` for HTTP and SOCKS5 proxies and `--proxy-auth <username>` for SOCKS4 proxies." HTTP 同时支持 Basic 和 Digest，客户端优先用 Digest；"Basic sends credentials in the clear and Digest does not."

- 来源：<https://nmap.org/ncat/guide/ncat-proxy.html> （官方文档）

- 置信度：**\[已确认]**

**2.6 OpenBSD netcat（`nc -X connect -x ...`）没有代理密码参数，需交互输入。** adangel.org："netcat from OpenBSD doesn't seem to have an option to specify the password. But there is another netcat variant, this time from nmap"；解决方式是换 ncat：`ProxyCommand ncat --proxy-type http --proxy 192.168.x.y:8080 --proxy-auth proxyuser:password %h %p`。（注：OpenBSD nc 有 `-P proxy_username` 选项但无对应密码选项，见 nc(1) 手册 SYNOPSIS。）

- 来源：<https://adangel.org/2020/10/15/github-behind-proxy/> （专家文章）、<https://man.openbsd.org/nc> （官方文档，`-P proxy_username`）

- 置信度：**\[多数来源]**

**2.7 HTTP Basic 代理认证本身是 base64 明文。** adangel.org："the proxy connection is unencrypted and the http basic authentication is just a base64 encoded"；Ncat 官方指南同样警告 "Basic sends credentials in the clear"。

- 来源：<https://adangel.org/2020/10/15/github-behind-proxy/> 、<https://nmap.org/ncat/guide/ncat-proxy.html>

- 置信度：**\[已确认]**

**2.8 有些 CONNECT 代理根本不支持 Basic 代理认证。** NGINX 官方文档（NGINX Plus 的 HTTP CONNECT 正向代理）："For an HTTP CONNECT proxy, mutual TLS (mTLS) is currently the only supported authentication method. Other methods, such as basic authentication are currently not supported because NGINX Plus processes only the `Authorization` header, not the `Proxy-Authorization` header."

- 来源：<https://docs.nginx.com/nginx/admin-guide/web-server/http-connect-proxy/> （官方文档，NGINX Plus）

- 置信度：**\[已确认]**（证明"带认证的 CONNECT"并非所有代理都有，是选型时的坑）

**2.9 PuTTY 的代理认证矩阵（GUI 侧对照）：** 用户名/密码认证支持 HTTP 与 SOCKS5；HTTP 用 Digest（优先）或 Basic；SOCKS5 用 CHAP 或明文密码；SOCKS4 仅用户名；SSH 代理则走 SSH 自身认证。官方文档同时警告"代理密码会以明文保存在会话配置中"。

- 来源：<https://the.earth.li/~sgtatham/putty/0.81/htmldoc/Chapter4.html#config-proxy> （官方文档 4.16.4）

- 置信度：**\[已确认]**

***

## 3. 超时与 Keepalive 坑（代理/防火墙切断空闲连接）

**3.1 防火墙/NAT/代理会因空闲切断连接，是官方文档明确描述的现象。** PuTTY 官方手册（4.14.1 Using keepalives to prevent disconnection）："Some network routers and firewalls need to keep track of all connections through them. Usually, these firewalls will assume a connection is dead if no data is transferred in either direction after a certain time interval. This can cause PuTTY sessions to be unexpectedly closed by the firewall if no traffic is seen in the session for some time."（典型症状 'Connection reset by peer'）

- 来源：<https://the.earth.li/~sgtatham/putty/0.81/htmldoc/Chapter4.html#config-keepalive> （官方文档）

- 置信度：**\[已确认]**

**3.2 官方建议的 keepalive 间隔约为防火墙空闲超时的一半。** PuTTY 手册举例："if your firewall cuts connections off after ten minutes then you might want to enter 300 seconds (5 minutes)"。

- 来源：同上（官方文档）

- 置信度：**\[已确认]**

**3.3 OpenSSH 客户端默认不发 keepalive：`ServerAliveInterval`** **默认为 0（不发送），`ServerAliveCountMax`** **默认为 3。** man 手册示例："If, for example, ServerAliveInterval is set to 15 and ServerAliveCountMax is left at the default, if the server becomes unresponsive, ssh will disconnect after approximately 45 seconds." 且 server alive 消息走加密通道、不可伪造，与可伪造的 TCP keepalive（TCPKeepAlive）不同。

- 来源：<https://man.openbsd.org/ssh_config> （官方文档）

- 置信度：**\[已确认]**

**3.4 服务端对应项** **`ClientAliveInterval`** **默认也为 0，`ClientAliveCountMax`** **默认 3。** sshd\_config 手册给出同样的 15×3≈45 秒示例；"Setting a zero ClientAliveCountMax disables connection termination."

- 来源：<https://man.openbsd.org/sshd_config> （官方文档）

- 置信度：**\[已确认]**

**3.5 keepalive 并非万能，某些场景反而更糟。** PuTTY 手册："you might find that keepalives help connection loss, or you might find they make it worse, depending on what kind of network problems you have"；临时断连期间一旦有数据发送，重传失败会直接放弃连接；另外 keepalives 仅在 Telnet 和 SSH 协议中支持，Rlogin/SUPDUP/Raw 无法实现。

- 来源：<https://the.earth.li/~sgtatham/putty/0.81/htmldoc/Chapter4.html#config-keepalive> （官方文档）

- 置信度：**\[已确认]**

**3.6 堡垒机/跳板段短超时会"杀死"长连接复用的 master。** deployer.org："If your bastion enforces short session timeouts on the jump leg, you may see deploys fail mid-task because the master died on the jump host. Disable multiplexing for those hosts."

- 来源：<https://deployer.org/blog/ssh-multiplexing> （专家文章）

- 置信度：**\[单一来源]**（与 3.1 机制一致）

**3.7 社区常用** **`ServerAliveInterval 30`** **等配置维持过代理的 SSH 连接。** frost.kiwi 的 SSH Config 示例注释："ServerAliveInterval 30 # Keep-Alive Packet every 30 seconds to ensure the connection doesn't terminate"。

- 来源：<https://blog.frost.kiwi/ssh-over-https-tunneling/> （专家文章）

- 置信度：**\[多数来源]**（与官方 3.3 机制一致）

**3.8 OpenSSH 新增了按通道类型清理空闲通道的** **`ChannelTimeout`（客户端与 sshd 均有），例如** **`session=5m`** **会在 5 分钟不活动后结束交互会话，但"终止通道不必然关闭 SSH 连接"。**

- 来源：<https://man.openbsd.org/ssh_config> 、<https://man.openbsd.org/sshd_config> （官方文档）

- 置信度：**\[已确认]**

**3.9 （未验证项）具体代理软件（如 Squid）对 CONNECT 隧道的空闲超时默认值**：本次调研未获得可直接引用的官方数值来源，不作陈述。方向性结论（代理/防火墙普遍存在空闲超时切流）已有 3.1、3.6 佐证。

- 置信度：**\[未验证]**

***

## 4. DNS 解析坑（ProxyCommand 下域名由谁解析）

**4.1 使用 ProxyCommand 后，目的地解析/路由职责转移给了 ProxyCommand 指定的程序。** frost.kiwi："Note how ProxyCommand now determines destination and port... ssh itself is not involved in matters of routing anymore, so neither -p for non-default ports, nor destination after user@ is required."

- 来源：<https://blog.frost.kiwi/ssh-over-https-tunneling/> （专家文章）

- 置信度：**\[多数来源]**（与 4.2、4.3 一致）

**4.2 OpenSSH 官方行为：配置了 ProxyCommand/ProxyJump 的连接默认不做主机名规范化（CanonicalizeHostname）。** ssh\_config 手册："If set to `yes` then, for connections that do not use a `ProxyCommand` or `ProxyJump`, ssh(1) will attempt to canonicalize the hostname... If `CanonicalizeHostname` is set to `always`, then canonicalization is applied to proxied connections too."

- 来源：<https://man.openbsd.org/ssh_config> （官方文档）

- 置信度：**\[已确认]**

**4.3 OpenSSH 官方行为：ProxyCommand 连接下** **`CheckHostIP`** **不可用。** ssh\_config 手册（ProxyCommand 词条）："Note that `CheckHostIP` is not available for connects with a proxy command."（host key 校验基于 Hostname，而非 IP）

- 来源：<https://man.openbsd.org/ssh_config> （官方文档）

- 置信度：**\[已确认]**

**4.4 corkscrew 模式下，目的地主机名是 CONNECT 请求的一部分，由代理解析而非本地。** geekchamp："the destination hostname is sent to the proxy as part of the CONNECT request, so the proxy may resolve it rather than your local machine. If an internal hostname works from the proxy network but not locally, this can be useful."

- 来源：<https://geekchamp.com/using-corkscrew-to-tunnel-ssh-over-http-2/> （专家文章，**仅搜索摘要核对，\[未完全验证]**）

- 置信度：**\[多数来源]**（与 4.5 的官方 nc 手册表述一致）

**4.5 nc(1) 官方手册直接回答了"谁解析"：SOCKS v.4 只能用于目的地可解析为 IPv4 地址的场景（即本地解析），而 4A/5/connect（HTTP CONNECT）等协议"把目的地作为字符串交给远端代理解释"，没有此限制。** 原文："Note that the SOCKS v.4 protocol is very limited and can only be used when the destination host can be resolved to an IPv4 address. The other protocols pass the destination as a string to be interpreted by the remote proxy and do not have this limitation."

- 来源：<https://man.openbsd.org/nc> （官方文档）

- 置信度：**\[已确认]**（本清单中最直接的一手依据）

**4.6 PuTTY 提供"Do DNS name lookup at proxy end"三态选项（No/Yes/Auto，默认 Auto）。** 官方手册："If you set it to 'No', PuTTY will always do its own DNS, and will always pass an IP address to the proxy. If you set it to 'Yes', PuTTY will always pass host names straight to the proxy"；默认 Auto 时"Most types of proxy (HTTP, SOCK5, SSH, Telnet, and local) will have host names passed straight to them; SOCKS4 proxies will not"。另注：SOCKS4 协议本身不支持代理端 DNS，只有 SOCKS4A 扩展支持且并非所有服务器实现。

- 来源：<https://the.earth.li/~sgtatham/putty/0.81/htmldoc/Chapter4.html#config-proxy> （官方文档 4.16.3；Royal Apps 的第三方整理页印证该选项语义 <https://content2.royalapplications.com/Help/RoyalTS/V3/reference_terminalputty_proxysettings.htm> ）

- 置信度：**\[已确认]**

**4.7 SOCKS 工具链中的等价坑：socks4/socks5 为本地解析，socks4a/socks5h 为远端解析。** 社区整理的 curl/代理速查（gist liuyunbin）："socks4 ---- 本地域名解析；socks4a --- 远程域名解析 -- 建议；socks5 ---- 本地域名解析；socks5h --- 远程域名解析 -- 建议"。

- 来源：<https://gist.github.com/liuyunbin/b6b820ecca264e2768e6574dc4235763> （社区整理）

- 置信度：**\[多数来源]**（oneuptime 博客佐证 `curl --socks5-hostname` 由 SSH 服务器端解析、防 DNS 泄漏：<https://oneuptime.com/blog/post/2026-03-20-ssh-socks-proxy-dns-leak-prevention/view> ）

**4.8 ProxyJump 的跳板机主机名由本地解析。** CSDN 问答（问题：`ssh: Could not resolve hostname bastion-host: Name or service not known`）：由于 ProxyJump 在建立隧道前就要完成跳板机地址解析，这一过程完全依赖本地系统 DNS，无法借助远程节点解析。

- 来源：<https://ask.csdn.net/questions/8954105> （社区问答，中文）

- 置信度：**\[单一来源]**（逻辑上与 OpenSSH ProxyJump 实现方式一致，但未见官方手册明文）

**4.9 内网域名能否解析取决于解析位置，常导致"本地解析失败、代理解析成功"的不对称。** geekchamp（4.4）与 ixany.org（"The DNS is by default proxied on Firefox (meaning the names are resolved on the other side of the tunnel)"）都描述了这一差异。

- 来源：<https://geekchamp.com/using-corkscrew-to-tunnel-ssh-over-http-2/> （未完全验证）、<http://www.ixany.org/articles/openssh-tunnels/> （专家文章）

- 置信度：**\[多数来源]**

***

## 5. netcat 变体不兼容坑

**5.1 OpenSSH 官方示例本身就是用 OpenBSD netcat 写的，隐含"必须装对 nc"的前提。** ssh\_config 手册 ProxyCommand 词条示例：`ProxyCommand /usr/bin/nc -X connect -x 192.0.2.0:8080 %h %p`。

- 来源：<https://man.openbsd.org/ssh_config> （官方文档）

- 置信度：**\[已确认]**

**5.2 装错 netcat 变体会直接报** **`nc: invalid option -- 'x'`。** GitHub Gist 评论（zhufengning, 2023-10-12）："Looks like you have the 'traditional' netcat (netcat-traditional) installed. The -x option is available in the OpenBSD netcat (netcat-openbsd)."

- 来源：<https://gist.github.com/chenshengzhi/07e5177b1d97587d5ca0acc0487ad677?permalink_comment_id=4722752> （社区讨论）

- 置信度：**\[多数来源]**

**5.3 "netcat 有两个实现，需要支持 -x 的那个"是普遍经验。** dimoulis.net："We will be using netcat-openbsd, as it's called in Ubuntu and Debian. Apparently there are two implementations of netcat and we want the one that supports the -x 'connect to proxy' parameter."

- 来源：<https://www.dimoulis.net/posts/ssh-over-proxy/> （专家文章）

- 置信度：**\[多数来源]**（与 5.2 独立印证；Debian/Ubuntu 下包名分别为 netcat-openbsd 与 netcat-traditional）

**5.4 各变体的代理参数不通用。** OpenBSD nc 用 `-X 协议 -x 代理地址[:端口]`（协议：4/4A/5/connect，默认 SOCKS5；端口缺省 1080 SOCKS / 3128 HTTPS）；Nmap ncat 用 `--proxy host[:port] --proxy-type http|socks4|socks5`（默认 http，端口缺省 3128 HTTP / 1080 SOCKS）并支持 `--proxy-auth`；GNU/traditional netcat 无代理选项。Ncat 官方指南还指出：IPv6 形式的代理地址必须显式带端口（否则歧义）。

- 来源：<https://man.openbsd.org/nc> 、<https://nmap.org/ncat/guide/ncat-proxy.html> （官方文档）

- 置信度：**\[已确认]**

**5.5 nc 的代理功能与监听类选项互斥。** nc(1)：代理不能与 `-l`、`-s`、`-u`、`-U` 同时使用（"A proxy cannot be used with any of the options -lsuU"）。

- 来源：<https://man.openbsd.org/nc> （官方文档）

- 置信度：**\[已确认]**

**5.6 Windows 下的 nc 构建会被 Windows Defender 标记。** frost.kiwi："Linux, BSD and MacOS have nc preinstalled, which can also be used. But we are ignoring it for brevity, as it's more of a general purpose tool and the windows builds are flagged by Windows Defender."（替代品是随 Git for Windows 附带的 connect.exe）

- 来源：<https://blog.frost.kiwi/ssh-over-https-tunneling/> （专家文章）

- 置信度：**\[单一来源]**

**5.7 选用参考：Debian Wiki 官方手册用** **`nc -X 5 -x 127.0.0.1:9050 %h %p`** **走 Tor SOCKS。**

- 来源：<https://wiki.debian.org/FreedomBox/Manual/SecureShell> （Debian 官方 Wiki）

- 置信度：**\[已确认]**

***

## 6. Windows 平台坑（ProxyCommand 引号/路径、Git Bash/MSYS2）

**6.1 根因（官方依据）：ProxyCommand 是"用用户 shell 的 exec 指令执行"的命令字符串，因此路径与引号规则取决于所用 shell。** ssh\_config 手册："The command string extends to the end of the line, and is executed using the user's shell 'exec' directive to avoid a lingering shell process."

- 来源：<https://man.openbsd.org/ssh_config> （官方文档）

- 置信度：**\[已确认]**（Windows 上 cmd/PowerShell/MSYS bash 的引号语义不同，是社区踩坑的根因）

**6.2 Windows 反斜杠路径会破坏 ProxyCommand：把** **`\`** **改成** **`/`** **即可修复。** open-remote-ssh Issue #309（"ProxyCommand with Windows backslash paths broken by argv tokenizer"）：`ProxyCommand "C:/Program Files/Foo/bar.exe" --config "C:/Users/me/cfg" -W %h:%p` 连接成功，唯一改动是 `\` → `/`；建议在 tokenizer 中不要把 `\` 当转义符。

- 来源：<https://github.com/jeanp413/open-remote-ssh/issues/309> （社区 Issue）

- 置信度：**\[多数来源]**

**6.3 工具自动生成的反斜杠 ProxyCommand 同样破坏 Git Bash 的 SSH。** coder/coder Issue #24205："coder config-ssh on Windows generates \~/.ssh/config entries with backslash paths in ProxyCommand and Match directives"，导致 Git Bash SSH 无法使用。

- 来源：<https://github.com/coder/coder/issues/24205> （社区 Issue）

- 置信度：**\[多数来源]**（与 6.2 独立印证）

**6.4 路径含空格（如 C:\Program Files）+ 引号问题，Git Bash 与 Windows 原生 OpenSSH 的正确写法不同。** Qiita 实践总结：Git Bash 用 `ProxyCommand "C:\Program Files\Git\mingw64\bin\connect.exe" -S socks.example.com:1080 %h:%p`（带引号）；PowerShell/cmd 下不用引号写反斜杠路径；要让两种 ssh 通用的写法是用 8.3 短路径 + 正斜杠：`ProxyCommand C:/PROGRA~1/Git/mingw64/bin/connect.exe -S socks.example.com:1080 %h %p`（PROGRA\~1 避免 Program Files 的空格；connect.exe 不在 PATH，必须写全路径；VSCode Remote Development 默认用的是 Windows 原生 ssh.exe）。

- 来源：<https://qiita.com/umorigu/items/4907187e9f1934ce6b88> （社区实践，日文）

- 置信度：**\[单一来源]**（但给出可复现的完整配置对照）

**6.5 Git Bash 下没有可用的 nc -X/-x，改用 Git for Windows 自带的 connect.exe。** Gist（chenshengzhi）评论区多人记录 Git Bash 中 `nc: invalid option -- 'x'`，最终改用 `connect -H 127.0.0.1:7897 %h %p`（HTTP）或 `-S`（SOCKS）；IdentityFile 需写成 Windows 路径 `"C:\Users\用户名\.ssh\..."`。

- 来源：<https://gist.github.com/chenshengzhi/07e5177b1d97587d5ca0acc0487ad677> （社区讨论）

- 置信度：**\[多数来源]**（与 5.2、5.6 相互印证）

**6.6 Windows 原生 OpenSSH 实现 ProxyJump 的替代写法：用 ssh.exe 自身 -W 转发。** Gist 示例：`ProxyCommand C:\Windows\System32\OpenSSH\ssh.exe -Y {PROXYJUMP USERNAME}@{PROXYJUMP HOSTNAME} -W %h:%p`。

- 来源：<https://gist.github.com/yiays/1a0cc0ca09b0db7c8ff7ff81b56d27ba> （社区 Gist）

- 置信度：**\[单一来源]**

**6.7 Windows 下建议：所有路径用 C:\ 起的绝对路径、含空格加引号，并重新指定 UserKnownHostsFile。** frost.kiwi 的 SSH Config 示例注释："if you are on Windows: use absolute paths for everything starting from C:\ and re-specify the default UserKnownHostsFile"，例如 `UserKnownHostsFile 'C:\Users\frost\.ssh\known_hosts'`。

- 来源：<https://blog.frost.kiwi/ssh-over-https-tunneling/> （专家文章）

- 置信度：**\[单一来源]**

**6.8 GUI 侧替代：PuTTY 的 Local proxy 类型可直接跑本地命令做代理，支持** **`%host/%port/%user/%pass`** **替换；命令行对应** **`-proxycmd`。**

- 来源：<https://the.earth.li/~sgtatham/putty/0.81/htmldoc/Chapter4.html#config-proxy> （官方文档 4.16.1/4.16.5）、<https://documentation.help/PuTTY/using-cmdline-proxycmd.html> （第三方镜像）

- 置信度：**\[已确认]**

## 7. ControlMaster/连接复用与 ProxyJump 的交互问题

**7.1 ControlMaster 的官方语义与"静默回退"坑：复用失败时 ssh 会悄悄退回普通直连。** ssh\_config 手册："Additional sessions can connect to this socket using the same ControlPath with ControlMaster set to no (the default). These sessions will try to reuse the master instance's network connection rather than initiating new ones, **but will fall back to connecting normally if the control socket does not exist, or is not listening**."（即用户以为在复用，实际可能已新建连接——在过代理/堡垒机环境下意味着多走一次代理认证与审计会话。）

- 来源：<https://man.openbsd.org/ssh_config> （官方文档）

- 置信度：**\[已确认]**（括号内"多走一次代理认证"为本清单的合理推论，非手册原文）

**7.2 X11/ssh-agent 转发在复用连接上受限于 master：无法转发多个 display 或 agent。** ssh\_config 手册："X11 and ssh-agent(1) forwarding is supported over these multiplexed connections, however the display and agent forwarded will be the one belonging to the master connection i.e. it is not possible to forward multiple displays or agents."

- 来源：<https://man.openbsd.org/ssh_config> （官方文档）

- 置信度：**\[已确认]**

**7.3 ControlPersist 默认 no；设为 yes/0 则 master 在后台无限期驻留（直到被 kill 或以** **`ssh -O exit`** **关闭）。** ssh\_config 手册："If set to no (the default), then the master connection will not be placed into the background, and will close as soon as the initial client connection is closed. If set to yes or 0, then the master connection will remain in the background indefinitely (until killed or closed via a mechanism such as the 'ssh -O exit')."

- 来源：<https://man.openbsd.org/ssh_config> （官方文档）

- 置信度：**\[已确认]**（长驻 master 与堡垒机会话超时/审计的冲突见 3.6、7.7、10.4）

**7.4 ProxyJump 与 ProxyCommand 互相竞争：同一配置中先出现者生效，后出现的另一个被忽略。** ssh\_config 手册（ProxyJump 词条）："Note that this option will compete with the ProxyCommand option - whichever is specified first will prevent later instances of the other from taking effect."（同时配置两者时只有命令行/配置文件中靠前的那个起作用，是典型的配置顺序坑。）

- 来源：<https://man.openbsd.org/ssh_config> （官方文档）

- 置信度：**\[已确认]**

**7.5 ProxyJump 支持逗号分隔的多跳（按顺序访问）与 ssh URI 语法。** ssh\_config 手册："Specifies one or more jump proxies as either \[user@]host\[:port] or an ssh URI. Multiple proxies may be separated by comma characters and will be visited sequentially."实现方式是"先 ssh 连到 ProxyJump 主机，再从那里建立到最终目标的 TCP 转发"（即基于 `ssh -W` 的 stdio 转发）。

- 来源：<https://man.openbsd.org/ssh_config> （官方文档）

- 置信度：**\[已确认]**

**7.6 跳板机的配置继承坑：目标主机的配置通常不会应用到跳板机。** ssh\_config 手册："Note also that the configuration for the destination host (either supplied via the command-line or the configuration file) is not generally applied to jump hosts. \~/.ssh/config should be used if specific configuration is required for jump hosts."（给跳板机设置专用参数，如代理、密钥、User，需在 \~/.ssh/config 中为跳板机单独写 Host 段。）

- 来源：<https://man.openbsd.org/ssh_config> （官方文档）

- 置信度：**\[已确认]**

**7.7 ProxyJump 场景下连接复用（multiplexing）仍然可用，master 会持有"被代理的连接"；但堡垒机对跳板段强制短超时会导致任务中途失败，此时应对这类主机禁用复用。** deployer.org："If your SSH config uses ProxyJump, multiplexing still works, but the master holds the proxied connection open. That is usually what you want. If your bastion enforces short session timeouts on the jump leg, you may see deploys fail mid-task because the master died on the jump host. Disable multiplexing for those hosts."

- 来源：<https://deployer.org/blog/ssh-multiplexing> （专家文章，Deployer 维护者）

- 置信度：**\[单一来源]**（机制与 3.1 的防火墙空闲切断一致）

**7.8 master 死亡时的一次性报错：`mux_client_request_session: read from master failed`，重跑通常可解决，否则删除 socket 文件。** deployer.org："Re-run usually resolves it. If it does not, just delete the socket file."

- 来源：<https://deployer.org/blog/ssh-multiplexing> （专家文章）

- 置信度：**\[单一来源]**

**7.9 OpenSSH 对 ControlMaster 的支持始于 2005 年。** deployer.org："OpenSSH has supported ControlMaster since 2005."

- 来源：<https://deployer.org/blog/ssh-multiplexing> （专家文章）

- 置信度：**\[单一来源]**

**7.10 官方明示：ssh 不对 ProxyCommand/TOKENS 做 shell 特殊字符的过滤或转义，引号正确性由用户负责——这是 Windows 引号坑（见第 6 节）的官方根因。** ssh\_config 手册（TOKENS 词条）："Note that some of these directives build commands for execution via the shell. Because ssh(1) performs no filtering or escaping of characters that have special meaning in shell commands (e.g. quotes), it is the user's responsibility to ensure that the arguments passed to ssh(1) do not contain such characters and that tokens are appropriately quoted when used."（ProxyJump 接受的 TOKEN 为 %%、%h、%n、%p、%r。）

- 来源：<https://man.openbsd.org/ssh_config> （官方文档）

- 置信度：**\[已确认]**

**7.11 进阶组合：`ProxyUseFdpass`** **+** **`nc -F`** **可让 nc 只完成代理握手、随后把已连接的文件描述符交还 ssh 而非继续中转数据。** ssh\_config："ProxyUseFdpass Specifies that ProxyCommand will pass a connected file descriptor back to ssh(1) instead of continuing to execute and pass data. The default is no."；nc(1) 的 `-F`："Pass the first connected socket using sendmsg(2) to stdout and exit. This is useful in conjunction with -X to have nc perform connection setup with a proxy but then leave the rest of the connection to another program."

- 来源：<https://man.openbsd.org/ssh_config> 、<https://man.openbsd.org/nc> （官方文档）

- 置信度：**\[已确认]**（适用于规避 ProxyCommand 中转进程的开销，但要求 nc 与 ssh 均支持该机制）

***

## 8. Telnet 过代理的方案与特殊性

**8.1 nc(1) 官方将"a SOCKS or HTTP ProxyCommand for ssh(1)"列为常见用途；同一手册指出 telnet(1) 会把部分错误消息打到 stdout、污染数据流，nc 则正确分离到 stderr。** nc(1)："Common uses include: ... a SOCKS or HTTP ProxyCommand for ssh(1)..."；"Unlike telnet(1), nc scripts nicely, and separates error messages onto standard error instead of sending them to standard output, as telnet(1) does with some."

- 来源：<https://man.openbsd.org/nc> （官方文档）

- 置信度：**\[已确认]**（Telnet 客户端 stdout 混入错误消息是脚本化场景的特殊性）

**8.2 Ncat 可将任意 TCP 连接（含 Telnet 的 23 端口）经 SOCKS4/5 或 HTTP 代理路由。** Ncat 官方指南："Ncat can route its connections through a SOCKS 4, SOCKS 5 or HTTP proxy. A basic connection looks like `ncat --proxy <proxyhost>[:<proxyport>] --proxy-type {http|socks4|socks5} <host> [<port>]`."（CONNECT 隧道承载任意 TCP 流量，与目标端口无关。）

- 来源：<https://nmap.org/ncat/guide/ncat-proxy.html> （官方文档）

- 置信度：**\[已确认]**

**8.3 socat 的** **`PROXY:`/`SOCKS:`** **地址类型支持经 HTTP/SOCKS 代理的任意协议连接。** socat 官方手册（PROXY 地址）："PROXY:<proxy>:<hostname>:<port> ... sends a CONNECT request for hostname:port. If the proxy grants access and succeeds to connect to the target, data transfer between socat and the target can start. **Note that the traffic need not be HTTP but can be an arbitrary protocol.**"官方示例集同时给出 SSH 的写法：`ProxyCommand socat - SOCKS:socks.mydomain.org:%h:%p` 与 `ProxyCommand socat - PROXY:proxy.mydomain.org:%h:%p,proxyport=8000`。

- 来源：<http://www.dest-unreach.org/socat/doc/socat.html> （官方手册）、<https://repo.or.cz/socat.git/blob_plain/HEAD:/EXAMPLES> （官方仓库示例集，已验证可访问）

- 置信度：**\[已确认]**

**8.4 socat 官方示例建议"代替 telnet 客户端"连接以避免终端问题。** 官方 EXAMPLES："To avoid terminal problems, you might - instead of telnet - connect using: `socat -,icanon=0,echo=0 TCP:target:5555; reset`"（该示例位于源码包中 poor-mans-telnetd 一节附近）。

- 来源：<https://repo.or.cz/socat.git/blob_plain/HEAD:/EXAMPLES> （官方仓库示例集）

- 置信度：**\[已确认]**

**8.5 socat 穿墙访问内网 Telnet 服务器的"double server/client"模式（官方示例，但位于"Not tested, just ideas"区域）。** 示例：外部客户端 `socat -d TCP-LISTEN:10023,range=localhost TCP-LISTEN:20023`，内部 `socat -d TCP:localhost:23 TCP:extclient:10023`（或 SOCKS 防火墙版 `SOCKS:socksserver:extclient:10023`），最后外部 `telnet localhost 20023` 登录。注意：该示例位于官方示例文件明确标注的 "Not tested, just ideas, or have problems" 区段。

- 来源：<https://repo.or.cz/socat.git/blob_plain/HEAD:/EXAMPLES> （官方仓库示例集；自带"未测试"声明）

- 置信度：**\[单一来源]**（官方来源但自我声明未测试）

**8.6 proxychains 官方以** **`proxychains telnet targethost.com`** **为标准使用示例，Telnet 是其明确点名的适用应用。** proxychains 官方 HowTo："proxychains - a tool that forces any TCP connection made by any given application to follow through proxy like TOR or any other SOCKS4, SOCKS5 or HTTP(S) proxy"；"Usage Example: `bash$ proxychains telnet targethost.com`"；设计动机包括"You may need it when the only way out from your LAN is through proxy server. Or to get out from behind restrictive firewall... And you want to do that with some app like telnet."；认证支持：user/pass（SOCKS4/5）、basic（HTTP）；另附 `proxyresolv` 用于经代理解析 DNS。

- 来源：<http://proxychains.sourceforge.net/howto.html> （官方 README/HowTo）

- 置信度：**\[已确认]**

**8.7 Telnet 协议本身无加密（明文协议）。** RFC 854（TELNET PROTOCOL SPECIFICATION）："The purpose of the TELNET Protocol is to provide a fairly general, bi-directional, eight-bit byte oriented communications facility"、"A TELNET connection is a Transmission Control Protocol (TCP) connection used to transmit data with interspersed TELNET control information."——协议规范中不存在任何加密或认证机制（整个 RFC 无安全层定义）。

- 来源：<https://www.rfc-editor.org/rfc/rfc854> （RFC/标准）

- 置信度：**\[已确认]**

**8.8 PuTTY 官方手册对 Telnet 安全性的直接评价：老协议、安全性极低。** "SSH (which stands for 'secure shell') is a recently designed, high-security protocol. It uses strong cryptography to protect your connection against eavesdropping, hijacking and other attacks. **Telnet, Rlogin, and SUPDUP are all older protocols offering minimal security.**"

- 来源：<https://the.earth.li/~sgtatham/putty/0.81/htmldoc/Chapter1.html#which-one> （官方文档 1.2）

- 置信度：**\[已确认]**

**8.9 （组合推论，非单一直接来源）Telnet 经 HTTP CONNECT 隧道后依然是明文：代理管理员与链路窃听者可见口令与全部会话内容。** 依据：CONNECT 隧道承载任意 TCP 流量、不改变内容（NGINX 官方，见 1.1）+ Telnet 无加密（RFC 854，见 8.7）。SSH 经 CONNECT 有自身加密层，Telnet 经 CONNECT 则完全没有——这是"过代理"并不能弥补 Telnet 弱点的核心区别。

- 来源：组合 <https://docs.nginx.com/nginx/admin-guide/web-server/http-connect-proxy/> 与 <https://www.rfc-editor.org/rfc/rfc854>

- 置信度：**\[多数来源]**（两处官方来源的联合推论，未找到单一来源直接陈述此组合结论）

**8.10 GUI/商业客户端侧的 Telnet 代理差异（详见第 9 节）：SecureCRT 官方功能表明确 HTTP 代理可用于"Telnet, Telnet/TLS (Windows), SSH1, SSH2"；Termius 则声明跳板链（Host Chain）"only available for SSH connection. You can use Port Forwarding for Telnet connections."**

- 来源：<https://www.vandyke.com/products/beta/securecrt/features.html?print=yes> 、<https://termius.com/blog/prepare-to-work-from-home> （厂商资料）

- 置信度：**\[已确认]**

## 9. GUI 客户端的代理支持（PuTTY/SecureCRT/Xshell/MobaXterm/Termius）

**9.1 PuTTY：Proxy 面板提供完整代理类型列表，代理为通用网络层配置。** 官方手册 4.16.1：默认 None；HTTP CONNECT（"as documented in RFC 2817"）；SOCKS 4；SOCKS 5；Telnet；Local；SSH to proxy（执行命令/调用子系统）。面板还提供代理排除列表（4.16.2）、代理解析位置三态（4.16.3，见 4.6）、代理用户名/密码（4.16.4，见 2.9）、代理命令与变量替换（4.16.5）、代理日志（4.16.6）。命令行对应 `-proxycmd` 等。

- 来源：<https://the.earth.li/~sgtatham/putty/0.81/htmldoc/Chapter4.html#config-proxy> （官方文档）

- 置信度：**\[已确认]**

**9.2 PuTTY 的"Telnet 代理类型"指防火墙的 Telnet 式非正式代理（与 Telnet 会话无关的另一个概念，易混淆）。** 官方手册 4.16.1："Many firewalls implement a less formal type of proxy in which a user can make a Telnet or TCP connection directly to the firewall machine and enter a command such as `connect myhost.com 22` to connect through to an external host. Selecting 'Telnet' allows you to tell PuTTY to use this type of proxy"；4.16.5："the usual command required by the firewall's Telnet server is `connect`, followed by a host name and a port number"，命令可自定义。

- 来源：<https://the.earth.li/~sgtatham/putty/0.81/htmldoc/Chapter4.html#config-proxy> （官方文档）

- 置信度：**\[已确认]**

**9.3 PuTTY：代理命令变量替换仅 Telnet 与 Local 代理类型支持 %user/%pass，SSH 代理类型不支持（因其用户名/密码用于 SSH 认证）。** 官方手册 4.16.5："For Telnet and Local proxy types, the strings %user and %pass will be replaced by the proxy username and password (which, if not specified in the configuration, will be prompted for) – this does not happen with SSH proxy types."（另支持 %host、%port、%proxyhost、%proxyport，%% 转义。）

- 来源：<https://the.earth.li/~sgtatham/putty/0.81/htmldoc/Chapter4.html#config-proxy> （官方文档）

- 置信度：**\[已确认]**

**9.4 MobaXterm：官方 FAQ 确认自 6.6 版起可在 SSH 会话中直接设置 SOCKS 代理。** "Can I perform a SSH connection through my SOCKS proxy? Yes, since version 6.6 of MobaXterm, this feature can be set directly in your SSH sessions."

- 来源：<https://mobaxterm.mobatek.net/documentation.html> （厂商资料/官方文档）

- 置信度：**\[已确认]**（注意：官方 FAQ 仅明确"SSH 会话 + SOCKS 代理"这一个组合；MobaXterm 是否支持 HTTP 代理、以及 Telnet 会话能否走代理，官方文档未提及，**\[未完全验证]**）

**9.5 SecureCRT：官方功能页列出完整防火墙/代理矩阵——SOCKS v4/v5、TIS/Wingate、HTTP（CONNECT）、Local proxy command、命名防火墙。** 官方功能页（SecureCRT 9.7）原文：

- "SOCKS v4 and v5: Support for both SOCKS v4 and v5 for use with Telnet, Telnet/TLS (Windows), SSH1, or SSH2. When using SOCKS v5, optional firewall authentication is supported."

- "TIS and Wingate proxy: Generic proxies from the TIS firewall toolkit and Wingate are supported for use with Telnet."

- "HTTP proxy: Telnet, Telnet/TLS (Windows), SSH1, and SSH2 connections can be configured to connect via an HTTP proxy that supports the Connect command. Proxy setup is simplified with support for unauthenticated and basic HTTP proxies."

- "Local proxy command"（本地代理命令）

- "Named firewalls: Name different firewall configurations and use them on an individual session basis."（每个会话可选用不同的防火墙配置）

- 保活功能："send a user-defined sequence after a specified interval to eliminate idle disconnections"（定时发送用户自定义序列以消除空闲断连）

- 来源：<https://www.vandyke.com/products/beta/securecrt/features.html?print=yes> （厂商资料）

- 置信度：**\[已确认]**

**9.6 SecureCRT：防火墙在 Global Options > Firewall 类别中定义，然后在各会话的 Session Options（Connection > 相应协议 > Firewall 下拉）中选择。** VanDyke 官方支持论坛工作人员答复："You can configure firewall/proxy in the Firewall category of SecureCRT's Global Options. Then choose the defined firewall in the Firewall dropdown of the Connection / SSH2 category of Session Options."论坛同期讨论还记录了旧版 SecureCRT 不支持 HTTP 代理时报错 "Invalid Firewall Type... Valid types are: Generic proxy, SocksV4 and SocksV5"。

- 来源：<https://forums.vandyke.com/showthread.php?t=6386> 、<https://forums.vandyke.com/showthread.php?p=6787> （厂商支持论坛）

- 置信度：**\[多数来源]**（官方人员答复）

**9.7 Xshell：官方手册有专门的 Connection > PROXY 会话设置页；官方特性页列出 SOCKS4/5、HTTP 代理与跳板机代理。** Xshell 6 User Guide："Connection > PROXY — Proxy Server: Select a proxy server to use in this session. For details on proxy setting, see 'Proxy Setting'."；特性列表包含"SOCKS4/5, HTTP proxy connection"、"Dynamic port forwarding using SOCKS4/5"、"Jump Host Proxy: Supports SSH1, SSH2, SFTP, TELNET, RLOGIN, SERIAL, and RDP protocols"。

- 来源：<https://cdn.netsarang.net/docs/Xshell6_manual.pdf> （厂商资料/官方手册）、<https://www.xshell.com/en/xshell-all-features/> （厂商资料）

- 置信度：**\[已确认]**

**9.8 Termius：支持 HTTP/SOCKS 代理（Host 编辑界面）；跳板链 Host Chain 等效** **`-J`/ProxyJump，但仅适用于 SSH 连接，Telnet 需改用端口转发。** Termius 官方博客："Termius supports Bastion or Jump hosts via the Host Chain feature. Host Chain provides the same functionality as the -J argument in ssh and ProxyJump option in \~/.ssh/config. **Those options are only available for SSH connection. You can use Port Forwarding for Telnet connections.**"以及"4.2 HTTP / SOCKS Proxy: Go to the Host Edit screen to set up a connection to a host via HTTP/SOCKS Proxy."

- 来源：<https://termius.com/blog/prepare-to-work-from-home> （厂商资料）

- 置信度：**\[已确认]**

**9.9 跨客户端对照结论（综合上述来源）：PuTTY、SecureCRT、Xshell、Termius 均有内建代理支持且官方文档明确；MobaXterm 官方文档仅确认 SSH 会话的 SOCKS 代理一项；命令行工具链（corkscrew/ncat/socat/connect.exe + ProxyCommand）是所有 GUI 之外的通用替代路径，但需要自行处理认证、引号、路径与变体兼容问题（见第 2、5、6 节）。**

- 来源：综合 9.1–9.8

- 置信度：**\[多数来源]**（综合归纳，各单项见对应条目）

***

## 10. 堡垒机（跳板机）场景下的审计/合规考虑

**10.1 堡垒机的定位与审计前提：所有经过它的连接都被记录。** JumpServer 官方博客："A bastion host is a specially hardened server that sits at the boundary between a public network (the internet) and a private internal network. Its sole purpose is to provide controlled, auditable access to systems that would otherwise be unreachable from the outside world."以及"**Every connection through it is logged.**"

- 来源：<https://www.jumpserver.com/blog/what-is-a-bastion-host/> （厂商资料）

- 置信度：**\[已确认]**

**10.2 堡垒机审计/监控层的具体构成（JumpServer 的四层架构之一）。** "Layer 4 — Audit and Monitoring. Every session is logged with timestamp, user identity, source IP, and target host. Session recordings (keystroke logs or screen replays) are stored in tamper-resistant storage. Alerts fire on anomalous behavior: off-hours logins, new source IPs, bulk file transfers, or repeated authentication failures."

- 来源：<https://www.jumpserver.com/blog/what-is-a-bastion-host/> （厂商资料）

- 置信度：**\[已确认]**

**10.3 认证控制层要求：禁用密码登录、强制密钥/证书 + MFA、禁止共享账号。** "Password-based authentication is disabled. SSH key pairs or certificate-based authentication is mandatory. MFA ... adds a second factor before any session is granted. Shared accounts are prohibited — every administrator authenticates with their own identity."

- 来源：<https://www.jumpserver.com/blog/what-is-a-bastion-host/> （厂商资料）

- 置信度：**\[已确认]**

**10.4 堡垒机是"单一策略执行点"：MFA、IP 白名单、会话超时（session timeouts）、访问授权在同一网关对所有人生效——"no exceptions, no workarounds"（无例外、无绕过）。** "Single policy enforcement point. MFA, IP allowlisting, session timeouts, and access authorization policies apply to everyone at the same gateway — no exceptions, no workarounds."（注意：正是这里的"会话超时"策略与本清单 3.6/7.7 的 ControlMaster 长连接复用产生直接冲突。）

- 来源：<https://www.jumpserver.com/blog/what-is-a-bastion-host/> （厂商资料）

- 置信度：**\[已确认]**

**10.5 凭据隔离原则：内部服务器凭据不离开私网边界，管理员认证到堡垒机而非直接到生产系统。** "Credential isolation. Internal server credentials never leave the private network perimeter. Administrators authenticate to the bastion, not directly to production systems."

- 来源：<https://www.jumpserver.com/blog/what-is-a-bastion-host/> （厂商资料）

- 置信度：**\[已确认]**

**10.6 现代 PAM 平台在经典堡垒机概念上内建会话录制、MFA、细粒度授权。** "Modern PAM platforms like JumpServer extend the classic bastion host concept with session recording, MFA, and fine-grained authorization built in."

- 来源：<https://www.jumpserver.com/blog/what-is-a-bastion-host/> （厂商资料）

- 置信度：**\[已确认]**

**10.7 云厂商堡垒机的"代理式"接入形态：阿里云堡垒机支持把已建立的堡垒机隧道会话配置为 SSH 代理（透明代理模式）。** 阿里云文档（堡垒机用户指南）：在 SSH-Proxy 菜单点击 Browse 配置 Proxy server，"Click Session to add a proxy. In the session list that appears, select the previously established bastion host tunnel session to use as the proxy."（即"经堡垒机"在这里本身就是一种代理链配置。）

- 来源：<https://www.alibabacloud.com/help/en/bastionhost/user-guide/transparent-proxy> （厂商资料；仅核对搜索摘要与文档目录，**\[未完全验证]**）

- 置信度：**\[单一来源]\[未完全验证]**

**10.8 （审计视角的坑，组合推断）SSH/Telnet 的代理连通性与"绕过堡垒机审计"之间存在天然张力：ProxyCommand/corkscrew/proxychains 等技术使客户端可以不经过堡垒机直达内网目标。** 若企业出口代理对内网 22/23 端口开放 CONNECT（第 1 节讨论的端口白名单通常不会放行，反向构成保护），或用户以 HTTP-over-443 隧道（1.6）等方式穿越，则该路径不经过堡垒机的会话录制与审计（10.1/10.2 的前提被破坏）。

- 来源：组合推断：<https://www.jumpserver.com/blog/what-is-a-bastion-host/> 的审计前提 + 本清单第 1 节的代理连通性事实

- 置信度：**\[推断]**（未见单一来源直接陈述"代理隧道绕过堡垒机审计"；逻辑由两部分已验证事实组合而成，作为风险提示而非已证实事件）

**10.9 （审计粒度，组合推断）ControlMaster 连接复用会改变堡垒机看到的"会话"粒度：多个逻辑会话共享一条 master 连接时，堡垒机侧通常只看到一条长 TCP/SSH 会话。** 基于 ControlMaster 官方语义"Enables the sharing of multiple sessions over a single network connection"（7.1）与堡垒机按会话记录/录制的审计模型（10.2）的组合：按会话计数的审计报表可能低估实际操作次数，部署工具类高频短会话场景尤甚。

- 来源：组合推断：<https://man.openbsd.org/ssh_config> + <https://www.jumpserver.com/blog/what-is-a-bastion-host/>

- 置信度：**\[推断]**（未见来源直接讨论该组合；标记为推测，供合规设计时考量）

**10.10 （实践印证）"合规的短超时"与"工程的连接复用"冲突已在部署工具实践中被点名。** deployer.org：堡垒机在跳板段强制短会话超时会导致复用 master 死亡、部署中途失败，工程上的应对是对这类主机禁用 multiplexing（`set('ssh_multiplexing', false)`）——这是审计策略（10.4）与连接复用（第 7 节）直接冲突的一手案例。

- 来源：<https://deployer.org/blog/ssh-multiplexing> （专家文章）

- 置信度：**\[单一来源]**（机制与 3.1 官方描述一致）

***

## 11. 未能验证/需复核事项汇总

以下内容在本轮调研中未获得可直接引用的可靠来源，使用前需自行验证：

1. **Squid 等具体代理软件对 CONNECT 隧道的空闲超时默认值**（见 3.9）——未获得官方默认数值来源。
2. **geekchamp.com 的 corkscrew 系列文章全文**（见 2.3、2.4、4.4）——受 Cloudflare 保护无法直接抓取，仅以搜索摘要核对，已标注 \[未完全验证]。
3. **corkscrew 与 Microsoft Proxy Server 的认证兼容性问题细节**（见 2.2）——官方 README 有提及但未展开，未找到进一步的权威复现记录。
4. **MobaXterm 对 HTTP 代理及 Telnet 会话代理的支持**（见 9.4）——官方 FAQ 仅确认 SSH 会话 + SOCKS 代理。
5. **Xshell 7/8 最新版手册中的代理设置差异**（见 9.7）——本清单引用的是官方 Xshell 6 手册 PDF 与官方特性页。
6. **SSH over HTTPS 隧道工具（GhostSSH、proxytunnel、sslh）的当前维护状态**（见 1.6）——仅确认项目存在与用途，未逐一验证其维护活跃度。
7. **堡垒机厂商对"客户端代理连接复用"的官方立场**（见 10.9）——JumpServer、阿里云等厂商文档未直接讨论 ControlMaster 复用对会话审计粒度的影响。
8. **Windows OpenSSH 官方对 ProxyCommand 引号语义的正式说明**（见第 6 节）——OpenSSH for Windows 的 Release Notes 未逐条检索，Windows 侧引号行为主要来自社区 Issue 与实践总结。

