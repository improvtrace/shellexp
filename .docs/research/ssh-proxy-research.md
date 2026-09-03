# SSH 通过代理连接远程主机：经典与原生方案调研事实清单

**调研日期**：2026-09-03
**来源类型标注**：[官方文档]（项目/厂商一手文档、man page、release notes）、[权威技术资料]（Nmap 开发者 wiki、发行版软件包文档等）、[权威博客]（知名安全/基础设施公司技术文章）、[社区]（社区经验，佐证性来源）
**说明**：以下所有引号内文字均为来源原文（英文），中文为对事实的转述；不确定内容单独标注 ⚠️。

---

## 一、OpenSSH 原生能力：ProxyCommand、ProxyJump、Match exec

### ProxyCommand（机制与官方定义）

1. **机制（stdin/stdout 桥接）**：ssh_config(5) 官方定义："Specifies the command to use to connect to the server. The command string extends to the end of the line, and is executed using the user's shell 'exec' directive to avoid a lingering shell process."（命令串以用户 shell 的 `exec` 执行，避免残留 shell 进程）；"The command can be basically anything, and should read from its standard input and write to its standard output."——即 ProxyCommand 指定的命令**从标准输入读取、向标准输出写入**，由 ssh 负责把该命令的 stdin/stdout 桥接到 SSH 协议流上。
   来源：https://man.openbsd.org/ssh_config ［官方文档］

2. **官方建议与 nc 配合**：同一 man page 明确写道："This directive is useful in conjunction with nc(1) and its proxy support." 并给出官方示例：
   ```
   ProxyCommand /usr/bin/nc -X connect -x 192.0.2.0:8080 %h %p
   ```
   来源：https://man.openbsd.org/ssh_config ［官方文档］

3. **Token 展开**：ProxyCommand 参数支持 TOKENS 运行时展开，其中 `%h` = "The remote hostname"（远程主机名）、`%p` = 远程端口。
   来源：https://man.openbsd.org/ssh_config（TOKENS 一节）［官方文档］

4. **其他细节**：ProxyCommand 设为 `none` 可完全禁用该选项；"CheckHostIP is not available for connects with a proxy command"（走代理命令的连接不可用 CheckHostIP）。
   来源：https://man.openbsd.org/ssh_config ［官方文档］

5. **ProxyUseFdpass 机制补充**：ssh_config(5) 另有 `ProxyUseFdpass` 选项，"Specifies that ProxyCommand will pass a connected file descriptor back to ssh(1) instead of continuing to execute and pass data."（让 ProxyCommand 直接回传已连接的文件描述符，而不是持续桥接数据）。
   来源：https://man.openbsd.org/ssh_config ［官方文档］

### ProxyJump（引入版本与定义）

6. **引入版本：OpenSSH 7.3（2016-08-01 发布）**。官方 release notes 原文："ssh(1): Add a ProxyJump option and corresponding -J command-line flag to allow simplified indirection through a one or more SSH bastions or 'jump hosts'."
   来源：https://www.openssh.com/txt/release-7.3 ［官方文档］

7. **官方定义**：ssh_config(5)："Specifies one or more jump proxies as either `[user@]host[:port]` or an ssh URI. Multiple proxies may be separated by comma characters and will be visited sequentially."（跳板可用 `[user@]host[:port]` 或 ssh URI 表示；多个跳板以逗号分隔、按顺序访问）；"Setting this option will cause ssh(1) to connect to the target host by first making an ssh(1) connection to the specified ProxyJump host and then establishing a TCP forwarding to the ultimate target from there."（先 ssh 连到跳板，再从跳板向最终目标建立 TCP 转发）。
   来源：https://man.openbsd.org/ssh_config ［官方文档］

8. **与 ProxyCommand 的竞争关系（官方原文）**："this option will compete with the ProxyCommand option - whichever is specified first will prevent later instances of the other from taking effect."（两者相互竞争，先出现者生效）；"the configuration for the destination host (either supplied via the command-line or the configuration file) is not generally applied to jump hosts. ~/.ssh/config should be used if specific configuration is required for jump hosts."（命令行/配置里给目标主机的配置一般不作用于跳板主机，跳板的专属配置应写入 ~/.ssh/config）。
   来源：https://man.openbsd.org/ssh_config ［官方文档］

9. **命令行 -J**：ssh(1) 手册：`-J destination`——"Connect to the target host by first making an ssh connection to the jump host described by destination and then establishing a TCP forwarding to the ultimate destination from there. Multiple jump hops may be specified separated by comma characters... This is a shortcut to specify a ProxyJump configuration directive."（-J 是 ProxyJump 指令的快捷方式；多个跳板用逗号分隔）。
   来源：https://man.openbsd.org/ssh ［官方文档］

10. **ssh -W（stdio 转发，ProxyJump 的底层原语之一）**：ssh(1) 手册：`-W host:port`——"Requests that standard input and output on the client be forwarded to host on port over the secure channel. Implies -N, -T, ExitOnForwardFailure and ClearAllForwardings."（把客户端标准输入/输出经安全通道转发到 host:port）。
    来源：https://man.openbsd.org/ssh ［官方文档］

11. **ProxyJump 与 `ssh -W` 的等价性**："The most common form uses SSH's own -W option to forward the connection through the intermediate host, which is effectively what ProxyJump does under the hood."（ProxyJump 底层实现等价于 `ProxyCommand ssh -W %h:%p jump`）。
    来源：https://goteleport.com/blog/ssh-proxyjump-ssh-proxycommand/ ［权威博客］

### Match exec（条件配置）

12. **官方定义**：ssh_config(5)："The exec keyword executes the specified command under the user's shell. If the command returns a zero exit status then the condition is considered true. Commands containing whitespace characters must be quoted. Arguments to exec accept the tokens described in the TOKENS section."（exec 关键字在用户 shell 下执行指定命令，退出码为 0 时条件成立；含空格须加引号；参数支持 token 展开）。Match 可用条件包括 canonical、final、exec、localnetwork、host、originalhost、user、localuser 等。
    来源：https://man.openbsd.org/ssh_config ［官方文档］

13. **条件跳板示例（权威博客）**：用 Match exec 按环境变量决定是否走跳板：
    ```
    Match host target.internal exec "test -z \"$INSIDE_NETWORK\""
    ProxyJump jump.example.com
    ```
    "The Match directive with an exec test runs a command and applies the block only when that command succeeds, which lets you set ProxyJump dynamically instead of hardcoding it."
    来源：https://goteleport.com/blog/ssh-proxyjump-ssh-proxycommand/ ［权威博客］

---

## 二、nc/netcat 家族差异

### OpenBSD netcat（nc，多数 Linux 发行版的 netcat-openbsd）

14. **-X 指定代理协议**：nc(1) 手册："Use proxy_protocol when talking to the proxy server. Supported protocols are `4` (SOCKS v.4), `4A` (SOCKS v.4A), `5` (SOCKS v.5) and `connect` (HTTPS proxy). If the protocol is not specified, SOCKS version 5 is used."（支持 SOCKS4/4A/5 与 HTTP CONNECT；缺省 SOCKS5）；另注明 "the SOCKS v.4 protocol is very limited and can only be used when the destination host can be resolved to an IPv4 address"（SOCKS4 要求目标可解析为 IPv4 地址，其余协议把目标以字符串交给代理解析）。
    来源：https://man.openbsd.org/nc ［官方文档］

15. **-x 指定代理地址**："Connect to destination using a proxy at proxy_address and port. If port is not specified, the well-known port for the proxy protocol is used (1080 for SOCKS, 3128 for HTTPS)."
    来源：https://man.openbsd.org/nc ［官方文档］

16. **-P 代理认证**："Specifies a username to present to a proxy server that requires authentication... Proxy authentication is only supported for HTTP CONNECT proxies at present."（nc 的代理认证目前仅支持 HTTP CONNECT 代理）。
    来源：https://man.openbsd.org/nc ［官方文档］

17. **nc(1) 官方用途清单**中包含 "a SOCKS or HTTP ProxyCommand for ssh(1)"；并给出官方示例：
    ```
    $ nc -x10.2.3.4:8080 -Xconnect host.example.com 42
    $ nc -x10.2.3.4:8080 -Xconnect -Pruser host.example.com 42   # 带认证
    ```
    来源：https://man.openbsd.org/nc ［官方文档］

18. **-F 与 ProxyUseFdpass 配合**：nc 的 `-F` 把第一个已连接 socket 经 sendmsg(2) 传给 stdout 后退出，"useful in conjunction with -X to have nc perform connection setup with a proxy but then leave the rest of the connection to another program (e.g. ssh(1) using the ssh_config(5) ProxyUseFdpass option)."
    来源：https://man.openbsd.org/nc ［官方文档］

### GNU netcat 与传统（traditional）netcat 缺少代理支持

19. **传统 netcat 无代理支持**：Nmap 开发者维护的兼容性 wiki 明确写道："OpenBSD netcat supports proxy connections, and all of its options are different than Ncat's. Traditional netcat does not support proxy connections."（传统 netcat 不支持代理连接）。
    来源：https://secwiki.org/w/Ncat/Compatibility ［权威技术资料（Nmap/Ncat 开发者 wiki）］

20. **传统 netcat man page 佐证**：Debian 归档的 traditional netcat（原 *Hobbit* 版 nc 1.10）man page 的选项表中完全不存在 `-X`/`-x`/proxy 相关选项或字样（经全文检索验证）。
    来源：https://manpages.debian.org/jessie/netcat-traditional/netcat.1.en.html ［官方文档（发行版 man page）］

21. **GNU Netcat 特性列表无代理功能**：GNU Netcat 官方首页列出的主要特性（TCP/UDP 收发连接、tunneling mode（指本地端口/UDP-TCP 转发，非代理协议）、端口扫描、缓冲发送、hexdump、telnet 解析）中不包含任何 SOCKS/HTTP 代理客户端能力。
    来源：http://netcat.sourceforge.net/ ［官方文档（GNU Netcat 官网）］

22. **社区佐证**：第三方速查表也标注 `-X`/`-x` "supported in the OpenBSD version of Netcat (and tools like Ncat from Nmap), but not in the traditional GNU version"。
    来源：https://www.blackhillsinfosec.com/netcat-cheatsheet/ ［社区］

### ncat（Nmap 出品）

23. **--proxy / --proxy-type 用法（官方）**："Ncat can route its connections through a SOCKS 4, SOCKS 5 or HTTP proxy." 基本形式：
    ```
    ncat --proxy <proxyhost>[:<proxyport>] --proxy-type {http|socks4|socks5} <host> [<port>]
    ```
    "--proxy-type may be omitted; it defaults to http. If <proxyport> is omitted, it defaults to the well-known port for the chosen proxy type: 1080 for SOCKS and 3128 for HTTP."
    来源：https://nmap.org/ncat/guide/ncat-proxy.html ［官方文档（Ncat Users' Guide）］

24. **--proxy-auth**："Use --proxy-auth <username>:<password> for HTTP and SOCKS5 proxies and --proxy-auth <username> for SOCKS4 proxies."（HTTP 与 SOCKS5 用 user:pass，SOCKS4 只用用户名）；HTTP 认证 "both the Basic and Digest authentication schemes are supported, as both a client and a server"，客户端优先 Digest。
    来源：https://nmap.org/ncat/guide/ncat-proxy.html ［官方文档］

25. **ncat 自身可作为代理服务器**（仅 http 类型）：`ncat -l 3128 --proxy-type http`（及 `--proxy-auth` 要求认证）；作为客户端连接时使用 CONNECT 方法。
    来源：https://nmap.org/ncat/guide/ncat-proxy.html ［官方文档］

26. **ncat 作为 SSH ProxyCommand 的官方示例**：
    ```
    ssh -o ProxyCommand="ssh -q <router> ncat %h %p" <host>
    ```
    （先 ssh 到路由器，再在其上用 ncat 连目标——即"跳板上跑 nc/ncat"的经典模式）。
    来源：https://nmap.org/ncat/guide/ncat-tricks.html ［官方文档］

27. **家族差异总结**：三套实现（traditional/GNU、OpenBSD nc、ncat）中，代理客户端能力仅 OpenBSD nc（-X/-x/-P）与 ncat（--proxy 系长选项）具备，且二者代理选项语法完全不同；traditional/GNU netcat 均无代理支持。
    来源：https://secwiki.org/w/Ncat/Compatibility ［权威技术资料］；https://man.openbsd.org/nc ［官方文档］

---

## 三、corkscrew（HTTP CONNECT 隧穿 SSH）

28. **定位**：官方 README："Corkscrew is a tool for tunneling SSH through HTTP proxies, but ...you might find another use for it."（专用于通过 HTTP 代理隧道传输 SSH）。
    来源：https://github.com/patpadgett/corkscrew ［官方文档（原作者维护仓库）］

29. **用法（官方示例）**：在 ~/.ssh/config 中添加：
    ```
    ProxyCommand /usr/local/bin/corkscrew proxy.example.com 8080 %h %p
    ```
    来源：https://github.com/patpadgett/corkscrew ［官方文档］

30. **语法变更**："Command line syntax has changed since version 1.5. Please notice that the proxy port is NOT optional anymore and is required in the command line."（1.5 版起代理端口为必填参数）。
    来源：https://github.com/patpadgett/corkscrew ［官方文档］

31. **代理认证支持**：通过认证文件提供（格式 `username:password`，建议放 ~/.ssh 并 `chmod 600`）：
    ```
    ProxyCommand /usr/local/bin/corkscrew proxy.work.com 80 %h %p ~/.ssh/myauth
    ```
    README 同时提醒："The proxy authentication feature is very new and has not been tested extensively so your mileage may vary."（认证特性较新、未经充分测试），且记录了对 Microsoft Proxy Server 的认证存在偶发问题。
    来源：https://github.com/patpadgett/corkscrew ［官方文档］

32. **兼容性记录**：官方 README 记载已测试的 HTTP 代理包括 Gauntlet、CacheFlow、JunkBuster、Apache mod_proxy；可编译平台包括 HPUX、Solaris、FreeBSD、OpenBSD、Linux、Win32（Cygwin）、macOS。
    来源：https://github.com/patpadgett/corkscrew ［官方文档］

33. **仅支持 HTTP CONNECT、不支持 SOCKS**：README 全文只描述 HTTP 代理（含上文认证文件走 HTTP 基本认证），未提供任何 SOCKS 参数。⚠️ 注意：这是基于官方 README 的"未提供"推断（absence of feature），并非一句逐字声明。
    来源：https://github.com/patpadgett/corkscrew ［官方文档 + 推断，见"不确定内容"］

34. **分发沿革**：原发布站为 agroman.net（作者 Pat Padgett），现 README 声明 "Corkscrew's primary distribution site is: https://github.com/patpadgett/corkscrew"。⚠️ 原 agroman.net 站点现状未逐一验证（社区普遍报告已失效）。
    来源：https://github.com/patpadgett/corkscrew ［官方文档 + 社区，见"不确定内容"］

---

## 四、connect-proxy（connect.c，作者 Shun-ichi Goto）

35. **定位（官方手册原文）**："`connect.c` is a simple relaying command to make network connection via SOCKS and https proxy. It is mainly intended to be used as proxy command of OpenSSH. You can make SSH session beyond the firewall with this command."（作为 OpenSSH ProxyCommand 使用的简易中继命令，经 SOCKS 与 https 代理建立网络连接）。
    来源：https://github.com/gotoh/ssh-connect（doc/manual.txt 与 README.md）［官方文档（作者仓库）］

36. **功能清单（官方）**：
    - "Supports SOCKS (version 4/4a/5) and https CONNECT method."（同时支持 SOCKS4/4a/5 与 HTTP CONNECT）
    - "Supports NO-AUTH and USERPASS authentication of SOCKS5"
    - "You can input password from tty, `ssh-askpass` or environment variable."
    - "Run on UNIX or Windows platform."（含 Windows 预编译二进制）
    来源：https://github.com/gotoh/ssh-connect ［官方文档］

37. **基本用法（官方示例）**：
    ```
    Host remote.outside.net
      ProxyCommand connect -S socks.local.net %h %p      # SOCKS
    Host *
      ProxyCommand connect -H proxy.local.net:8080 %h %p # HTTP 代理
    ```
    `-H` 指定 http 代理（缺省端口 80），`-S` 指定 SOCKS 服务器（缺省端口 1080）；`%h`/`%p` 由 ssh 展开为目标主机与端口。
    来源：https://github.com/gotoh/ssh-connect ［官方文档］

38. **其余选项**：`-4`/`-5` 选择 SOCKS 版本（须与 -S 连用）；`-R local|remote|both` 决定域名解析位置（"On SOCKS4 protocol, remote resolving method (remote and both) use protocol version 4a"——SOCKS4 下远程解析走 4a 协议）；用户名/密码可用环境变量 `SOCKS5_USER`、`SOCKS5_PASSWD`、`HTTP_PROXY_USER`、`HTTP_PROXY_PASSWORD`、`CONNECT_USER`/`CONNECT_PASSWORD` 等指定。
    来源：https://github.com/gotoh/ssh-connect ［官方文档］

39. **认证限制（官方 Limitations）**："Only NO-AUTH and USER/PASSWORD authentications are supported. GSSAPI authentication (RFC 1961) and other draft authentications (CHAP, EAP, MAF, etc.) is not supported."；HTTP 侧 "BASIC authentication is supported but DIGEST authentication is not."（SOCKS5 仅 NO-AUTH/USERPASS；HTTP 仅 BASIC，不支持 DIGEST）。
    来源：https://github.com/gotoh/ssh-connect ［官方文档］

40. **与 OpenSSH 的历史关系（官方手册叙述）**："OpenSSH development team decides to stop supporting SOCKS and any other tunneling mechanism. It was aimed to separate complexity to support various mechanism of proxying from core code. And they recommends more flexible mechanism: ProxyCommand option instead."（OpenSSH 决定不在核心代码里支持 SOCKS 等隧道机制，改以 ProxyCommand 外部委托）；"Proxy command mechanism is delegation of network stream communication... Invoked command undertakes network communication with relaying to/from standard input/output including initial communication or negotiation for proxying."——与 ssh_config(5) 的 ProxyCommand 机制描述一致。
    来源：https://github.com/gotoh/ssh-connect ［官方文档（作者视角的二手叙述，见"不确定内容"）］

41. **发行版打包名**：Debian 打包为 `connect-proxy`，包描述："Establish TCP connection using SOCKS4/5 or HTTP tunnel / connect-proxy is a simple relaying command to make tunnel TCP connection via SOCKS or HTTPS proxies. It is mainly intended to be used as proxy command of OpenSSH."；Debian man page 名即 "connect-proxy — connect over SOCKS4/5 proxy"，并记录早期项目主页为 `http://www.meadowy.org/~gotoh/projects/connect`（旧站已失效）。
    来源：https://packages.debian.org/testing/net/connect-proxy ［官方文档（Debian 软件包）］；https://manpages.debian.org/jessie/connect-proxy/connect.1.en.html ［官方文档（Debian man page）］

42. **与 PuTTY 的关系**：
    - connect.c 官方手册称其 "Run on UNIX or Windows platform"，并提供 MS Windows 预编译二进制（MSVC/Borland C/Cygwin 均可编译）。
      来源：https://github.com/gotoh/ssh-connect ［官方文档］
    - PuTTY 官方文档（Proxy 面板）表明 PuTTY **原生内置**代理支持：代理类型包括 HTTP CONNECT（"proxy your connections through a web server supporting the HTTP CONNECT command, as documented in RFC 2817"）、SOCKS 4、SOCKS 5、Telnet、"SSH to proxy and use port forwarding"（文档明言 "similar to OpenSSH's -J option"）以及 **Local** 类型；其中 Local 类型 "allows you to specify an arbitrary command on the local machine to act as a proxy... PuTTY runs the command... and uses its standard input and output streams"——即 PuTTY 版的 ProxyCommand 等价机制。
      来源：https://the.earth.li/~sgtatham/putty/0.81/htmldoc/Chapter4.html（4.16.1 / 4.16.5 节）［官方文档（PuTTY User Manual）］
    - ⚠️ 社区常见的说法是"connect.exe 在 Windows 上常被用作 PuTTY 的 Local proxy command /配合 PuTTY 使用"。PuTTY 官方文档与 connect.c 官方手册均**未直接点名** connect.c 与 PuTTY 的配合；此关联属于社区使用惯例，见"不确定内容"。

---

## 五、socat 用于代理转发

43. **HTTP 代理（PROXY 地址类型，官方）**：`PROXY:<proxy>:<hostname>:<port>`——"Connects to an HTTP proxy server on port 8080 using TCP/IP version 4 or 6 ... and sends a CONNECT request for hostname:port. If the proxy grants access and succeeds to connect to the target, data transfer between socat and the target can start... Note that the traffic need not be HTTP but can be an arbitrary protocol."（socat 作为 HTTP 代理客户端发 CONNECT；代理建立后承载任意协议——当然包括 SSH）。可用地址选项包括 `proxyport`（改代理端口，缺省 8080）、`proxy-authorization=<username>:<password>`（Basic 认证，base64 编码可被嗅探）、`proxy-authorization-file=<filename>`（凭据从文件读取，避免出现在进程列表）、`resolve`（本地解析后向代理发 IP）、`ignorecr`（容错非标准代理的行结尾）。
    来源：http://www.dest-unreach.org/socat/doc/socat.html ［官方文档（socat man page）］

44. **SOCKS 客户端地址类型（官方）**：
    - `SOCKS4:<socks-server>:<host>:<port>`——"using socks version 4 protocol"；
    - `SOCKS4A:<socks-server>:<host>:<port>`——"like SOCKS4, but uses socks protocol version 4a, thus leaving host name resolution to the socks server."（把域名解析交给代理端）；
    - `SOCKS5-CONNECT:<socks-server>:<socks-port>:<target-host>:<target-port>`——"using socks version 5 protocol over TCP. Currently no authentication mechanism is provided."（当前不提供认证）。
    来源：http://www.dest-unreach.org/socat/doc/socat.html ［官方文档］

45. **官方示例（经 HTTP 代理的转发器，官方 man page EXAMPLES）**：
    ```
    socat \
    TCP4-LISTEN:2022,reuseaddr,fork \
    PROXY:proxy.local:www.domain.org:22,proxyport=3128,proxyauth=username:s3cr3t
    ```
    官方解释：在本地 2022 端口监听，经 proxy.local:3128 的 CONNECT 方法（带 Basic 认证）转发到 www.domain.org:22。
    来源：http://www.dest-unreach.org/socat/doc/socat.html ［官方文档］

46. **与 ssh_config 配合的典型写法（社区惯例）**：`ProxyCommand socat - PROXY:proxy.example.com:%h:%p,proxyport=3128`（SOCKS 场景则用 `SOCKS4A:proxy.example.com:%h:%p` 等）。⚠️ 此写法属于社区常见模式：官方 man page 说明了 PROXY/SOCKS 地址类型与 ssh(1) 的 ProxyCommand 通用机制（事实 1），但没有逐字给出"socat 直接作为 ProxyCommand"的官方示例。
    来源：http://www.dest-unreach.org/socat/doc/socat.html ［官方文档（地址类型）+ 社区（组合写法）］

47. **版本差异**：⚠️ 当前官网 man 页含 `SOCKS5-CONNECT`（无认证）；广泛部署的旧版 socat（1.7.x 系）客户端地址类型只有 SOCKS4/SOCKS4A/PROXY。SOCKS5-CONNECT 具体由哪个版本引入未在本次调研中核实（不确定）。
    来源：http://www.dest-unreach.org/socat/doc/socat.html ［官方文档 + ⚠️ 版本沿革未核实］

---

## 六、ProxyJump 与 ProxyCommand 差异、多级跳板与配置示例

48. **差异总览（权威博客总结）**："ProxyCommand is the older mechanism, and it runs an arbitrary command to open the connection to the target rather than using the built-in jump logic."；建议："Reach for ProxyJump in almost every case, because it is shorter, clearer, and handles multi-hop cleanly. Reach for ProxyCommand when you need something ProxyJump cannot express, such as routing through a tool other than SSH or wrapping the connection in a custom transport."（ProxyJump 更短更清晰、原生处理多跳；ProxyCommand 适合非 SSH 工具或自定义传输的场景——如经 HTTP/SOCKS 代理，即 corkscrew/connect/nc/socat 的用武之地）。
    来源：https://goteleport.com/blog/ssh-proxyjump-ssh-proxycommand/ ［权威博客］

49. **等价写法对照（权威博客）**：
    ```
    # ProxyJump 写法
    Host target
      HostName target.internal
      ProxyJump jump.example.com

    # 等价的 ProxyCommand 写法
    Host target
      HostName target.internal
      ProxyCommand ssh -W %h:%p jump.example.com
    ```
    来源：https://goteleport.com/blog/ssh-proxyjump-ssh-proxycommand/ ［权威博客］（-W 语义见事实 10 的官方定义）

50. **多级跳板（多级 -J）**：命令行 `ssh -J jump1.example.com,jump2.example.com target.internal`；配置文件中 `ProxyJump jump1.example.com,jump2.example.com`。"ProxyJump chains as a comma-separated list, and the client hops through each host in order from left to right... Each hop is authenticated in turn, so every jump host along the way still enforces its own access rules."（逗号分隔、从左到右逐跳认证）。
    来源：https://goteleport.com/blog/ssh-proxyjump-ssh-proxycommand/ ［权威博客］；多跳逗号分隔与"按序访问"亦见官方文档：https://man.openbsd.org/ssh_config、https://man.openbsd.org/ssh ［官方文档］

51. **命令行配置不作用于跳板主机**（官方）：ssh(1) 对 -J 的说明："Note that configuration directives supplied on the command-line generally apply to the destination host and not any specified jump hosts. Use ~/.ssh/config to specify configuration for jump hosts."
    来源：https://man.openbsd.org/ssh ［官方文档］

52. **配置示例汇总**（各片段均出自上述来源）：
    ```
    # 1) 经 HTTP 代理直连目标（OpenBSD nc，ssh_config(5) 官方示例）
    Host behind-http-proxy
      ProxyCommand /usr/bin/nc -X connect -x 192.0.2.0:8080 %h %p

    # 2) 经 SOCKS5（nc 缺省即 SOCKS5）
    Host behind-socks
      ProxyCommand /usr/bin/nc -x 10.2.3.4:1080 %h %p

    # 3) corkscrew（官方 README 示例）
    Host via-corkscrew
      ProxyCommand /usr/local/bin/corkscrew proxy.example.com 8080 %h %p

    # 4) connect（作者手册示例）
    Host remote.outside.net
      ProxyCommand connect -S socks.local.net %h %p

    # 5) 单跳（官方语义 + 博客示例）
    Host target
      HostName target.internal
      ProxyJump jump.example.com

    # 6) 多跳（官方语义 + 博客示例）
    Host target
      HostName target.internal
      ProxyJump jump1.example.com,jump2.example.com

    # 7) 条件跳板（权威博客示例）
    Match host target.internal exec "test -z \"$INSIDE_NETWORK\""
      ProxyJump jump.example.com
    ```
    来源：https://man.openbsd.org/ssh_config ［官方文档］；https://github.com/patpadgett/corkscrew ［官方文档］；https://github.com/gotoh/ssh-connect ［官方文档］；https://goteleport.com/blog/ssh-proxyjump-ssh-proxycommand/ ［权威博客］

53. **互斥细节（官方）**：同一配置流中 ProxyJump 与 ProxyCommand 相互竞争，"whichever is specified first will prevent later instances of the other from taking effect"（先出现者优先）。CanonicalizeHostname 设为 `none` 亦可禁用 ProxyJump 的使用。
    来源：https://man.openbsd.org/ssh_config ［官方文档］

---

## 七、相关已知事实：OpenSSH 对 SOCKS 的原生支持情况

54. **ssh -D 是动态端口转发（ssh 充当 SOCKS 服务端），不是 SOCKS 代理客户端**。ssh(1) 手册原文："-D [bind_address:]port: Specifies a local 'dynamic' application-level port forwarding... Currently the SOCKS4 and SOCKS5 protocols are supported, and ssh will act as a SOCKS server."（ssh 作为 SOCKS **服务器**提供动态转发）。
    来源：https://man.openbsd.org/ssh ［官方文档］

55. **ssh -R 也能当 SOCKS 服务端（远端方向）**：ssh(1) 对 -R 的说明："if no explicit destination was specified, ssh will act as a SOCKS 4/5 proxy and forward connections to the destinations requested by the remote SOCKS client."
    来源：https://man.openbsd.org/ssh ［官方文档］

56. **历史：-D 的 SOCKS4 起源**：OpenSSH 2.9 release notes（2001 年）："Dan Kaminsky contributed an experimental SOCKS4 proxy to the ssh client (yes, client not the server). Use 'ssh -D 1080 server' if you want to try this out."
    来源：https://www.openssh.com/txt/release-2.9 ［官方文档］

57. **OpenSSH 连接侧（客户端出站）没有内置 SOCKS/HTTP 代理支持**：让 ssh 本身"通过代理连出去"需依赖 ProxyCommand 委托外部程序（nc/ncat/corkscrew/connect/socat 等）。佐证：① ssh_config(5) 以"与 nc 及其代理支持配合"来描述 ProxyCommand（事实 2）；② connect.c 作者手册的历史叙述"OpenSSH development team decides to stop supporting SOCKS and any other tunneling mechanism... recommends... ProxyCommand option instead"（事实 40）。
    来源：https://man.openbsd.org/ssh_config ［官方文档］；https://github.com/gotoh/ssh-connect ［官方文档（作者叙述）］
    ⚠️ "OpenSSH 曾经内置 SOCKS 支持后在某版本移除"的**具体版本号**未能在本次调研的官方 release notes 中定位到（2.9/7.3 均无此条目），该历史细节依据 connect.c 作者手册的单方叙述，属于二手来源。

58. **PuTTY 侧对照**：PuTTY 原生内置 HTTP CONNECT/SOCKS4/SOCKS5/Telnet/SSH/Local 六类代理（含用户名密码认证），与 OpenSSH"需外部 ProxyCommand 工具"形成对照；PuTTY 的 SSH 代理类型 "SSH to proxy and use port forwarding" 被官方文档描述为 "similar to OpenSSH's -J option"。
    来源：https://the.earth.li/~sgtatham/putty/0.81/htmldoc/Chapter4.html ［官方文档（PuTTY）］

59. **组合技（官方演示）**：Ncat 指南演示了"`ssh router -D 8080` 在本地起 SOCKS 服务端，再让 `ncat --proxy localhost:8080 --proxy-type socks4 192.168.1.123` 经它连内网主机"的组合，说明 ssh -D 与代理客户端工具是互补关系。
    来源：https://nmap.org/ncat/guide/ncat-tricks.html ［官方文档］

---

## 八、不确定与存疑内容汇总（⚠️）

| # | 内容 | 状态与说明 |
|---|------|-----------|
| 1 | corkscrew "仅支持 HTTP CONNECT、不支持 SOCKS" | 官方 README 全文只描述 HTTP 代理、无 SOCKS 参数，据此推断为"功能缺失"；非逐字官方声明。 |
| 2 | corkscrew 原站 agroman.net 已失效 | README 只说主分发地是 GitHub；原站失效为社区普遍报告，未直接验证。 |
| 3 | connect.c 与 PuTTY 的直接关联（connect.exe 用作 PuTTY Local proxy） | PuTTY 官方文档定义了 Local 代理命令机制（等价 ProxyCommand），connect.c 官方手册说明其支持 Windows；但双方官方文档均未互相点名，属社区使用惯例。 |
| 4 | socat SOCKS5-CONNECT 的引入版本 | 当前官方 man page 含该地址类型且注明无认证；具体引入版本（是否 1.8.x 新增）未核实。旧版 1.7.x 仅 SOCKS4/4A/PROXY 的说法亦未逐版核实。 |
| 5 | OpenSSH "曾内置 SOCKS 后移除" 的具体版本 | connect.c 作者手册称 OpenSSH 团队决定停止支持 SOCKS 改推 ProxyCommand；未能在官方 release notes（含 2.9）中定位到移除条目，历史细节为单方二手叙述。 |
| 6 | GNU netcat 官网长期未更新（0.7.1，2004 年） | 官网自述 beta 状态；其"无代理支持"基于官网特性列表与 man page 选项表的功能缺失推断，并有 secwiki（Nmap 开发者）对 traditional netcat 的同类表述交叉佐证。 |
| 7 | 命令示例的行为随版本变化 | 本文所有 man page 引文取自 man.openbsd.org 当前版（OpenSSH 10.x 时代）与各工具当前官方文档；旧版本（如 OpenSSH 7.x 时期）措辞可能略有差异。 |

---

## 九、来源清单

**官方文档（一手）**
1. OpenBSD ssh_config(5) 手册 — https://man.openbsd.org/ssh_config
2. OpenBSD ssh(1) 手册 — https://man.openbsd.org/ssh
3. OpenBSD nc(1) 手册 — https://man.openbsd.org/nc
4. OpenSSH 7.3 Release Notes — https://www.openssh.com/txt/release-7.3
5. OpenSSH 2.9 Release Notes — https://www.openssh.com/txt/release-2.9
6. Ncat Users' Guide: Proxying — https://nmap.org/ncat/guide/ncat-proxy.html
7. Ncat Users' Guide: Neat Tricks（Use SSH Through an Ncat Tunnel） — https://nmap.org/ncat/guide/ncat-tricks.html
8. corkscrew 官方 README（patpadgett/corkscrew） — https://github.com/patpadgett/corkscrew
9. connect.c 作者仓库与手册（gotoh/ssh-connect，doc/manual.txt） — https://github.com/gotoh/ssh-connect
10. socat 官方 man page — http://www.dest-unreach.org/socat/doc/socat.html
11. PuTTY User Manual, Chapter 4（Proxy 面板 4.16.1/4.16.5） — https://the.earth.li/~sgtatham/putty/0.81/htmldoc/Chapter4.html
12. Debian connect-proxy 软件包页 — https://packages.debian.org/testing/net/connect-proxy
13. Debian connect-proxy man page — https://manpages.debian.org/jessie/connect-proxy/connect.1.en.html
14. Debian netcat-traditional man page — https://manpages.debian.org/jessie/netcat-traditional/netcat.1.en.html
15. GNU Netcat 官方首页 — http://netcat.sourceforge.net/

**权威技术资料**
16. Ncat/Compatibility（Nmap 开发者 wiki） — https://secwiki.org/w/Ncat/Compatibility

**权威博客**
17. Teleport (Gravitational)：SSH ProxyJump and ProxyCommand: How to Use Jump Hosts — https://goteleport.com/blog/ssh-proxyjump-ssh-proxycommand/

**社区（佐证性）**
18. Black Hills Information Security: Netcat (nc) Cheatsheet — https://www.blackhillsinfosec.com/netcat-cheatsheet/
