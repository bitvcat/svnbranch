#!/usr/bin/lua5.3
-- svn 切分支

-- readme
--[[
仓库文件结构：
.
├── branch
│   └── self_20210520_10
├── tools
│   ├── client
│   ├── common
│   └── server
└── trunk
    ├── client
    ├── config
    ├── docs
    └── server

branch 为分支目录
trunk 为主干目录
tools 为工具目录

切分支的大概思路：
1. 把 trunk 整个目录切到 branch 目录下，并以平台名称作为分支的名称，例如：tencent；
2. 切分支时需要指定分支所属的平台名称，切完后把 "日期_版本号" 写入到分支目录的 config/version.txt 中
3. 若 branch 目录中已经存在某个平台的分支，则需要先把这个旧分支移动备份，备份的分支命名格式为："平台_日期_版本号"，例如：tencent_20210520_1001，“日期_版本号”从分支的 config/version.txt 中读取

ps：可以把备份的分支（例如：tencent_20210520_1001）看成是一个 tag。至于为什么要先移动备份上一个分支，然后再从 trunk 切新的分支，
是为了减少分支目录的 checkout 操作，如果每次切分支都用 "平台_日期_版本号" 来命名，那每切一次都要重新拉一次新的 svn，可能对测试和策划不够友好。
]]


----------------------------------- color command -----------------------------------
-- 特殊格式（可以同时设置多个）
local specOpt = {
    bold = 1,           -- 加粗（高亮）
    underline = 4,      -- 下划线
    blink = 5,          -- 闪烁
    reverse = 7,        -- 反显（背景色和字体色翻转）
    -- unbold = 22,        -- 取消加粗
    -- nounderline = 24,   -- 取消下划线
    -- unblink = 25,       -- 取消闪烁
    -- unreverse = 27      -- 取消反显
}

-- 字体颜色
local fontColor = {
    black = 30,     -- 黑色
    red = 31,       -- 红色
    green = 32,     -- 绿色
    yellow = 33,    -- 黄色
    blue = 34,      -- 蓝色
    carmine = 35,   -- 洋红
    cyan = 36,      -- 青色
    white = 37      -- 白色
}

-- 默认黑底白字加粗
local function _cformat(str, f, b, ...)
    local fc = f and fontColor[f] or 37
    local bc = (b and fontColor[b] or 30) + 10

    local spec = ""
    for _, v in ipairs({...}) do
        local opt = specOpt[v]
        if opt then
            spec = spec .. ";" .. opt
        end
    end
    if string.len(spec) == 0 then
        spec = spec .. ";" .. specOpt["bold"]
    end

    local prefix = "\27[" .. fc .. ";" .. bc .. spec .. "m"
    return prefix .. str .. "\27[0m"
end

local crPrint = function(str) print(_cformat(str, "red")) end
local cgPrint = function(str) print(_cformat(str, "green")) end


----------------------------------- variable -----------------------------------
-- 仓库 url
local _svn_ip = "192.168.1.254"
local _url_proj = "svn://".. _svn_ip .. "/proj-slg"
local _url_trunk = _url_proj .. "/trunk"
local _url_branch = _url_proj .. "/branch"
local _svn_path = "/var/svn/repos/proj-slg"
local _repo_name = "proj-slg"


----------------------------------- trunk2branch -----------------------------------
local function _remove_tmp()
    os.execute("rm -rf __tmp &> /dev/null")
end

local function _remove_log()
    os.execute("rm -f __log &> /dev/null")
end

local function _readfile(file)
    local fd = io.open(file, "r")
    if fd then
        local content = fd:read("a")
        fd:close()
        return content
    end
end

-- shell
local function _shell(cmd, quite)
    if quite then
        return os.execute(cmd  .. "&> /dev/null")
    else
        _remove_log()
        local ok = os.execute(cmd .. "&> __log")
        local msg = _readfile("__log")
        _remove_log()
        return ok, msg
    end
end

local function _repo_info(url, echo)
    print()
    print("测试仓库：" .. _cformat(url, "green"))

    local fd = io.popen("svn info " .. url)
    if fd then
        local svninfo = fd:read("a")
        fd:close()

        if echo then
            print(svninfo)
        end
        print("测试仓库：" .. _cformat("ok", "green"))
        return svninfo
    else
        crPrint("获取仓库信息失败")
    end
end

local function _checkout_empty_path(url)
    _remove_tmp()

    local ok, err = _shell(string.format("svn co %s --depth=empty __tmp", url))
    return ok, err
end

-- 提取 config/version.txt
-- eg.: svn://192.168.1.254/proj-slg/branch/xxx/config
local function _extract_version(url)
    local ok, err = _checkout_empty_path(url)
    if ok then
        _shell("svn up __tmp/version.txt", true)
        return true
    else
        crPrint("拉取 config 目录失败，errmsg = " .. err)
    end
end

local function _get_version(url)
    local datestr, revision
    if _extract_version(url) then
        local verstr = _readfile("__tmp/version.txt")
        if verstr then
            datestr, revision = string.match(verstr, "(%d+)_(%d+)")
        else
            crPrint("读取 version.txt 失败， 请人工修复！")
        end
    end

    _remove_tmp()
    return datestr, revision
end

local function _set_version(url, version)
    local ok = _extract_version(url .. "/config")
    if ok then
        local f = io.open("__tmp/version.txt", 'w')
        f:write(tostring(version))
        f:close()
    end

    -- svn add
    local addcmd = "svn add __tmp/version.txt"
    _shell(addcmd, true)

    -- svn ci
    print("写版本号：" .. _cformat("config/version.txt, version="..version, "green"))
    local cicmd = 'svn ci __tmp/version.txt -m "set version: "' .. version
    local ok, err = _shell(cicmd)
    if not ok then
        crPrint("写入版本号失败, err：" .. err)
        print("写版本号：" .. _cformat("失败，err："..err, "red"))
    else
        print("写版本号：" .. _cformat("成功", "green"))
    end
end

local function _extract_branch(url, plat)
    local fd = io.popen("svn list " .. url)
    assert(fd)

    local branchs = {}
    for line in fd:lines() do
        local bname = string.match(line, "^("..plat .. "%S*)/")
        if bname then
            local sd, sv
            if bname == plat then
                -- last release
                local burl = url .. "/" .. plat .. "/config"
                sd, sv = _get_version(burl)
            else
                -- tags
                sd, sv = string.match(line,'%S+_(%d+)_(%d+)/')
            end

            local dt = assert(tonumber(sd), sd)
            local rv = assert(tonumber(sv), sv)

            assert(tostring(dt) == sd)
            assert(tostring(rv) == sv)
            table.insert(branchs, {bname, dt, rv})
        end
    end
    fd:close()

    -- sort
    if #branchs > 1 then
        table.sort(branchs, function (a, b)
            if a[2] == b[2] then
                return a[3] > b[3]
            else
                return a[2] > b[2]
            end
        end)
    end

    return branchs
end

local function _branch2tag(burl, last)
    -- 备份
    local tagurl = string.format("%s/%s_%s_%s", _url_branch, last[1], last[2], last[3])
    print("备份分支：" .. _cformat(tagurl, "green"))

    local movecmd = string.format('svn move %s %s -m"move %s to %s"', burl, tagurl, burl, tagurl)
    local ok, msg  = _shell(movecmd)
    if ok then
        print("备份分支：" .. _cformat("成功", "green"))
    else
        print("备份分支：" .. _cformat("失败", "red"))
        print(msg)
    end
    return ok
end

local function _trunk2branch(burl, plat, date, revision)
    -- svn copy trunk branch --revision xxx -m "xxxx" --quiet
    local version = date .. "_" .. revision
    print("切换分支：" .. _cformat(plat.."_"..version, "green"))
    local copycmd = string.format('svn copy %s %s --revision %s -m "trunk2branch：%s"', _url_trunk, burl, revision, version)
    local ok, err = _shell(copycmd)
    if ok then
        print("切换分支：" .. _cformat("成功", "green"))
        return version
    else
        print("切换分支：" .. _cformat("失败", "green"))
        print(err)
    end
end

-- 确认检查
local function _judge_start()
    crPrint("\n\n接下来的操作可能很危险,一切后果自负! 如果你不想继续请直接关闭窗口! \n\n")
    print("是否继续？[yes/no]")
    local r = io.read("l")
    if r ~= "yes" then
        crPrint("Error: 口令错误，操作结束！")
        return false
    end

    local fd = io.popen("hostname -I")
    assert(fd)
    local ipstr = string.gsub(fd:read("a"), "%s", "")
    if ipstr ~= _svn_ip then
        crPrint("Error: 必须在 svn 服务器上执行该脚本(需要更新 svn 权限文件)")
        return false
    end

    return true
end

-- 平台检查
local function _judge_plat()
    print("\n请输入平台:")
    local platform = io.read() --arg[2]
    if not platform or string.len(platform)==0 then
        crPrint('Error: 请输入平台' )
        return
    end
    if string.find(platform, " ") then
        crPrint("Error: 平台名称不能有空格")
        return
    end

    return platform
end

-- 版本号检查
local function _judge_revision()
    local crevision
    local info = _repo_info(_url_trunk)
    if info then
        local rev = string.match(info, "Last Changed Rev:%s*(%d+)")
        crevision = assert(tonumber(rev))
        print("主干版本：" .. _cformat(crevision, "green"))
    else
        crPrint("Error: 主干仓库不存在")
        return false
    end

    print("\n请输入svn版本号(若不输入则表示取主干最新的版本号):")
    local revision = io.read()
    if not revision or string.len(revision) == 0 then
        -- 读取主干 revision
        revision = crevision
    else
        revision = assert(tonumber(revision))
        if revision > crevision then
            crPrint("Error: 输入的svn版本号不能比主干当前的版本号大")
            return false
        end
    end
    return revision
end

-- 分支检查
local function _judge_branch(plat, date, revision)
    local last
    local branchs = _extract_branch(_url_branch, plat)
    if #branchs > 0 then
        for _, v in ipairs(branchs) do
            if v[1] == plat then
                last = v
            end

            if date == v[2] and revision == v[3] then
                crPrint(string.format("Error：该分支已经存在，plat=%s, date=%s, revision=%s", table.unpack(v)))
                return
            end
        end

        --print(table.unpack(last), date, revision)
        if last and not (date >= last[2] and revision > last[3]) then
            crPrint("Error: 新的分支版本不能小于最后一个分支的版本")
            return
        end
    end
    return true, last
end


----------------------------------- auth -----------------------------------
local function _load_authz()
    local file = io.open(_svn_path.."/conf/authz", "r")
    assert(file)

    local trunkFolder --子文件夹
    local headers = {} --分支之前的行
    local trunkAuth = {}
    for ln in file:lines() do
        if string.len(ln) > 0 and not string.match(ln, "^%s*#") then
            -- 忽略空行、注释行
            local node = string.match(ln, "^%[(.+)%]$") -- 匹配 [proj-name:/xxx/yyy]
            if node then
                local repoNm,folder1,folder2 = string.match(node, "(%S+):/(%S-)/(.*)")
                if repoNm then
                    assert(repoNm == _repo_name, ln)
                    if folder1=="trunk" then
                        assert(not string.find(folder2, "/"))
                        trunkFolder = folder2
                        trunkAuth[trunkFolder] = trunkAuth[trunkFolder] or {}
                    else
                        trunkFolder = nil
                        if next(trunkAuth) then break end -- 只读到主干即可
                    end
                end
            else
                if trunkFolder then
                    table.insert(trunkAuth[trunkFolder], ln)
                end
            end
            table.insert(headers, ln)
        else
            if not next(trunkAuth) then
                table.insert(headers, ln)
            end
        end
    end
    file:close()
    return headers, trunkAuth
end


----------------------------------- do_xxx -----------------------------------
function do_trunk2branch()
    if not _judge_start() then return end

    local plat = _judge_plat()
    if not plat then return end

    local revision = _judge_revision()
    if not revision then return end

    local date = tonumber(os.date("%Y%m%d"))
    print("\n当前日期：" .. _cformat(date, "green"))

    local ok, lb = _judge_branch(plat, date, revision)
    if ok then
        local burl = _url_branch .. "/" .. plat
        if not lb or _branch2tag(burl, lb) then
            local version = _trunk2branch(burl, plat, date, revision)
            if version then
                _set_version(burl, version)

                -- auth
                do_update_auth(plat, version)
            end
        end
    end
end

function do_clean()
    _remove_log()
    _remove_tmp()
end

function do_update_auth(plat, version)
    local contents, trunkAuth = _load_authz()

    local fd = io.popen("svn list " .. _url_branch)
    assert(fd)

    local bnames = {}
    for line in fd:lines() do
        local bname = string.match(line, "(%S+)/")
        if bname then
            table.insert(bnames, bname)
        end
    end
    fd:close()
    table.sort(bnames)

    local authz = _svn_path.."/conf/authz"
    local cpcmd = string.format([[\cp -f %s %s.%s_%s]], authz, authz, plat, version)
    assert(os.execute(cpcmd), cpcmd)
    print("\n备份权限：" .. _cformat("成功", "green"))

    for _, bnm in ipairs(bnames) do
        table.insert(contents, string.format("\n#----------- %s ----------", bnm))

        for k, t in pairs(trunkAuth) do
            table.insert(contents, string.format("[%s:/branch/%s/%s]", _repo_name, bnm, k))
            for _, v in ipairs(t) do
                table.insert(contents, v)
            end
            table.insert(contents, "")
        end
    end

    fd = io.open(authz, "w+")
    assert(fd)
    fd:write(table.concat(contents, "\n"))
    fd:flush()
    fd:close()
    print("更新权限：" .. _cformat("成功", "green"))
end

do_clean()
do_trunk2branch()
do_clean()
