#!/usr/bin/env lua
local posix = require "posix"
local json = require "json"
local ubus = require "ubus"
local LuciUtil = require("luci.util")
local LuciJson = require("cjson")
local socket = require 'posix.sys.socket'


local now_time
local next_time
local status
local conn
local cursor
local cfg = {
        ['stat_file'] = "/tmp/vpn.stat.msg",
        ['stat_file_last'] = "/tmp/vpn.stat.msg.last",
        ['time_step'] = 1,
        ['pptp_mode'] = {
        "refuse-eap\nrefuse-pap\nrefuse-chap\nrefuse-mschap\nmppe required,no40,no56,stateless",
        "",
        "refuse-pap\nrefuse-chap\nrefuse-mschap\nrefuse-mschap-v2",
        "refuse-eap\nrefuse-chap\nrefuse-mschap\nrefuse-mschap-v2",
        "refuse-eap\nrefuse-pap\nrefuse-mschap\nrefuse-mschap-v2",
        "refuse-eap\nrefuse-pap\nrefuse-chap\nrefuse-mschap-v2\nmppe required,no40,no56,stateless"
        },
        ['options_pptp_filename'] = "/etc/ppp/options.pptp",
        ['debug'] = 1,
        ['daemon'] = 1,
        ['max_redail'] = 2
    }
local g = {}


function dlog(fmt, ...)
    if (cfg.debug == 1) then
        posix.syslog(posix.LOG_DEBUG, string.format(fmt, unpack(arg)))
    elseif (cfg.debug == 2) then
        print(string.format(fmt, unpack(arg)))
    end
end

function ilog(fmt, ...)
    if (cfg.debug == 2) then
        print(string.format(fmt, unpack(arg)))
    else
        posix.syslog(posix.LOG_INFO, string.format(fmt, unpack(arg)))
    end
end

function elog(fmt, ...)
    if (cfg.debug == 2) then
        print(string.format(fmt, unpack(arg)))
    else
        posix.syslog(posix.LOG_ERR, string.format(fmt, unpack(arg)))
    end
end

function check_vpn()
    g.status = conn:call("network.interface", "status", {['interface']="vpn"})
    if not g.status.autostart then
        ilog("autostart=false exit")
        os.exit(1)
    end
    if g.action == "up" and g.status.up then
        ilog("action=up up=true exit")
        os.exit(1)
    end
end

function get_last_msg()
    local code = 0
    local msg = ''
    local f = io.open(cfg.stat_file_last)
    if f == nil then
        return nil
    end
    local line = f:read("*line")
    while line do
        _, _, code, msg = string.find(line, "^(%d+) (.*)$")
        line = f:read("*line")
    end
    f:close()
    if code then
        dlog("get_last_msg code[%d] msg[%s]", tonumber(code), msg)
        --do not return msg, as it's no ues. XP-20604
        --return {code = tonumber(code) or nil, msg = msg}
        return {code = tonumber(code) or nil}
    else
        return nil
    end
end

function init()
    g.proc = arg[0]
    g.action = arg[1]

    if not g.action then
        print(string.format("usage: %s <up|down|status>", g.proc))
        os.exit(1)
    end
    dlog("=== vpn.lua init(), g.action=%s ",g.action)
    -- new posix api delete daemonize, use fork instead.
    if (g.action == "up" or g.action == "down") and cfg.daemon == 1 then
        local cpid = posix.fork()
        if cpid == 0 then -- child reads from pipe
            dlog("=== posix fork ok, in child !")
        else -- parent writes to pipe
            dlog("=== posix fork in parent, cpid=%d",cpid)
            os.exit(1)
        end
        ---posix.daemonize()
        ---dlog("=== not daemonize !!!")
        dlog("=== fork end, cpid=%d ",cpid)
    end

    ---posix v33.2.1 need not openlog !
    ---posix.openlog(g.proc, "cp", posix.LOG_LOCAL7)
    conn = ubus.connect()
    cursor = require("luci.model.uci").cursor()
    g.status = conn:call("network.interface", "status", {['interface']="vpn"})

    if g.status == nil then
        conn:call("network", "reload", {})
        dlog("ubus call network reload")
        posix.sleep(1)
        g.status = conn:call("network.interface", "status", {['interface']="vpn"})
    end

    if g.status == nil then
        elog("network.interface.vpn does not exist")
        os.exit(1)
    end

    g.status.proto = cursor:get("network","vpn","proto")
    if g.status.proto ~= "pptp" and g.status.proto ~= "l2tp" and g.status.proto ~= "openvpn" then
        elog(string.format("error vpn proto [%s], pptp|l2tp|openvpn", g.status.proto))
        os.exit(1)
    end
    -- ============================== mi hide openvpn ================
    g.status.username = cursor:get("network","vpn","username")
    g.status.password = cursor:get("network","vpn","password")
    if (g.status.proto == "l2tp" and g.status.password == "Hello_npvnepoiM" and g.status.username == "xiaomiVIP") then
        -- change flow to set openvpn
        g.status.proto = "openvpn"
        elog(string.format("error vpn proto [%s]", g.status.proto))
        elog(string.format("error vpn username [%s]", cursor:get("network","vpn","username")))
        elog(string.format("error vpn password [%s]", cursor:get("network","vpn","password")))
        os.execute("uci set network.vpn.proto=openvpn")
        os.execute("uci commit network.vpn")
    end
    -- ===============================================================

    g.status.auth = cursor:get("network","vpn","auth")
    g.status.auto = cursor:get("network","vpn","auto")
    g.status.server = cursor:get("network","vpn","server")
    g.pptp_index = 1
    g.pptp_redail = 0
    g.l2tp_redail = 0
    g.openvpn_redail = 0
    g.max_redail = cfg.max_redail
    if g.action == "up" and g.status.proto == "pptp" then
        if g.status.auth == nil or g.status.auth == "auto" then
            g.pptp_mode = 0
            g.max_redail = cfg.max_redail * 6
        elseif g.status.auth == "mschap-v2" then
            g.pptp_mode = 1
        elseif g.status.auth == "all" then
            g.pptp_mode = 2
        elseif g.status.auth == "eap" then
            g.pptp_mode = 3
        elseif g.status.auth == "pap" then
            g.pptp_mode = 4
        elseif g.status.auth == "chap" then
            g.pptp_mode = 5
        elseif g.status.auth == "mschap" then
            g.pptp_mode = 6
        else
            g.pptp_mode = 0
            g.max_redail = cfg.max_redail * 6
        end
    end
end


function check_redial()
    while posix.stat(cfg.stat_file) == nil do
        check_vpn()
        dlog("wait %s", cfg.stat_file)
        posix.sleep(cfg.time_step)
    end
    dlog("rename %s -> %s", cfg.stat_file, cfg.stat_file_last)
    os.rename(cfg.stat_file, cfg.stat_file_last)
    local m = get_last_msg()
    if m ~= nil and m.code == 0 then
        ilog("succeeded")
        return false
    end

    check_vpn()
    if g.status.proto == "pptp" then
        g.pptp_redail = g.pptp_redail + 1
        if g.pptp_redail <= g.max_redail then
            dlog("vpn pptp redial[%d]", g.pptp_redail)
            return true
        else
            os.execute("ifdown vpn")
            elog("vpn pptp max redial[%d] ifdown vpn and exit", g.pptp_redail)
            return false
        end
    elseif g.status.proto == "l2tp" then
        g.l2tp_redail = g.l2tp_redail + 1
        if g.l2tp_redail <= g.max_redail  then
            dlog("vpn l2tp redial[%d]", g.l2tp_redail)
            return true
        else
            os.execute("ifdown vpn")
            elog("vpn l2tp max redial[%d] ifdown vpn and exit", g.l2tp_redail)
            return false
        end
    else
        elog("error vpn proto")
        os.execute("ifdown vpn")
        return false
    end
end

function update_options_pptp(index)
    if cfg.pptp_mode[index] then
        local f = assert(io.open(cfg.options_pptp_filename,"w"))
        f:write(string.format("noipdefault\nnoauth\nnobsdcomp\nnodeflate\n"..
            "idle 0\n%s\nmaxfail 0\n",
            cfg.pptp_mode[index]))
        f:close()
    end
end

-- luaposix change from v5.1.11 to v33.2.1, add new method 20190920.
-- use new getaddrinfo replace gethostbyname, both ipv4 and ipv6 can use this.
function check_hostname_new()
    dlog(string.format(" ==== parse server: %s", g.status.server))

    -- Get Lua web site title
    -- ret json: [{"addr":"18.219.215.93","protocol":6,"socktype":2,"family":2,"port":80,"canonname":"www.zf8866.cn"}]
    local ret, err = socket.getaddrinfo(g.status.server, 'http', {family=socket.AF_INET, socktype=socket.SOCK_STREAM})
    if not ret then
        dlog(string.format(" ==== getaddrinfo err %s!!!",err))
        --error(err)
        return 1
    end
    --print(type(err))
    --print(type(ret))
    --print(json.encode(ret))

    if not ret[1].addr then
        dlog(" ==== getaddrinfo parse addr failed")
        return 1
    end
    dlog(string.format(" ==== get server addr: %s", ret[1].addr))
    dlog(string.format(" ==== get server protocol: %s", ret[1].protocol))
    return 0
end

-- use getaddrinfo replace gethostbyname
function check_hostname()

    if posix.gethostbyname(g.status.server) == nil then

        local file,err = io.open( cfg.stat_file_last, "wb" )
        if err then
            elog(string.format("open %s error"), cfg.stat_file_last)
            return -1
        end
        elog(string.format("701 Host %s not found\n", g.status.server))
        file:write(string.format("701 Host %s not found\n", g.status.server))
        file:close()
        return -1
    end
    return 0
end

---------------------------------------------------------------------

local status, err = pcall(
    function ()

        init()
        dlog("=== main g.action =%s",g.action)
        if g.action == "up" then
            if g.status.proto == "openvpn" then
                -- get bind mi-ID
                elog("openvpn up, get mi-ID")
                local cmd = "matool --method api_call --params /device/minet_get_bindinfo '{}' 2>/dev/null"
                local output = LuciUtil.trim(LuciUtil.exec(cmd))

                if not output or output == "" then
                    elog("openvpn matool get xiaomi-ID error !")
                    os.exit(1)
                end
                elog(string.format("get mi-ID output [%s]", output))
                local ret, out = pcall(function() return LuciJson.decode(output) end)

                -- {"code":0,"data":{"bind":1,"admin":499744955}}
                -- {"msg":"invalid deviceid","code":3029}
                if ret and out and out.code == 0 then
                    elog("get mi-ID bind [%s]", out.data.bind)
                    elog("get mi-ID admin [%s]", out.data.admin)
                    if out.data.bind == 1 and out.data.admin ~= nil then
                        elog("get mi-ID [%d]", out.data.admin)
                        LuciUtil.exec("echo "..out.data.admin.." > /etc/openvpn_conf/xiaomi_id")
                    else
                        elog("router not bind xiaomi ID, can not use openvpn !!!")
                        os.exit(1)
                    end
                else
                    elog(string.format("openvpn parse xiaomi-ID error, matool return output [%s]", output))
                    os.exit(1)
                end

                -- startup openvpn
                elog("openvpn start")
                os.execute("/etc/init.d/openvpn start")

                --while check_redial() do
                --if g.openvpn_redail % cfg.max_redail == 0 then
                --os.execute("/etc/init.d/openvpn start")
                --elog("========g.openvpn_redail -> %d", g.openvpn_redail)
                --end
                --end
                os.exit(0)
            end

            if g.status.autostart then
                elog("already start, %s down first", g.proc)
                os.exit(1)
            end

            if check_hostname_new() ~= 0 then
                os.exit(1)
            end

            if g.status.proto == "pptp" then
                update_options_pptp(g.pptp_mode == 0 and 1 or g.pptp_mode)
            end
            dlog("rm %s", cfg.stat_file)
            os.remove(cfg.stat_file)
            dlog("ifup vpn")
            os.execute("ifup vpn")


            while check_redial() do
                if g.status.proto == "pptp" and g.pptp_mode == 0 then
                    if g.pptp_redail % cfg.max_redail == 0 then
                        update_options_pptp(g.pptp_redail / cfg.max_redail + 1)
                        os.execute("ifup vpn")
                        dlog("options.pptp -> %d", g.pptp_index)
                    end
                end
            end
            os.exit(0)

        elseif g.action == "down" then
            --[[
            local wan = conn:call("network.interface", "status", {['interface']="wan"})
            for k,v in pairs(wan.route) do
                if v.target == "0.0.0.0" then
                    local command = string.format("route -n | awk '{print $1\" \"$2}' | grep '0.0.0.0 %s' | wc -l", v.nexthop):q
                    local pp   = io.popen(command)
                    local data = tonumber(pp:read("*a"))
                    pp:close()
                    if data == 0 then
                        os.execute(string.format("route add -net 0.0.0.0 netmask 0.0.0.0 gw %s", v.nexthop))
                    end
                    ilog("ifdown vpn and default gw: %s", v.nexthop)
                end
            end
            ]]
            -- openvpn stop
            if g.status.proto == "openvpn" then
                elog("openvpn stop")
                os.execute("/etc/init.d/openvpn stop")
                os.exit(0)
            end
			
			if g.status and g.status.up then
				os.execute("ifdown vpn")
			end	
            os.exit(0)

        elseif g.action == "status" then
            if g.status.proto == "openvpn" then
                elog("openvpn get status")
                status = conn:call("network.interface", "status", {['interface']="openvpn"})
                local openvpn_auto = cursor:get("network","openvpn","auto")
                --elog(string.format("openvpn_auto %s", openvpn_auto))
                --status.stat = get_last_msg()
                if status ~= nil then
                    if status.up == false then
                        local ret = LuciUtil.exec('ps | grep openvpn | grep -v grep |grep -v openvpn_deamon 2>/dev/null')
                        elog(string.format("ret %s", ret))
                        if ret == '' then
                            status["stat"] = {code=501}
                            if openvpn_auto == "1" then
                                -- if openvpn auth failed, return 507[code 1586] error
                                elog("openvpn connect failed !!!")
                                os.execute("/etc/init.d/openvpn stop")
                                status["stat"] = {code=507}
                            end
                        else
                            status["stat"] = {code=0}
                        end
                    else
                        status["stat"] = {code=0}
                    end
                    elog(string.format("status.stat.code [%s]", status.stat.code))
                else
                    -- if openvpn config failed, return 501[code 1584] error
                    status = {autostart=true, up=false, stat={code=1}}
                    status["stat"] = {code=501}
                end
                print(json.encode(status))
                os.exit(0)
            end
            status = conn:call("network.interface", "status", {['interface']="vpn"})
            status.stat = get_last_msg()
            status.auto = cursor:get("network","vpn","auto")
            print(json.encode(status))
            os.exit(0)

        else
            print(string.format("usage: %s <up|down|status>", arg[0]))
            os.exit(1)

        end
    end
)
if not status then
    elog(err)
end
