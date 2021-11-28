#!/usr/bin/lua
--[[
check wan status and light with colors
--]]

--local uci = require 'luci.model.uci'
--local fs = require "nixio.fs"
local LuciUtil = require "luci.util"
local px = require "posix"

local mytimer
local timer_interval=8000  -- 8s interval

local lockfile="/var/run/check_wan_status.lock"
local ethstt="/sbin/ethstatus"
local target_domain={"www.baidu.com","www.qq.com","www.taobao.com"}
local target_ip={"114.114.114.114","180.76.76.76","119.29.29.29","223.5.5.5"}
local xqled="/usr/sbin/xqled"
local dns_intercept_file="/tmp/state/dns_intercept"
local target_dns={"api.miwifi.com","www.baidu.com","www.taobao.com"}

local inited=false

-- common state
local wan_port=nil
local current_light=''
local xqled_ok=false
local is_main_router=true

local is_wan_pluged_in=false

-- init uloop
local uloop = require "uloop"
-- init ubus
local ubus = require "ubus"
local conn

function check_inited()
    res=run_cmd("uci -q get xiaoqiang.common.INITTED")
    if res and res == 'YES' then
        inited=true
    else
        logger('router is not INITED, will keep light OFF. plz note.')
        inited=false
    end
end

function reset()
    is_main_router = true
    xqled_ok = false
    current_light = ''
    wan_port=nil
    inited=false

    local res
    res=run_cmd("[ -f " .. xqled .. " ] && echo 0 ")
    if res and res ~= '' then
        xqled_ok = true
    else
        logger('xqled light not working. plz note.')
        xqled_ok = false
    end

    check_inited()    

    -- read netmode
    read_netmode()

    wan_port = read_wan_port()
    if wan_port == nil then
        logger("cannot get WAN port from uci. exit.")
        os.exit(-1)
    end
end

function init()

    -- init variables
    reset()

    uloop.init()

    conn = ubus.connect()
    if not conn then
        logger("init ubus failed. exit.")
        os.exit(-1)
    end

end

function trim(str)
    -- print(str or '')
    if str then
        return str:gsub("^%s+", ""):gsub("%s+$", "")
    else
        return ''
    end
end

function logger(msg)
    px.syslog(3, "WAN_CHECK:" .. msg)
end

function run_cmd(cmd)
    -- print(cmd)
    return trim(LuciUtil.exec(cmd))
end

function light(stat)
    if current_light ~= stat then
        logger("WAN state Changed: " .. current_light .. ' -> ' .. stat)
        current_light = stat
        local light_act=''
        if xqled_ok then
            if stat == 'off' then
                light_act = "/usr/sbin/xqled link_down"
            elseif stat == 'yellow' then
                light_act = "/usr/sbin/xqled link_connfail"
            elseif stat == 'blue' then
                light_act = "/usr/sbin/xqled link_conned"
            elseif stat == 'blueing' then
                light_act = "/usr/sbin/xqled link_conning"
            end

            if light_act and light_act ~= '' then
                run_cmd('[ -f "/usr/sbin/xqled" ] && ' .. light_act)
            end
        end
    end
end

function check_by_DNS_query(target)
    local res
    for _,v in pairs(target) do
        res=run_cmd('timeout -t2 nslookup ' .. v .. ' 2>/dev/null|grep "Address" |awk -F": " ' .. " '{print $2}' " .. '|grep -v "127.0.0.1" |grep -v "^10." |grep -v "^192.168" |grep -v "^169.254"')
        if res and res ~= '' then
            return true
        end
    end
    return false
end

function check_by_PING(target)
    local res
    for _,v in pairs(target) do
        res=run_cmd('timeout -t2 ping -4 -c1 -w1 ' .. v .. ' >/dev/null 2>&1 && echo "0"')
        if res and res ~= '' then
            return true
        end
    end
    return false
end

function read_wan_port()
    local res=run_cmd("uci -q get misc.sw_reg.sw_wan_port")
    if res and res ~= '' then
        return res
    end
    return nil
end

function read_netmode()
    local res=run_cmd("uci -q get xiaoqiang.common.NETMODE")
    if res == 'whc_re' or res == 'wifiapmode' or res == 'lanapmode' then
        logger("Router is in AP mode: " .. res)
        is_main_router = false
    else
        logger("Router is in Router mode.")
        is_main_router = true
    end
end

--read link port
function check_if_wan_port_UP()
    local res = run_cmd('[ -f ' .. ethstt .. ' ] && ' .. ethstt .. ' | grep "port ' .. wan_port ..':up"')
    if res and res ~= '' then
        if not is_wan_pluged_in then
            is_wan_pluged_in = true
        end
        return true
    end
    
    if is_wan_pluged_in then
        is_wan_pluged_in = false
        logger('WAN is plugged OUT. plz note.')
    end
    return false
end

function check_if_internet_UP()
    -- check by DNS 1stly
    if check_by_DNS_query(target_dns) then
        return true
    end

    --logger("dnsmasq seems not working....");

    -- only ping ip
    if check_by_PING(target_ip) then
        logger("ERROR: dnsmasq resolve domain NOK, but ping ip OK !!!!")
        return true
    end

    return false
end

function check_work()
    if inited == false then
        light("off")
        return
    end
    if is_main_router == true then
        if check_if_wan_port_UP() == false then
            light("off")
            return
        elseif current_light == 'off' then
            light("yellow")
        end

        if check_if_internet_UP() == false then
            light("yellow")
            return
        end

        light("blue")
    else
        -- for ap-mode, blue if connected, off if not-conneted
        if check_if_internet_UP() == false then
            light("yellow")
        else
            light("blue")
        end
    end

end

-- ubus call interface
my_method = {
    check_wan =
    {
        update = {
            function(req, msg)
                local ret = { code = 0, msg = 'ok' }
                logger("event update to check wan status.")
                mytimer:set(1)
                conn:reply(req, ret)
            end, {}
        },
        reset ={
            function(req, msg)
                mytimer:set(1)
                reset()
                conn:reply(req, {code=0,msg='ok'})
            end, {}
        }
    },
}


function timer_process()
    check_work()
	mytimer:set(timer_interval)
end

--try to start ccgame service
local function main_service()
    logger("check_wan_status service ubus binding....")
    init()

    conn:add(my_method)
    mytimer = uloop.timer(timer_process)
    mytimer:set(timer_interval)

    uloop.run()
end

-- main
main_service()

