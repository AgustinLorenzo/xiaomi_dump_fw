module ("xiaoqiang.module.XQTopology", package.seeall)

local Json = require("cjson")

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")
local LuciUtil = require("luci.util")
--local XQLog = require("xiaoqiang.XQLog")

function _recursive(item)
    --XQLog.log(6,"hostname:"..item.hostname)
    --XQLog.log(6,"locale:"..item.description.locale)
    local result = {
        ["ip"] = "",
        ["name"] = item.hostname or "",
        ["locale"] = item.locale or "",
        ["hardware"] = "",
        ["channel"] = "",
        ["mode"] = tonumber(item.is_ap or "0"),
        ["version"] = item.version or "",
        ["ssid"] = "",
        ["color"] = 100
    }
    if string.lower(result.name):match("^xiaomirepeater") then
        result.name = "小米中继器"
    end
    local description = item.description
    local function decode(str)
        description = Json.decode(str)
    end
    if not XQFunction.isStrNil(item.description) then
        if pcall(decode, item.description) then
            result.hardware = description.hardware
            result.channel = description.channel
            result.color = description.color
            result.ssid = description.ssid
            result.ip = description.ip
            -- add locale for ap and whc_re
            result.locale = description.locale
        end
    end
    local leafs = {}
    if XQFunction.isStrNil(result.ip) and item.ip_list and #item.ip_list > 0 then
        local dev = item.ifname or ""
        for _, ip in ipairs(item.ip_list) do
            if (not dev:match("wl") or (dev:match("wl") and tonumber(item.assoc) == 1))
                and ip.ageing_timer <= 300 and (ip.tx_bytes ~= 0 or ip.rx_bytes ~= 0) then
                result.ip = ip.ip
                break
            end
        end
    end
    if item.child and #item.child > 0 then
        for _, newitem in ipairs(item.child) do
            if newitem.is_ap ~= nil and newitem.is_ap ~= 0 then
                table.insert(leafs, _recursive(newitem))
            end
        end
        if #leafs > 0 then
            result["leafs"] = leafs
        end
    end
    return result
end

function topologicalGraph()
    local XQSysUtil = require("xiaoqiang.util.XQSysUtil")
    local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local wifi = XQWifiUtil.getWifiStatus(1) or {}
    local ubuscall = "ubus call trafficd hw '{\"tree\":true}'"
    local tree = LuciUtil.exec(ubuscall)

    local graph = {
        ["ip"] = XQLanWanUtil.getLanIp(),
        ["name"] = XQSysUtil.getRouterName(),
        ["locale"] = XQSysUtil.getRouterLocale(),
        ["hardware"] = XQSysUtil.getHardware(),
        ["channel"] = XQSysUtil.getChannel(),
        ["mode"] = XQFunction.getNetModeType(),
        ["color"] = XQSysUtil.getColor(),
        ["ssid"] = wifi.ssid or ""
    }
    if XQFunction.isStrNil(tree) then
        return graph
    else
        tree = Json.decode(tree)
    end

    local leafs = {}
    for key, item in pairs(tree) do
        if item.is_ap ~= nil and item.is_ap ~= 0 then
            table.insert(leafs, _recursive(item))
        end
    end
    if #leafs > 0 then
        graph["leafs"] = leafs
    end
    return graph
end

function _simpleRecursive(item)
    local result = {
        ["mac"] = XQFunction.macFormat(item.hw),
        ["mac5G"] = ""
    }
    if XQFunction.isStrNil(item.description) then
        return nil
    end
    local succeed, description = pcall(Json.decode, item.description)
    if not succeed or not description
        or (description.hardware and string.lower(description.hardware) ~= "r01" and XQFunction.isStrNil(description.bssid1)) then
        return nil
    end
    if not XQFunction.isStrNil(description.bssid1) then
        result.mac = description.bssid1
    end
    if not XQFunction.isStrNil(description.bssid2) then
        result.mac5G = description.bssid2
    end
    if description.hardware and string.lower(description.hardware) == "r01" then
        if XQFunction.isStrNil(description.mac) then
            result["needConvert"] = true
        else
            result["mac"] = XQFunction.macFormat(description.mac)
        end
    end
    local leafs = {}
    if item.ip_list and #item.ip_list > 0 then
        local dev = item.ifname or ""
        for _, ip in ipairs(item.ip_list) do
            if (not dev:match("wl") or (dev:match("wl") and tonumber(item.assoc) == 1))
                and ip.ageing_timer <= 300 and (ip.tx_bytes ~= 0 or ip.rx_bytes ~= 0) then
                break
            end
        end
    end
    if item.child and #item.child > 0 then
        for _, newitem in ipairs(item.child) do
            if newitem.is_ap ~= nil and newitem.is_ap ~= 0 then
                local leaf = _simpleRecursive(newitem)
                if leaf then
                    table.insert(leafs, leaf)
                end
            end
        end
        if #leafs > 0 then
            result["leafs"] = leafs
        end
    end
    return result
end

function simpleTopoGraph()
    local wifi = require("xiaoqiang.util.XQWifiUtil")
    local bssid, bssid5 = wifi.getWifiBssid()
    local graph = {
        ["mac"] = bssid,
        ["mac5G"] = bssid5 or ""
    }
    local tree = LuciUtil.exec("ubus call trafficd hw '{\"tree\":true}'")
    if XQFunction.isStrNil(tree) then
        return graph
    else
        tree = Json.decode(tree)
    end
    local leafs = {}
    for key, item in pairs(tree) do
        if item.is_ap ~= nil and item.is_ap ~= 0 then
            local leaf = _simpleRecursive(item)
            if leaf then
                table.insert(leafs, leaf)
            end
        end
    end
    if #leafs > 0 then
        graph["leafs"] = leafs
    end
    return graph
end
