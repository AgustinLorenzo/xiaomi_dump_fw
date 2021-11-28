module ("xiaoqiang.module.XQEcos", package.seeall)

local Json          = require("json")
local LuciUtil      = require("luci.util")
local XQFunction    = require("xiaoqiang.common.XQFunction")
local ExtenderHw = { R01=1, R02=1, R03=1 }

function _getEcosDevices()
    local devices = LuciUtil.exec("ubus call trafficd hw")
    if XQFunction.isStrNil(devices) then
        return {}
    end
    local ecos = {}
    devices = Json.decode(devices)
    for mac, item in pairs(devices) do
       local suc,des = nil
       if item.description then
            -- parse desc
            suc, des = pcall(Json.decode, item.description)
       end
       if suc and des and des.hardware and ExtenderHw[des.hardware] then
            if item.version
                and tonumber(item.is_ap) ~= 0
                and tonumber(item.assoc) == 1 then
                local dev = {
                    ["mac"]     = mac,
                    ["version"] = item.version,
                    ["channel"] = "current",
                    ["color"]   = des.color or "100",
                    ["sn"]      = des.sn or "",
                    ["ctycode"] = des.country_code or "CN"
                }
                local ips = item.ip_list
                if #ips > 0 then
                    dev["ip"] = ips[1].ip
                end
                dev["channel"] = des.channel or "current"
                if dev.ip then
                    ecos[mac] = dev
                end
            end
        end
    end
    return ecos
end

-- signal: 1/2/3 优/良/差
function _getEcosSignal(mac)
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local signal = tonumber(XQWifiUtil.getWifiDeviceSignal(mac))
    if signal then
        if signal < -70 then
            return 3
        elseif signal > -60 then
            return 1
        else
            return 2
        end
    end
    return nil
end

function _getEcosSignalDB(mac)
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local signal = tonumber(XQWifiUtil.getWifiDeviceSignal(mac)) or -70
    return signal
end

function _getEcosUpgrade(version, channel, sn, countryCode)
    local XQNetUtil = require("xiaoqiang.util.XQNetUtil")
    local info = XQNetUtil.checkEcosUpgrade(version, channel, sn, countryCode)
    if info and info.needUpdate == 1 then
        return info
    else
        return nil
    end
end

function _getEcosWRoamingStatus(ip)
    if not ip then
        return nil
    end
    local des = LuciUtil.exec("tbus call "..ip.." desc \"{\\\"desc\\\":1}\" 2>/dev/null")
    if des then
        local suc, res = pcall(Json.decode, des)
        if suc then
            return res.switch_wifi_explorer or 0
        end
    end
    return 0
end

function getEcosInfo(mac)
    if XQFunction.isStrNil(mac) then
        return nil
    end
    local info = {}
    local ecoses = _getEcosDevices()
    local ecos = ecoses[mac]
    if ecos then
        local upgrade = _getEcosUpgrade(ecos.version, ecos.channel, ecos.sn, ecos.ctycode)
        if upgrade then
            info["upgrade"] = true
            info["upgradeinfo"] = upgrade
        else
            info["upgrade"] = false
        end
        info["signal"]      = _getEcosSignal(mac) or 2
        info["signalDB"]    = _getEcosSignalDB(mac)
        info["roaming"]     = _getEcosWRoamingStatus(ecos.ip) or 0
        info["version"]     = ecos.version
        info["channel"]     = ecos.channel
        info["color"]       = ecos.color
        info["ip"]          = ecos.ip
        return info
    else
        return nil
    end
end

function ecosWirelessRoamingSwitch(mac, on)
    local ecoses = _getEcosDevices()
    local ecos = ecoses[mac]
    if ecos then
        local cmd = "tbus call "..ecos.ip.." switch \"{\\\"wifi_explorer\\\":"..(on and "1" or "0").."}\" >/dev/null 2>/dev/null"
        return os.execute(cmd) == 0
    end
    return false
end

function ecosUpgrade(mac)
    if mac then
        os.execute("echo 1 > /tmp/"..mac)
        local cmd = "lua /usr/sbin/ecos_upgrade.lua "..mac.." 2>/dev/null"
        XQFunction.forkExec(cmd)
    end
end

function ecosUpgradeStatus(mac)
    if mac then
        local fs = require("nixio.fs")
        local filepath = "/tmp/"..mac
        local status = fs.readfile(filepath)
        if tonumber(status) then
            return tonumber(status)
        end
    end
    return 0
end
