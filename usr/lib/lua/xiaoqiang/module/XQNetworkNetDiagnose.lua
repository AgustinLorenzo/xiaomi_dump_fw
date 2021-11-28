module ("xiaoqiang.module.XQNetworkNetDiagnose", package.seeall)

local LuciUtil = require("luci.util")
local XQFunction = require("xiaoqiang.common.XQFunction")

NETTB = {
    ["1"] = "wan port unplug",
    ["2"] = "dhcp no server",
    ["3"] = "pppoe no reaponse",
    ["4"] = "dhcp upstream conflict",
    ["5"] = "gateway unreachable",
    ["6"] = "dns resolve failed",
    ["7"] = "dns custom set",
    ["8"] = "wifi_ap gateway unreachable",
    ["9"] = "wired_ap gateway unreachable",
    ["10"] = "link broken",
    ["31"] = "pppoe no more sesson",
    ["32"] = "pppoe password error",
    ["33"] = "pppoe account not valid",
    ["34"] = "pppoe need reset mac",
    ["35"] = "pppoe stop by user"
}

function execl2(command)
    local pp   = io.popen(command)
    local line = ""
    local data = {}

    while true do
        line = pp:read()
        if line == nil then
            break
        end
        data[#data+1] = line
    end
    pp:close()
    return data
end

function saveNettb(result)
    local XQPreference = require("xiaoqiang.XQPreference")
    if result then
        XQPreference.set("NETTB", result)
    end
end

function getWanMode()
    local pp = io.popen("uci -q get network.wan.proto")
    local model = pp:read("*line")
    pp:close()

    return model
end

function getDnsIp()
    local dnsres = execl2("cat /tmp/resolv.conf.auto")
    local dnsip
    if dnsres and next(dnsres)~=nil then
        local i = 0
        for k,v in ipairs(dnsres) do
            --print("line"..k..": "..v)
            if i > 2 then
                break
            end

            local _,_,ip = string.find(v, 'nameserver ([0-9]+%.[0-9]+%.[0-9]+%.[0-9]+)')
            if ip then
               --print("find ip: "..ip)
               i = i + 1
               if dnsip then
                   dnsip = dnsip.." "..ip
               else
                   dnsip = ip
               end
               --print("dnsip: "..dnsip)
            end
        end
        if dnsip then
            return dnsip
        else
            return "0"
        end
    else
        return "0"
    end
end

function getNetDiagResult()
    local XQPreference = require("xiaoqiang.XQPreference")
    local nettb = tonumber(XQPreference.get("NETTB"))
    if nettb then
        if nettb == 99  then
            return nettb,"detecting..."
        elseif nettb == 0 then
            return nettb,"network ok!"
        else
            local result = NETTB[tostring(nettb)]
            if result then
                return nettb,result
            end
            return -1,"unknown nettb code!"
        end
    else
        return -2,"no diag result!"
    end
end

function asyncNetDiag()
    saveNettb("99")
    XQFunction.forkExec("lua /usr/sbin/do_net_diagose.lua")
end
