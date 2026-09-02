# SHELL EXPECT

基于 [Expect](https://core.tcl-lang.org/expect/) 的远程主机管理脚本生成框架。

把一次远程运维拆解为 **认证（auth）→ 提权（escalate）→ 业务（biz）** 三段模板，由 `main.sh` 按需拼装为 `bin/` 下的独立可执行 expect 脚本。无驱动配置、无运行时配置文件，模板即代码。

设计依据见调研报告：[.docs/research/expect-remote-device-mgmt.md](.docs/research/expect-remote-device-mgmt.md)（第 11 章「模板拼装框架」）。

## 设计原则

| 原则 | 落地方式 |
| --- | --- |
| 一次业务 = 多段拼接 | 段序列 `公共头 → auth → escalate → biz → epilogue`，`main.sh` 纯文本拼接，不解析不改写 |
| 无驱动配置 | 平台差异收敛为模板文件（`script/biz/**`），不引入 JSON/YAML 驱动注册表 |
| 生成式交付 | 模板进版本库，`bin/` 为构建产物，可随时重建、不手工编辑 |
| 参数不落盘 | 非敏感参数走 argv，密码一律走环境变量；生成产物中只有 `$env()` 引用，无凭据本体 |
| 单 spawn 铁律 | 只有认证段 `spawn ssh`，提权与业务复用同一会话（有状态业务的前提） |
| 失败分段编码 | 退出码按段语义划分（2/6/7），便于上层批量调度统计与重试 |

## 目录结构

```text
shellexp/
├── main.sh                          # 生成器：--auth/--escalate/--biz/--out 按需拼装
├── bin/                             # 构建产物：可直接执行的 expect 脚本
├── script/
│   ├── lib/
│   │   └── util.tcl                 # 公共工具函数：日志、die、POSIX 单引号转义
│   └── biz/
│       ├── auth/
│       │   └── generic.tpl          # 认证段：SSH 密码登录（唯一 spawn 点，多分支状态机）
│       ├── escalate/
│       │   ├── none.tpl             # 提权段：空段（登录身份已满足权限）
│       │   ├── su.tpl               # 提权段：su - 切换目标身份（输目标身份密码）
│       │   └── sudo.tpl             # 提权段：sudo -S -i 提权为 root（输当前用户密码）
│       └── password/
│           ├── chpasswd.tpl         # 业务段：非交互改密（首选，退出码标记判定）
│           └── passwd.tpl           # 业务段：交互式 passwd 兜底（中英双语提示）
├── requirements.txt                 # expect/tcl 依赖与安装说明
└── .examples/                       # 历史参考样例
```

## 快速开始

### 1. 安装依赖

见 [requirements.txt](requirements.txt)，如 Debian/Ubuntu：

```bash
sudo apt-get install -y expect tcl
```

### 2. 查看可用模板

```bash
./main.sh --list
```

### 3. 生成脚本

```bash
# 生成"spider 登录 → sudo 提权 → 非交互改密"脚本
./main.sh --auth generic --escalate sudo --biz chpasswd \
    --out bin/generic_sudo_chpasswd.exp
```

### 4. 运行

```bash
AUTH_PASS='登录密码' ESCALATE_PASS='sudo密码' NEW_PASS='新密码' \
    ./bin/generic_sudo_chpasswd.exp 10.0.0.1 22 spider targetuser
```

## 环境变量契约

| 变量 | 必填 | 消费段 | 说明 |
| --- | --- | --- | --- |
| `AUTH_PASS` | 是 | auth | SSH 登录密码 |
| `ESCALATE_PASS` | su/sudo 提权时必填 | escalate | 提权密码。注意语义相反：su 输**目标身份**的密码，sudo 输**当前登录用户**的密码 |
| `NEW_PASS` | password 类业务必填 | biz | 新密码 |
| `OLD_PASS` | 可选 | biz=passwd | 目标用户当前密码（非 root 上下文自改密码时需要） |
| `TIMEOUT` | 可选 | 公共头 | expect 超时秒数，默认 30 |

必需变量由模板头部 `# REQUIRE_ENV:` 自描述，`main.sh` 拼装时收集并在运行时前置校验；位置参数同理由 `# REQUIRE_ARGV: <名> <描述>` 声明。

## 退出码

| 码 | 含义 |
| --- | --- |
| 0 | 成功 |
| 1 | 用法错误 / 缺少必需环境变量 |
| 2 | 认证失败（密码错误 / 连接不可达 / 超时 / 会话中断） |
| 6 | 业务失败（如 chpasswd 非零退出、密码策略拒绝） |
| 7 | 提权失败（su/sudo 密码错误、不在 sudoers） |
| 64 | 生成器参数错误（main.sh） |

## 安全基线

- 凭据只经环境变量注入，禁止写入 argv（防 `ps`/`/proc` 泄露）
- 敏感内容发送期间 `log_user 0`；chpasswd 管道内嵌密码经 POSIX 单引号转义（`string map`）
- 认证/提权密码单次失败即退出，防止连续错密触发账号锁定
- 会话前置 `export LANG=C LC_ALL=C`，匹配模式用 `[Pp]` 字符类双语正则，规避中文 locale 与 gate keeper 优化坑
- 生成的脚本与日志不含明文密码；建议凭据清单文件权限 600
- 改密成功判定为远端 rc=0；重要场景建议用新凭据二次登录复核

## 扩展指南

- **新增认证/提权平台变体**：在 `script/biz/auth/`、`script/biz/escalate/` 下新增 `<名称>.tpl`，头部用 `REQUIRE_ENV` / `REQUIRE_ARGV` 自描述契约
- **新增业务段**：在 `script/biz/` 下新建业务子目录（如 `script/biz/exec/`），`--biz` 会在这些子目录中按文件名唯一匹配
- 重新运行 `main.sh` 生成对应组合即可，认证/提权层零改动
- 历史交互样例参考：[.examples/scripts/ssh_exec_ps.exp](.examples/scripts/ssh_exec_ps.exp)

## License

[MIT](LICENSE) © 2026 ShellExp
