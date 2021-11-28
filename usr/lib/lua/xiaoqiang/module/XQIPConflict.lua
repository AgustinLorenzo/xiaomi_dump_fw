module ("xiaoqiang.module.XQIPConflict", package.seeall)

local bit           = require("bit")
local json          = require("json")
local util          = require("luci.util")
local xqfunction    = require("xiaoqiang.common.XQFunction")

function _gen_new_ip(ip)
    if ip then
        local wan = ip:gsub(".%d+.%d+$", "")
        local cip = tonumber(ip:match(".(%d+).%d+$"))
        -- reverse the last two digits in case of guest-wifi has been set up
        local newip = wan.."."..tostring(bit.bxor(cip, 3))..".1"
        return newip
    end
    return ""
end

-- detect whether there is IP conflict
-- @return true/false
function ip_conflict_detection()
    -- local nettb = util.exec("/usr/sbin/nettb 2>/dev/null")
    -- if xqfunction.isStrNil(nettb) then
    --     return false
    -- end
    -- nettb = util.trim(nettb)
    -- local succ, info = pcall(json.decode, nettb)
    -- if succ and info then
    --     if tonumber(info.code) == 4 then
    --         return true
    --     end
    -- end
    -- return false
    local lanwan = require("xiaoqiang.util.XQLanWanUtil")
    local uci = require("luci.model.uci").cursor()
    local proto = uci:get("network", "wan", "proto")
    local lanip = uci:get("network", "lan", "ipaddr")
    local mode  = xqfunction.getNetModeType()
    if (proto ~= "dhcp" and proto ~= "static") or mode ~= 0 then
        return false
    end
    local ubuswan = lanwan.ubusWanStatus()
    if ubuswan and ubuswan["ipv4"] then
        local ip = ubuswan["ipv4"]["address"]
        if ip:gsub(".%d+$", "") == lanip:gsub(".%d+$", "") then
            return _gen_new_ip(ip)
        end
    end
    return false
end

-- modify configuration files
function ip_conflict_resolution()
    local messagebox = require("xiaoqiang.module.XQMessageBox")
    local uci    = require("luci.model.uci").cursor()
    local event  = require("xiaoqiang.XQEvent")
    local lanwan = require("xiaoqiang.util.XQLanWanUtil")
    local ubuswan = lanwan.ubusWanStatus()
    if ubuswan and ubuswan["ipv4"] then
        local ip = ubuswan["ipv4"]["address"]
        if ip then
            messagebox.removeMessage(4)
            local newip = _gen_new_ip(ip)
            uci:set("network", "lan", "ipaddr", newip)
            uci:commit("network")
            event.lanIPChange(newip)
        end
    end
end

-- restart related services
-- plz note here, dnsmasq need to stop before restart if lan-ip changed.
function restart_services(async)
    local cmd = [[
        sleep 4;
        /etc/init.d/network restart 2>/dev/null;
        /etc/init.d/dnsmasq stop 2>/dev/null;
        /etc/init.d/dnsmasq restart 2>/dev/null;
        /usr/sbin/dhcp_apclient.sh restart lan 2>/dev/null;
        /etc/init.d/trafficd restart 2>/dev/null;
        /etc/init.d/minet restart 2>/dev/null;
        /usr/sbin/shareUpdate -b 2>/dev/null
    ]]
    if async then
        xqfunction.forkExec(cmd)
    else
        os.execute(cmd)
    end
end
