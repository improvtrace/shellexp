# proxychains‑ng 是否适合 ssh / telnet 客户端
> 结论：**可以用，但属于“能用，但不推荐作为首选方案”，有明确适用边界与坑；优先选原生ssh能力，迫不得已再上proxychains**。

## ✅可以正常工作的条件
1. ssh、telnet 是系统动态链接版本（glibc，不是静态编译）
2. 使用 TCP（ssh/telnet本身都是TCP，这点没问题）
3. 不开复杂高级特性，用 `-q` 关闭proxychains的stderr日志干扰终端

```bash
proxychains4 -q ssh user@target
proxychains4 -q telnet 192.168.1.100 23
```

## ⚠️针对 ssh / telnet 的特有问题
### 1. SSH 场景特有坑
1. **OpenSSH会做多个connect调用**：连接、gssapi、dns、已知主机检查，全部会被劫持；绝大多数情况没问题，但极端多线程/信号场景有小概率部分请求逃逸。
2. **SSH ControlMaster 连接复用**：如果已经有后台ssh主进程，proxychains包装的ssh子进程会复用已存在的master socket，**不走proxychains劫持，流量直连泄露**。
> 解决：用proxychains执行ssh时，关闭ControlMaster，或者每次全新会话。
3. 交互终端、信号、SIGINT：大部分正常；少数场景stderr打印proxychains调试信息，干扰终端输出，必须加 `-q`。

> 📌SSH有**原生代理能力**，优先不要用proxychains：
> - `ssh -o ProxyCommand="nc -x 127.0.0.1:1080 %h %p"` 或者使用 `socat` 做ProxyCommand，原生支持socks代理，不需要LD_PRELOAD劫持。
> OpenSSH本身就内置代理逻辑，比外部劫持更可靠。

### 2. Telnet 场景特有坑
1. telnet是交互式终端程序，IAC telnet协商报文双向流转；proxychains只是单纯字节转发，**协议层面不处理telnet协商**，这个本身没问题。
2. 风险来自底层劫持缺陷：
    - 如果telnet二进制是静态编译，直接完全失效；
    - 如果telnet内部通过dlopen加载某些网络库，存在部分流量逃逸。

## 🆚几种访问telnet/ssh走socks代理的方案对比
|方案|原理|适合ssh/telnet|缺点|
|---|---|---|---|
|proxychains4 -q ssh/telnet|LD_PRELOAD劫持libc connect|✅能用，非首选|静态二进制失效、存在逃逸风险、ControlMaster坑|
|ssh ProxyCommand(socat/nc)|ssh原生代理配置|✅ssh最优|仅ssh，不支持telnet|
|ssh‑L 本地端口转发|ssh端口映射|✅telnet/ssh|每个目标要新建隧道|
|自研mytelnet（内部socks5握手）|应用层内置socks客户端|✅telnet最优|需要自己维护小工具|
|teleport tproxy|内核iptables劫持|✅全部程序|需要root，修改iptables规则|

## 什么时候可以用 proxychains 处理 ssh/telnet
1. 临时快速调试，工具是系统动态链接版本；
2. 不想写 ProxyCommand、不想开多条 `-L` 端口转发；
3. 一次性手工操作，不是自动化脚本、不是生产稳定链路。

## ❌不建议使用 proxychains 的场景
1. **自动化脚本、生产环境、稳定业务链路**：劫持机制存在逃逸可能性，出问题很难排查；优先原生方案。
2. 二进制是静态编译版本（自己编译的ssh/telnet、busybox telnet）：直接失效。
3. 开启了ssh ControlMaster连接复用。
4. 需要高可靠、可排查链路。

## 最佳实践建议
### SSH走socks代理（优先原生，不要proxychains）
`~/.ssh/config` 配置，OpenSSH原生支持socks5代理，无劫持，非常稳定：
```ssh-config
Host target-host
  ProxyCommand socat - SOCKS5:127.0.0.1:%h:%p,socksport=1080
```
直接：`ssh target-host`，不需要proxychains。

### Telnet走socks代理
- 临时少量目标：`ssh -L localport:telnet‑ip:23 jump`，本机telnet 127.0.0.1 localport。
- 大量不定目标：**自研内置socks5的telnet客户端（我们前面写的mytelnet）优于proxychains**，从根源上避免LD_PRELOAD劫持的各类缺陷。

## 总结一句话
> proxychains 对 ssh/telnet **是应急临时工具，不是生产级可靠方案**。
> SSH优先使用OpenSSH的ProxyCommand；Telnet优先端口转发或者自研socks客户端；proxychains当作“临时偷懒手段”。

> 本质：proxychains是“黑盒外部劫持”，而原生ProxyCommand / 程序内置socks握手，是“白盒主动代理”，可靠性高出一个量级。