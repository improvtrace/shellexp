# ------------------------------------------------------------
# script/lib/util.tcl — 公共工具函数（拼装时内联进 bin/ 产物）
# ------------------------------------------------------------

# 带时间戳的日志，输出到 stderr（不污染 stdout，便于管道采集）
proc log_info {msg} {
    puts stderr "\[[clock format [clock seconds] -format %H:%M:%S]\] $msg"
}

# 报错退出：code 为分段语义退出码
proc die {code msg} {
    puts stderr "ERROR: $msg"
    exit $code
}

# POSIX 单引号转义：把值安全嵌入远端 shell 的单引号字符串
# 例：ab'cd -> ab'\''cd（拼回单引号串后还原为 ab'cd）
# 注意：映射表必须用 [list] 构造，大括号字面量会被 lindex 吃掉反斜杠
proc quote_single {s} {
    return [string map [list "'" "'\\''"] $s]
}
