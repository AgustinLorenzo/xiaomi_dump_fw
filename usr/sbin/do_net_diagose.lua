#!/usr/bin/lua
local LuciUtil = require("luci.util")
local XQFunction = require("xiaoqiang.common.XQFunction")

function saveNettb(result)
    local XQPreference = require("xiaoqiang.XQPreference")
    if result then
        XQPreference.set("NETTB", result)
    end
end

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

function nettb()
    local LuciJson = require("json")
    local LuciUtil = require("luci.util")
    local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
    local nettb = {
        ["code"] = 0,
        ["reason"] = ""
    }
    local result = LuciUtil.exec("/usr/sbin/nettb")
    if not XQFunction.isStrNil(result) then
        result = LuciUtil.trim(result)
        result = LuciJson.decode(result)
        if result.code then
            nettb.code = tonumber(result.code)
            if nettb.code == 32 then
                nettb.code = XQLanWanUtil._pppoeError(691) or 33
            elseif nettb.code == 33 then
                nettb.code = XQLanWanUtil._pppoeError(678) or 35
            end
            --nettb.reason = NETTB[tostring(result.code)]
        else
            nettb.code = -1
        end
    end
    return nettb
end

--print("start!")
result = nettb()
--print("code:"..result.code.." msg: "..result.reason)
saveNettb(tostring(result.code))
