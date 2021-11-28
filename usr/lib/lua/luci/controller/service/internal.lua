module("luci.controller.service.internal", package.seeall)

function index()
    local page   = node("service","internal")
    page.target  = firstchild()
    page.title   = ("")
    page.order   = nil
    page.sysauth = "admin"
    page.sysauth_authenticator = "jsonauth"
    page.index = true
    entry({"service", "internal", "ccgame"}, call("turbo_ccgame_call"), (""), nil, 0x10)
    entry({"service", "internal", "ipv6"}, call("turbo_ipv6_call"), (""), nil, 0x10)
    entry({"service", "internal", "custom_host_get"}, call("custom_host_get"), (""), nil, 0x10)
    entry({"service", "internal", "custom_host_set"}, call("custom_host_set"), (""), nil, 0x10)
end

local LuciHttp = require("luci.http")
local XQConfigs = require("xiaoqiang.common.XQConfigs")
local ServiceErrorUtil = require("service.util.ServiceErrorUtil")
local XQFunction = require("xiaoqiang.common.XQFunction")
local LuciJson = require("cjson")
local LuciUtil = require("luci.util")
local fs   = require("nixio.fs")
local nixio = require ("nixio")
local logger = require("xiaoqiang.XQLog")

function check_and_run_ubus_ready(conn,sname,scmd) 
    if not conn then
        return false
    end

    for i=1,2 do
        local objs=conn:objects()
        local exist=false
        for i,v in ipairs(objs) do
            if v == sname then
                return true
            end
        end
    
        XQFunction.forkExec(scmd)
        nixio.nanosleep(1)
    end
    
    return false
end

-- ccgame call interface
function turbo_ccgame_call()
    local cmd = tonumber(LuciHttp.formvalue("cmd") or "")
    local result={}
    local XQCCGame = require("turbo.ccgame.ccgame_interface")
    if not XQCCGame then
        result['code'] = -1
        result['msg'] = 'not support ccgame.'
    elseif cmd < 0 or cmd > 7 then
        result['code'] = -1
        result['msg'] = 'action id is not valid'
    else
        local para ={}
        para.cmdid = cmd
        para.data={}
        local strIPlist = LuciHttp.formvalue("ip")
        local strByVPN = LuciHttp.formvalue("byvpn")
        local strGame = LuciHttp.formvalue("game")
        local strRegion = LuciHttp.formvalue("region")
        local strUbus = LuciHttp.formvalue("ubus")

        if strIPlist then
            para.data['iplist'] = XQFunction._cmdformat(strIPlist)
        end
        if strByVPN and strByVPN ~= "0" then
            para.data['byvpn'] = "0"
        else
            para.data['byvpn'] = "1"
        end

        if strGame and strRegion then
            para.data['gameid'] = XQFunction._cmdformat(strGame)
            para.data['regionid'] = XQFunction._cmdformat(strRegion)
        end

        if strUbus then
            para.ubus = XQFunction._cmdformat(strUbus)
        end

        result = XQCCGame.ccgame_call(para)
    end
    LuciHttp.write_json(result)
end

-- turbo ipv6 interface
function turbo_ipv6_call()
    local cmd = tonumber(LuciHttp.formvalue("cmd") or "")
    local result={}
    if cmd < 0 or cmd > 3 then
        result['code'] = -1
        result['msg'] = 'action id is not valid'
    else
        local ubus = require("ubus")
        local conn = ubus.connect()
        if not conn then
            result['code'] = -1
            result['msg'] = 'ubus cannot connected.'
        else
            if not check_and_run_ubus_ready(conn,'turbo_ipv6','/etc/init.d/turbo start_ipv6') then
                result['code'] = -1
                result['msg'] = 'ubus service is not running...'
            else
                local query=nil
                local ubus_service = 'turbo_ipv6'
                local data={}
                if cmd == 1 then
                    -- need active account 1stly
                    local pdata={provider="sellon"}
                    local cmd = "matool --method api_call_post --params /device/vip/account '" .. LuciJson.encode(pdata) .. "'"

                    local ret, account = pcall(function() return LuciJson.decode(LuciUtil.trim(LuciUtil.exec(cmd))) end)

                    if not ret or not account or type(account) ~= "table" or account.code ~= 0 then
                        result['code'] = -1
                        result['msg'] = 'active account failed. pls check if account binded or network is connected.'
                        query = nil
                    else
                        query = 'start'
                    end
                elseif cmd == 2 then
                    query = 'stop'
                elseif cmd == 3 then
                    query = 'status'
                elseif cmd == 0 then
                    query = XQFunction._cmdformat(LuciHttp.formvalue("ubus") or "nothing")
                else
                    query = nil
                    result.msg = 'not supported command.'
                end

                if query and query ~= '' then
                    local res = conn:call(ubus_service, query, data)
                    conn:close()
                    if res then
                        result = res
                    else
                        result['code'] = -1
                        result['msg'] = 'call ubus failed.'
                    end
                else
                    result.code = -1
                end
            end
        end
    end
    LuciHttp.write_json(result)
end

-- custom host interface for plugin
function custom_host_get()
    local dstPath = '/tmp/hosts/custom_hosts'
    local result ={
        code = 0,
        msg = 'OK'
    }
    if fs.access(dstPath) then
        -- read file
        hFile = io.open(dstPath, "r")
        local data={}
        for line in hFile:lines() do
            local s,_,sip,shost = string.find(line,"^%s*([0-9A-Fa-f.:]+)%s*([^%s]+)%s*")
            if s and sip and shost then
                data[#data+1] = sip .. ' ' .. shost
            end
        end
        hFile:close()
        result['hosts'] = data
    else
        result['code'] = -1
        result['msg'] = "read hosts file failure."
    end
    LuciHttp.write_json(result)        
end

function custom_host_set()
    --rewrite /etc/hosts, and enable dnsmasq to read it
    local param = LuciHttp.formvalue("hosts") or ""
    local result={
        code=0,
        msg='OK'
    }
    local ret, hosts = pcall(function() return LuciJson.decode(LuciUtil.trim(param)) end)
    local srcPath = '/etc/custom_hosts'
    local dstPath = '/tmp/hosts/custom_hosts'

    if ret and hosts then
        -- write header 1stly
        hFile = io.open(srcPath ,"w")
        hFile:write("#generated by plugin, DONOT edit it\n")
        for _,v in pairs(hosts) do
            local s,_,sip,shost = string.find(v,"^%s*([0-9A-Fa-f.:]+)%s*([^%s]+)%s*")
            if s and sip and shost then hFile:write(sip," ",shost,"\n") end
        end
        hFile:close()
        -- copy hosts file to tmp
        fs.copy(srcPath,dstPath)

        -- active hosts into dnsmasq
        LuciUtil.exec("/etc/init.d/dnsmasq restart")
    else
        result['code'] = -1
        result['msg'] = 'parameter hosts lost or foramt invalid.'
    end
    LuciHttp.write_json(result)
end