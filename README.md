# SHELL EXPECT

基于 [Expect](https://core.tcl-lang.org/expect/) 的远程主机管理脚本生成框架。

把一次远程运维拆为 **认证（auth）→ 提权（escalate）→ 业务（biz）** 三段模板，由 `main.sh` 按需拼装为 `bin/` 下可直接执行的 expect 脚本。无驱动配置，模板即代码。

> 设计依据：[.docs/research/expect-remote-device-mgmt.md](.docs/research/expect-remote-device-mgmt.md) 第 11 章「模板拼装框架」

## 设计原则

- **段式拼装**：`公共头 → auth → locale → escalate → biz → epilogue`，纯文本拼接
- **无驱动配置**：平台差异收敛为模板文件，`REQUIRE_ENV` / `REQUIRE_ARGV` 头部自描述契约
- **参数不落盘**：非敏感参数走 argv，密码只走环境变量（`$env()` 注入，不进 argv / 不写死在产物里）
- **单 spawn 铁律**：仅认证段 `spawn`，提权与业务复用同一会话
- **输出规约**：注释用中文；日志 / 报错 / usage 等运行时输出统一英文，便于采集与聚合
- **失败分段编码**：退出码 2=认证 6=业务 7=提权，供上层批量调度统计与重试

## 目录结构

```text
shellexp/
├── main.sh                              # 生成器：--auth/--escalate/--biz [--out]
├── bin/
│   ├── draft/                           # 生成产物（草稿区，可随时重建，勿手工编辑）
│   ├── release/                         # 人工归档：已适配调试完成的 draft 脚本
│   └── manual/                          # 人工归档：用户自定义脚本（生成器不写入）
├── script/
│   ├── lib/
│   │   └── util.tcl                     # 公共工具函数：日志、die、POSIX 单引号转义
│   └── biz/
│       ├── auth/                        # 认证段（唯一 spawn 点）
│       │   ├── auth_ssh.tpl             #   SSH 密码登录
│       │   └── auth_telnet.tpl          #   Telnet 密码登录（仅限管理网）
│       ├── escalate/                    # 提权段
│       │   ├── escalate_none.tpl        #   空段：登录身份已满足权限
│       │   ├── escalate_su.tpl          #   su -（输目标身份密码）
│       │   └── escalate_sudo.tpl        #   sudo -S -i（输当前用户密码）
│       ├── password/                    # 改密业务段
│       │   ├── password_chpasswd.tpl    #   非交互 chpasswd（首选，退出码标记判定）
│       │   └── password_passwd.tpl      #   交互式 passwd（中英双语兜底）
│       └── discover/                    # 资产探测业务段
│           └── discover_os.tpl          #   探测 OS 家族/内核/发行版/改密能力
├── requirements.txt                     # expect/tcl 依赖与安装说明
└── .examples/                           # 历史参考样例
```

bin/ 三个子目录的工作流：`main.sh` 生成的脚本落在 `bin/draft/`，针对目标适配调试通过后，**由用户手动**移入 `bin/release/` 归档；`bin/manual/` 存放不依赖生成器的自定义脚本，生成器会拒绝写入这两个目录。

## 快速开始

```bash
# 1. 安装依赖（详见 requirements.txt）
sudo apt-get install -y expect tcl

# 2. 查看可用模板
./main.sh --list

# 3. 生成脚本：spider 登录 → sudo 提权 → 非交互改密（缺省输出 bin/draft/）
./main.sh --auth ssh --escalate sudo --biz chpasswd
#   等价于: ./main.sh --auth ssh --escalate sudo --biz chpasswd \
#               --out bin/draft/ssh_sudo_chpasswd.exp

# 4. 运行
AUTH_PASS='登录密码' ESCALATE_PASS='sudo密码' NEW_PASS='新密码' \
    ./bin/draft/ssh_sudo_chpasswd.exp 10.0.0.1 22 spider targetuser

# 5. 资产类型探测（登录后只读采集，结果输出到 stdout）
AUTH_PASS='登录密码' ./bin/draft/ssh_none_discover_os.exp 10.0.0.1 22 spider
# DISCOVER os=Linux kernel=5.15.0-73-generic id=ubuntu chpasswd=yes

# 6. 适配调试通过后，手动归档到 release/
mv bin/draft/ssh_sudo_chpasswd.exp bin/release/
```

## 环境变量契约

| 变量 | 必填 | 消费段 | 说明 |
| --- | --- | --- | --- |
| `AUTH_PASS` | 是 | auth | 登录密码 |
| `ESCALATE_PASS` | su/sudo 时 | escalate | su 输**目标身份**密码；sudo 输**当前用户**密码（语义相反） |
| `NEW_PASS` | password 类业务 | biz | 新密码 |
| `OLD_PASS` | 可选 | biz=passwd | 当前密码（目标用户非提权自改时需要） |
| `TIMEOUT` | 可选 | 公共头 | expect 超时秒数，默认 30 |

## 退出码

| 码 | 含义 |
| --- | --- |
| 0 | 成功 |
| 1 | 用法错误 / 缺少必需环境变量 |
| 2 | 认证失败（密码错误 / 连接不可达 / 超时） |
| 6 | 业务失败（改密被拒、探测超时等） |
| 7 | 提权失败 |
| 64 | 生成器参数错误 |

## 用 autoexpect 开发新业务模板

面对不熟悉的设备/系统，不要凭空写模板——用 `autoexpect` 录制一次真实交互会话作为底稿：

```bash
# 1. 录制现场会话（-p 只保留提示符匹配，产物更精简）
autoexpect -p -f /tmp/session.exp ssh admin@10.0.0.1
#   人工完成一次完整业务操作（如改密全流程），exit 结束录制

# 2. 以 /tmp/session.exp 为底稿收敛为段模板
#    - 删除回显噪音、send/expect 冗余对，只保留关键交互序列
#    - 剔除硬编码密码，改为 $env(...) 引用
#    - 匹配模式锚定行首/行尾，显式覆盖 timeout / eof 分支
#    - 头部补 REQUIRE_ENV / REQUIRE_ARGV 契约注释

# 3. 放入 script/biz/<类目>/<名称>.tpl，用 main.sh 生成，单台灰度验证后再批量
```

> autoexpect 产物可读性差、难以维护，官方定位是"模板起点"而非成品（调研 2.4 / 8.1）。

## 安全基线

- 凭据只经环境变量注入；敏感内容发送期间 `log_user 0`
- chpasswd 管道内嵌密码经 POSIX 单引号转义（`string map`）
- 认证 / 提权密码单次失败即退出，防止连续错密触发账号锁定
- 登录后、提权前统一 `export LANG=C LC_ALL=C`；匹配用 `[Pp]` 字符类双语正则
- 建议凭据清单 600 权限；重要改密用新凭据二次登录复核

## 扩展指南

- **新增认证方式**：`script/biz/auth/auth_<name>.tpl`（如 `auth_sshkey`）
- **新增提权方式**：`script/biz/escalate/escalate_<name>.tpl`
- **新增业务**：`script/biz/<类目>/<名称>.tpl`（`--biz` 按文件名在业务子目录中唯一匹配）
- 模板头部用 `# REQUIRE_ENV:` / `# REQUIRE_ARGV: <名> <英文描述>` 声明契约，`main.sh` 自动收集校验
- **自定义脚本**：与生成器无关的脚本放 `bin/manual/`，生成器不会覆盖该目录

## License

[MIT](LICENSE) © 2026 ShellExp
