# ------------------------------------------------------------
# 段3 业务 · discover_os —— 探测远端资产类型（OS 家族/内核/发行版/改密能力）
# 前置: 已到达远端 POSIX shell 提示符（认证/提权段完成）
# 输出: stdout 单行结构化结果
#       DISCOVER os=<os> kernel=<ver> id=<distro> chpasswd=<yes|no>
# 说明: 全部探测只读；id 依赖 /etc/os-release，AIX/Solaris 等无该文件则为 "-"
# 退出码: 6 业务失败
# ------------------------------------------------------------

log_info "biz: discovering remote asset type"
# 注意: Tcl 正则默认非 multiline, `^` 只锚定缓冲区开头; 用 `\r?\n` 前缀锚定规避
# 命令回显误判（调研 3.3）。行尾用后瞻 (?=\r?\n) 而非直接消费换行符,
# 否则上一模式吃掉换行后, 下一行失去前导锚点（exp_continue 连续匹配场景）。
send "echo DISC_BEGIN; uname -s; uname -r; awk -F= '/^ID=/{print \"ID=\" \$2; exit}' /etc/os-release 2>/dev/null; command -v chpasswd >/dev/null 2>&1 && echo HAS_CHPASSWD=1 || echo HAS_CHPASSWD=0; echo DISC_END\r"

set _os "-"
set _kernel "-"
set _id "-"
set _chpwd "-"
expect {
    -re {\r?\n(Linux|AIX|SunOS|FreeBSD|OpenBSD|NetBSD|Darwin|HP-UX)(?=\r?\n)} {
        set _os $expect_out(1,string)
        exp_continue
    }
    -re {\r?\n([0-9][^\r\n]*)(?=\r?\n)} {
        set _kernel $expect_out(1,string)
        exp_continue
    }
    -re {\r?\nID=([^\r\n]*)(?=\r?\n)} {
        if {[string length $expect_out(1,string)] > 0} { set _id $expect_out(1,string) }
        exp_continue
    }
    -re {\r?\nHAS_CHPASSWD=([01])(?=\r?\n)} {
        set _chpwd [expr {$expect_out(1,string) eq "1" ? "yes" : "no"}]
        exp_continue
    }
    -re {\r?\nDISC_END(?=\r?\n)} { }
    timeout { puts stderr "BIZ_TIMEOUT"; exit 6 }
    eof     { puts stderr "BIZ_EOF";     exit 6 }
}

puts "DISCOVER os=$_os kernel=$_kernel id=$_id chpasswd=$_chpwd"
log_info "biz: discover done: os=$_os kernel=$_kernel id=$_id chpasswd=$_chpwd"
