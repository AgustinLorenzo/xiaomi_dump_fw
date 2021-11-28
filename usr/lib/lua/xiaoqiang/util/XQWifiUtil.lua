module ("xiaoqiang.util.XQWifiUtil", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")

local LuciNetwork = require("luci.model.network")
local LuciUtil = require("luci.util")
local logger = require("xiaoqiang.XQLog")

local UCI = require("luci.model.uci").cursor()
local WIFI2G = UCI:get("misc", "wireless", "if_2G") or ""
local WIFI5G = UCI:get("misc", "wireless", "if_5G") or ""
local WIFIGUEST = UCI:get("misc", "wireless", "ifname_guest_2G") or ""
local HARDWARE = UCI:get("misc", "hardware", "model") or ""
if HARDWARE then
    HARDWARE = string.lower(HARDWARE)
end

local WIFI_DEVS = {
    WIFI2G,
    WIFI5G
}

local WIFI_NETS = {
    WIFI2G..".network1",
    WIFI5G..".network1"
}

function getWifiNames()
    return WIFI_DEVS, WIFI_NETS
end

function _wifiNameForIndex(index)
    return WIFI_NETS[index]
end

function wifiNetworks()
    local result = {}
    local network = LuciNetwork.init()
    local dev
    for _, dev in ipairs(network:get_wifidevs()) do
        local rd = {
            up       = dev:is_up(),
            device   = dev:name(),
            name     = dev:get_i18n(),
            networks = {}
        }
        local wifiNet
        for _, wifiNet in ipairs(dev:get_wifinets()) do
            rd.networks[#rd.networks+1] = {
                name       = wifiNet:shortname(),
                up         = wifiNet:is_up(),
                mode       = wifiNet:active_mode(),
                ssid       = wifiNet:active_ssid(),
                bssid      = wifiNet:active_bssid(),
                cssid      = wifiNet:ssid(),
                encryption = wifiNet:active_encryption(),
                frequency  = wifiNet:frequency(),
                channel    = wifiNet:channel(),
                cchannel   = wifiNet:confchannel(),
                bw         = wifiNet:bw(),
                cbw        = wifiNet:confbw(),
                signal     = wifiNet:signal(),
                quality    = wifiNet:signal_percent(),
                noise      = wifiNet:noise(),
                bitrate    = wifiNet:bitrate(),
                ifname     = wifiNet:ifname(),
                assoclist  = wifiNet:assoclist(),
                country    = wifiNet:country(),
                txpower    = wifiNet:txpower(),
                txpoweroff = wifiNet:txpower_offset(),
                key        = wifiNet:get("key"),
                key1       = wifiNet:get("key1"),
                encryption_src = wifiNet:get("encryption"),
                hidden = wifiNet:get("hidden"),
                txpwr = wifiNet:txpwr(),
                bsd = wifiNet:get("bsd"),
                txbf = dev:get("txbf") or "0",
                ax = dev:get("ax") or "0",
                weakenable = wifiNet:get("weakenable") or "0",
                weakthreshold = wifiNet:get("weakthreshold") or "0",
                kickthreshold = wifiNet:get("kickthreshold") or "0",
                apcliband = wifiNet:get("apcliband"),
                disabled = wifiNet:disabled(),
                sae = wifiNet:get("sae") or "0",
                sae_password  = wifiNet:get("sae_password")
            }
            -- add disabled params for old version.
            --logger.log(6, wifiNet:ifname())
            --logger.log(6, wifiNet:disabled())
            --logger.log(6, dev:is_up())
            if wifiNet:disabled() == nil then
                wifiNet:set("disabled", "0")
                logger.log(6, "init disabled =0 ifname: " ..wifiNet:ifname())
                network:save("wireless")
                network:commit("wireless")
            end
            -- add end
        end
        result[#result+1] = rd
    end
    return result
end

function wifiNetwork(wifiDeviceName)
    local network = LuciNetwork.init()
    local wifiNet = network:get_wifinet(wifiDeviceName)
    if wifiNet then
        local dev = wifiNet:get_device()
        if dev then
            return {
                id         = wifiDeviceName,
                name       = wifiNet:shortname(),
                up         = wifiNet:is_up(),
                mode       = wifiNet:active_mode(),
                ssid       = wifiNet:active_ssid(),
                bssid      = wifiNet:active_bssid(),
                cssid      = wifiNet:ssid(),
                encryption = wifiNet:active_encryption(),
                encryption_src = wifiNet:get("encryption"),
                frequency  = wifiNet:frequency(),
                channel    = wifiNet:channel(),
                cchannel   = wifiNet:confchannel(),
                bw         = wifiNet:bw(),
                cbw        = wifiNet:confbw(),
                signal     = wifiNet:signal(),
                quality    = wifiNet:signal_percent(),
                noise      = wifiNet:noise(),
                bitrate    = wifiNet:bitrate(),
                ifname     = wifiNet:ifname(),
                assoclist  = wifiNet:assoclist(),
                country    = wifiNet:country(),
                txpower    = wifiNet:txpower(),
                txpoweroff = wifiNet:txpower_offset(),
                key        = wifiNet:get("key"),
                key1       = wifiNet:get("key1"),
                hidden     = wifiNet:get("hidden"),
                txpwr = wifiNet:txpwr(),
                bsd = wifiNet:get("bsd"),
                disabled = wifiNet:disabled(),
                txbf = dev:get("txbf") or "0",
                ax = dev:get("ax") or "0",
                sae = wifiNet:get("sae") or "0",
                sae_password  = wifiNet:get("sae_password"),
                device     = {
                    up     = dev:is_up(),
                    device = dev:name(),
                    name   = dev:get_i18n()
                }
            }
        end
    end
    return {}
end

function getWifissid()
    local wifi2 = wifiNetwork(_wifiNameForIndex(1))
    local wifi5 = wifiNetwork(_wifiNameForIndex(2))
    return wifi2.cssid, wifi5.cssid
end

-- 2.4G, 5G
function getWifiBssid()
    local LuciUtil = require("luci.util")
    local XQSysUtil = require("xiaoqiang.util.XQSysUtil")
    -- Add for R3600, get mac of wl1 wl0.
    local hardware = XQSysUtil.getHardware()
    if hardware then
        if hardware == "R3600" or hardware == "R2200" or hardware == "R1800" then
            local bssid_2g = LuciUtil.exec("getmac wl1")
            local bssid_5g = LuciUtil.exec("getmac wl0")
            return LuciUtil.trim(bssid_2g), LuciUtil.trim(bssid_5g)
        elseif hardware == "R4C" then
            local bssid_2g = LuciUtil.exec("getmac wl1")
            return LuciUtil.trim(bssid_2g),""
        end
    end
    -- Add end
    local macs = LuciUtil.exec("getmac")
    if macs then
        macs = LuciUtil.trim(macs)
        local macarr = LuciUtil.split(macs, ",")
        if #macarr == 3 then
          return macarr[2], macarr[3]
        elseif #macarr == 2 then
          return macarr[2], nil
        end
    end
    return nil, nil
end

function getGuestWifiBssid()
    if not XQFunction.isStrNil(WIFIGUEST) then
        local LuciUtil = require("luci.util")
        local cmd = "cat /sys/class/net/"..WIFIGUEST.."/address 2>/dev/null"
        local bssid = LuciUtil.exec(cmd)
        if not XQFunction.isStrNil(bssid) then
            bssid = LuciUtil.trim(bssid)
            return XQFunction.macFormat(bssid)
        end
    end
    return nil
end

--[[
Get devices conneted to wifi
@param wifiIndex: 1 (2.4G)/ 2 (5G)
@return avaliable channel list
]]--
function getChannels(wifiIndex)
    local stat, iwinfo = pcall(require, "iwinfo")
    local iface = _wifiNameForIndex(wifiIndex)
    local cns
    if stat then
        local t = iwinfo.type(iface or "")
        if iface and t and iwinfo[t] then
            cns = iwinfo[t].freqlist(iface)
        end
    end
    return cns
end

local wifi24 = {
    ["1"] = {["20"] = "1", ["40"] = "1l"},
    ["2"] = {["20"] = "2", ["40"] = "2l"},
    ["3"] = {["20"] = "3", ["40"] = "3l"},
    ["4"] = {["20"] = "4", ["40"] = "4l"},
    ["5"] = {["20"] = "5", ["40"] = "5l"},
    ["6"] = {["20"] = "6", ["40"] = "6l"},
    ["7"] = {["20"] = "7", ["40"] = "7l"},
    ["8"] = {["20"] = "8", ["40"] = "8u"},
    ["9"] = {["20"] = "9", ["40"] = "9u"},
    ["10"] = {["20"] = "10", ["40"] = "10u"},
    ["11"] = {["20"] = "11", ["40"] = "11u"},
    ["12"] = {["20"] = "12", ["40"] = "12u"},
    ["13"] = {["20"] = "13", ["40"] = "13u"}
}

local wifi50 = {
    ["36"] = {["20"] = "36", ["40"] = "36l", ["80"] = "36/80"},
    ["40"] = {["20"] = "40", ["40"] = "40u", ["80"] = "40/80"},
    ["44"] = {["20"] = "44", ["40"] = "44l", ["80"] = "44/80"},
    ["48"] = {["20"] = "48", ["40"] = "48u", ["80"] = "48/80"},
    ["52"] = {["20"] = "52", ["40"] = "52l", ["80"] = "52/80"},
    ["56"] = {["20"] = "56", ["40"] = "56u", ["80"] = "56/80"},
    ["60"] = {["20"] = "60", ["40"] = "60l", ["80"] = "60/80"},
    ["64"] = {["20"] = "64", ["40"] = "64u", ["80"] = "64/80"},
    ["149"] = {["20"] = "149", ["40"] = "149l", ["80"] = "149/80"},
    ["153"] = {["20"] = "153", ["40"] = "153u", ["80"] = "153/80"},
    ["157"] = {["20"] = "157", ["40"] = "157l", ["80"] = "157/80"},
    ["161"] = {["20"] = "161", ["40"] = "161u", ["80"] = "161/80"},
    ["165"] = {["20"] = "165"}
}

local CHANNELS = {
    ["CN"] = {
        "0 1 2 3 4 5 6 7 8 9 10 11 12 13",
        "0 36 40 44 48 149 153 157 161 165"
    },
    ["TW"] = {
        "0 1 2 3 4 5 6 7 8 9 10 11",
        "0 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 149 153 157 161 165"
    },
    ["HK"] = {
        "0 1 2 3 4 5 6 7 8 9 10 11 12 13",
        "0 36 40 44 48 52 56 60 64 149 153 157 161 165"
    },
    ["US"] = {
        "0 1 2 3 4 5 6 7 8 9 10 11",
        "0 36 40 44 48 149 153 157 161 165"
    },
    ["EU"] = {
        "0 1 2 3 4 5 6 7 8 9 10 11 12 13",
        "0 36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140"
    },
    ["KR"] = {
        "0 1 2 3 4 5 6 7 8 9 10 11 12 13",
        "0 36 40 44 48 149 153 157 161"
    },
    ["ID"] = {
        "0 1 2 3 4 5 6 7 8 9 10 11 12 13",
        "0 149 153 157 161"
    }
}

local BANDWIDTH = {
    {"20"},
    {"20", "40"},
    {"20", "40", "80"}
}

function getDefaultWifiChannels(wifiIndex)
    local index = tonumber(wifiIndex) == 2 and 2 or 1
    local XQCountryCode = require("xiaoqiang.XQCountryCode")
    local ccode = XQCountryCode.getCurrentCountryCode()
    local channels = CHANNELS[ccode]
    local result = {}
    if channels then
        channels = channels[index]
        if channels then
            channels = LuciUtil.split(channels, " ")
            for _, channel in ipairs(channels) do
                local item = {["c"] = channel}
                if tonumber(channel) <= 14 then
                    item["b"] = BANDWIDTH[2]
                else
                    if tonumber(channel) == 165 then
                        item["b"] = BANDWIDTH[1]
                    else
                        item["b"] = BANDWIDTH[3]
                    end
                end
                table.insert(result, item)
            end
            return result
        end
    end
    return {}
end

--[[
Get devices conneted to wifi
@param wifiIndex: 1 (2.4G)/ 2 (5G)
@return divices list
]]--
function getWifiConnectDeviceList(wifiIndex)
    local wifiUp
    local assoclist = {}
    if tonumber(wifiIndex) == 1 then
        wifiUp = (getWifiStatus(1).up == 1)
        assoclist = wifiNetwork(_wifiNameForIndex(1)).assoclist or {}
    else
        wifiUp = (getWifiStatus(2).up == 1)
        assoclist = wifiNetwork(_wifiNameForIndex(2)).assoclist or {}
    end
    local dlist = {}
    if wifiUp then
        for mac, info in pairs(assoclist) do
            table.insert(dlist, XQFunction.macFormat(mac))
        end
    end
    return dlist
end

function isDeviceWifiConnect(mac,wifiIndex)
    local dict = getWifiConnectDeviceDict(wifiIndex)
    if type(dict) == "table" then
        return dict[XQFunction.macFormat(mac)] ~= nil
    else
        return false
    end
end

--[[
Get devices conneted to wifi
@param wifiIndex: 1 (2.4G)/ 2 (5G)
@return divices dict{mac:1}
]]--
function getWifiConnectDeviceDict(wifiIndex)
    local wifiUp
    local assoclist = {}
    if tonumber(wifiIndex) == 1 then
        wifiUp = (getWifiStatus(1).up == 1)
        assoclist = wifiNetwork(_wifiNameForIndex(1)).assoclist or {}
    else
        wifiUp = (getWifiStatus(2).up == 1)
        assoclist = wifiNetwork(_wifiNameForIndex(2)).assoclist or {}
    end
    local dict = {}
    if wifiUp then
        for mac, info in pairs(assoclist) do
            if mac then
                dict[XQFunction.macFormat(mac)] = 1
            end
        end
    end
    return dict
end

function _pauseChannel(channel)
    if XQFunction.isStrNil(channel) then
        return ""
    end
    if channel:match("l") then
        return channel:gsub("l","").."(40M)"
    end
    if channel:match("u") then
        return channel:gsub("u","").."(40M)"
    end
    if channel:match("\/80") then
        return channel:gsub("\/80","").."(80M)"
    end
    return channel.."(20M)"
end

function getWifiWorkChannel(wifiIndex)
    local channel = ""
    if HARDWARE:match("^rm1800$") or HARDWARE:match("^r3600") or HARDWARE:match("^r2200$") then
        if tonumber(wifiIndex) == 1 then
            channel = LuciUtil.trim(LuciUtil.exec("iwlist wl1 channel | awk -F '[ )]+' '/Current Frequency/{print $6}'"))
        else
            channel = LuciUtil.trim(LuciUtil.exec("iwlist wl0 channel | awk -F '[ )]+' '/Current Frequency/{print $6}'"))
        end
    else
        if tonumber(wifiIndex) == 1 then
            channel = LuciUtil.trim(LuciUtil.exec(XQConfigs.WIFI24_WORK_CHANNEL))
        else
            channel = LuciUtil.trim(LuciUtil.exec(XQConfigs.WIFI50_WORK_CHANNEL))
        end
    end
    return _pauseChannel(channel)
end

--[[
Get device wifiIndex
@param mac: mac address
@return 0 (lan)/1 (2.4G)/ 2 (5G)
]]--
function getDeviceWifiIndex(mac)
    mac = XQFunction.macFormat(mac)
    local wifi1Devices = getWifiConnectDeviceDict(1)
    local wifi2Devices = getWifiConnectDeviceDict(2)
    if wifi1Devices then
        if wifi1Devices[mac] == 1 then
            return 1
        end
    end
    if wifi2Devices then
        if wifi2Devices[mac] == 1 then
            return 2
        end
    end
    return 0
end

function getWifiDeviceSignalDict(wifiIndex)
    local result = {}
    local assoclist = {}
    if not (getWifiStatus(wifiIndex).up == 1) then
        return result
    end
    if wifiIndex == 1 then
        assoclist = wifiNetwork(_wifiNameForIndex(1)).assoclist or {}
    else
        assoclist = wifiNetwork(_wifiNameForIndex(2)).assoclist or {}
    end
    for mac, info in pairs(assoclist) do
        if mac then
            result[XQFunction.macFormat(mac)] = 2*math.abs(tonumber(info.signal)-tonumber(info.noise))
        end
    end
    return result
end

function getWifiDeviceSignal(mac)
    if XQFunction.isStrNil(mac) then
        return nil
    end
    local assoclist1 = wifiNetwork(_wifiNameForIndex(1)).assoclist or {}
    for amac, item in pairs(assoclist1) do
        if mac == amac then
            return item.signal
        end
    end
    local assoclist2 = wifiNetwork(_wifiNameForIndex(2)).assoclist or {}
    for amac, item in pairs(assoclist2) do
        if mac == amac then
            return item.signal
        end
    end
    return nil
end

-- diag requirement
function getWifiDeviceSpeed(mac)
    local result = {}
    if XQFunction.isStrNil(mac) then
        return nil
    end
    local assoclist1 = wifiNetwork(_wifiNameForIndex(1)).assoclist or {}
    for amac, item in pairs(assoclist1) do
        if mac == amac then
            result["upspeed"] = item.rx_rate
            result["downspeed"] = item.tx_rate
            return result
        end
    end
    local assoclist2 = wifiNetwork(_wifiNameForIndex(2)).assoclist or {}
    for amac, item in pairs(assoclist2) do
        if mac == amac then
            result["upspeed"] = item.rx_rate
            result["downspeed"] = item.tx_rate
            return result
        end
    end
    return nil
end

--[[
Get all devices conneted to wifi
@return devices list [{mac,signal,wifiIndex}..]
]]--
function getAllWifiConnetDeviceList()
    local result = {}
    for index = 1,2 do
        local wifiSignal = getWifiDeviceSignalDict(index)
        local wifilist = getWifiConnectDeviceList(index)
        for _, mac in pairs(wifilist) do
            table.insert(result, {
                    ['mac'] = XQFunction.macFormat(mac),
                    ['signal'] = wifiSignal[mac],
                    ['wifiIndex'] = index
                })
        end
    end
    return result
end

--[[
Get all devices conneted to wifi
@return devices dict{mac:{signal,wifiIndex}}
]]--
function getAllWifiConnetDeviceDict()
    local result = {}
    for index = 1,2 do
        local wifiSignal = getWifiDeviceSignalDict(index)
        local wifilist = getWifiConnectDeviceList(index)
        for _, mac in pairs(wifilist) do
            local item = {}
            item['signal'] = wifiSignal[mac]
            item['wifiIndex'] = index
            result[XQFunction.macFormat(mac)] = item
        end
    end
    return result
end

--[[
Get wifi status
@param wifiIndex: 1 (2.4G)/ 2 (5G)
@return dict{ssid,up}
]]--
function getWifiStatus(wifiIndex)
    local wifiNet = wifiNetwork(_wifiNameForIndex(wifiIndex))
    return {
        ['ssid'] = wifiNet["ssid"],
        ['up'] = wifiNet["up"] and 1 or 0
    }
end

function channelHelper(channel)
    local channelInfo = {channel = "", bandwidth = ""}
    if XQFunction.isStrNil(channel) then
        return channelInfo
    end
    if string.find(channel,"l") ~= nil then
        channelInfo["channel"] = channel:match("(%S+)l")
        channelInfo["bandwidth"] = "40"
    elseif string.find(channel,"u") ~= nil then
        channelInfo["channel"] = channel:match("(%S+)u")
        channelInfo["bandwidth"] = "40"
    elseif string.find(channel,"/80") ~= nil then
        channelInfo["channel"] = channel:match("(%S+)/80")
        channelInfo["bandwidth"] = "80"
    else
        channelInfo["channel"] = tostring(channel)
        channelInfo["bandwidth"] = "20"
    end
    local bandList = {}
    if channelInfo.channel then
        local channelList = wifi24[channelInfo.channel] or wifi50[channelInfo.channel]
        if channelList and type(channelList) == "table" then
            for key, v in pairs(channelList) do
                table.insert(bandList, key)
            end
        end
    end
    channelInfo["bandList"] = bandList
    return channelInfo
end

function getBandList(channel)
    local channelInfo = {channel = "", bandwidth = ""}
    if XQFunction.isStrNil(channel) then
        return channelInfo
    end
    local bandList = {}
    if tonumber(channel) ~= 0 then
        local wifi = getDefaultWifiChannels(1)
        local wifi2 = getDefaultWifiChannels(2)
        table.foreachi(wifi2,
            function (k, v)
                table.insert(wifi, v)
            end
        )
        if wifi and type(wifi) == "table" then
            for _, v in ipairs(wifi) do
                if v and tonumber(v.c) == tonumber(channel) then
                    bandList = v.b
                    break
                end
            end
        end
    end
    channelInfo["bandList"] = bandList
    return channelInfo
end

function _channelFix(channel)
    if XQFunction.isStrNil(channel) then
        return ""
    end
    channel = string.gsub(channel, "l", "")
    channel = string.gsub(channel, "u", "")
    channel = string.gsub(channel, "/80", "")
    return channel
end

function channelFormat(wifiIndex, channel, bandwidth)
    local channelList = {}
    if tonumber(wifiIndex) == 1 then
        channelList = wifi24[tostring(channel)]
    else
        channelList = wifi50[tostring(channel)]
    end
    if channelList and type(channelList) == "table" then
        local channel = channelList[tostring(bandwidth)]
        if not XQFunction.isStrNil(channel) then
            return channel
        end
    end
    return false
end

--[[
Get wifi information
@return dict{status,ifname,device,ssid,encryption,channel,mode,hidden,signal,password}
]]--
function getAllWifiInfo()
    local infoList = {}
    local infoDict = {}
    local wifis = wifiNetworks()
    for i,wifiNet in ipairs(wifis) do
        local item = {}
        local index = 1
        local channel = wifiNet.networks[index].cchannel
        if channel == "auto" then
            channel = "0"
        end
        item["channel"] = channel
        item["bandwidth"] = wifiNet.networks[index].cbw
        item["channelInfo"] = getBandList(channel)
        logger.log(6, wifiNet["up"])
        logger.log(6, wifiNet.networks[index].disabled)

        -- old method to get wifi status, from uci mt7603e disabled param. For old version online.
        if wifiNet.networks[index].disabled == nil then
            if wifiNet["up"] then
                item["status"] = "1"
                item["ssid"] = wifiNet.networks[index].ssid
                item["channelInfo"]["channel"] = wifiNet.networks[index].channel
                item["channelInfo"]["bandwidth"] = wifiNet.networks[index].bw
            else
                item["status"] = "0"
                item["ssid"] = wifiNet.networks[index].cssid
                item["channelInfo"]["channel"] = wifiNet.networks[index].cchannel
                item["channelInfo"]["bandwidth"] = wifiNet.networks[index].cbw
            end
        else
            -- new method to get wifi status, from uci wl disabled param.
            if wifiNet.networks[index].disabled == "1" then
                item["status"] = "0"
                item["ssid"] = wifiNet.networks[index].cssid
                item["channelInfo"]["channel"] = wifiNet.networks[index].cchannel
                item["channelInfo"]["bandwidth"] = wifiNet.networks[index].cbw
            else
                item["status"] = "1"
                item["ssid"] = wifiNet.networks[index].ssid
                item["channelInfo"]["channel"] = wifiNet.networks[index].channel
                item["channelInfo"]["bandwidth"] = wifiNet.networks[index].bw
            end
        end
        --[[    
        if wifiNet["up"] then
            item["status"] = "1"
            item["ssid"] = wifiNet.networks[index].ssid
            item["channelInfo"]["channel"] = wifiNet.networks[index].channel
            item["channelInfo"]["bandwidth"] = wifiNet.networks[index].bw
        else
            item["status"] = "0"
            item["ssid"] = wifiNet.networks[index].cssid
            item["channelInfo"]["channel"] = wifiNet.networks[index].cchannel
            item["channelInfo"]["bandwidth"] = wifiNet.networks[index].cbw
        end
        ]]
        local encryption = wifiNet.networks[index].encryption_src
        local key = wifiNet.networks[index].key
        if encryption == "wep-open" then
            key = wifiNet.networks[index].key1
            if key:len()>4 and key:sub(0,2)=="s:" then
                key = key:sub(3)
            end
        elseif encryption == "ccmp" then
            key = wifiNet.networks[index].sae_password
        end
        item["ifname"] = wifiNet.networks[index].ifname
        item["device"] = wifiNet.device..".network"..index
        item["mode"] = wifiNet.networks[index].mode
        item["hidden"] = wifiNet.networks[index].hidden or 0
        item["signal"] = wifiNet.networks[index].signal
        item["password"] = key
        item["encryption"] = encryption
        item["txpwr"] = wifiNet.networks[index].txpwr
        item["bsd"] = wifiNet.networks[index].bsd
        item["txbf"] = wifiNet.networks[index].txbf
        item["ax"] = wifiNet.networks[index].ax
        item["weakenable"] = wifiNet.networks[index].weakenable or 0
        item["weakthreshold"] = wifiNet.networks[index].weakthreshold or 0
        item["kickthreshold"] = wifiNet.networks[index].kickthreshold or 0
        infoDict[wifiNet.device] = item
    end
    if infoDict[WIFI2G] then
        table.insert(infoList, infoDict[WIFI2G])
    end
    if infoDict[WIFI5G] then
        table.insert(infoList, infoDict[WIFI5G])
    end
    --[[
    -- call from web, override guest wifi status
    local guestwifi = getGuestWifi(1)
    if guestwifi and XQFunction.getNetModeType() == 0 then
        table.insert(infoList, guestwifi)
    end
    ]]
    return infoList
end

--[[
Get wifi information
@return dict{status,ifname,device,ssid,encryption,channel,mode,hidden,signal,password}
]]--
function getDiagAllWifiInfo()
    local infoList = {}
    local infoDict = {}
    local wifis = wifiNetworks()
    for i,wifiNet in ipairs(wifis) do
        local item = {}
        local index = 1
        local channel = wifiNet.networks[index].cchannel
        item["channel"] = channel
        item["bandwidth"] = wifiNet.networks[index].cbw
        item["channelInfo"] = getBandList(channel)
        if wifiNet["up"] then
            item["status"] = "1"
            item["ssid"] = wifiNet.networks[index].ssid
            item["channelInfo"]["channel"] = wifiNet.networks[index].channel
            item["channelInfo"]["bandwidth"] = wifiNet.networks[index].bw
        else
            item["status"] = "0"
            item["ssid"] = wifiNet.networks[index].cssid
            item["channelInfo"]["channel"] = wifiNet.networks[index].cchannel
            item["channelInfo"]["bandwidth"] = wifiNet.networks[index].cbw
        end
        local encryption = wifiNet.networks[index].encryption_src
        local key = wifiNet.networks[index].key
        if encryption == "wep-open" then
            key = wifiNet.networks[index].key1
            if key:len()>4 and key:sub(0,2)=="s:" then
                key = key:sub(3)
            end
        elseif encryption == "ccmp" then
            key = wifiNet.networks[index].sae_password
        end
        item["ifname"] = wifiNet.networks[index].ifname
        item["device"] = wifiNet.device..".network"..index
        item["mode"] = wifiNet.networks[index].mode
        item["hidden"] = wifiNet.networks[index].hidden or 0
        item["signal"] = wifiNet.networks[index].signal
        item["password"] = key
        item["encryption"] = encryption
        item["txpwr"] = wifiNet.networks[index].txpwr
        item["bsd"] = wifiNet.networks[index].bsd
        item["txbf"] = wifiNet.networks[index].txbf
        item["ax"] = wifiNet.networks[index].ax
        infoDict[wifiNet.device] = item
    end
    if infoDict[WIFI2G] then
        infoDict[WIFI2G]["iftype"] = 1--2.4G wifi
        table.insert(infoList, infoDict[WIFI2G])
    end
    if infoDict[WIFI5G] then
        infoDict[WIFI5G]["iftype"] = 2--5G wifi
        table.insert(infoList, infoDict[WIFI5G])
    end
    local guestwifi = getGuestWifi(1)
    if guestwifi and XQFunction.getNetModeType() == 0 then
        guestwifi["iftype"] = 3--guest wifi
        table.insert(infoList, guestwifi)
    end
    return infoList
end

function getWifiTxpwr(wifiIndex)
    local network = LuciNetwork.init()
    local wifiNet = network:get_wifinet(_wifiNameForIndex(wifiIndex))
    if wifiNet then
        return tostring(wifiNet:txpwr())
    else
        return nil
    end
end

function getWifiChannel(wifiIndex)
    local network = LuciNetwork.init()
    local wifiNet = network:get_wifinet(_wifiNameForIndex(wifiIndex))
    if wifiNet then
        return tostring(wifiNet:channel())
    else
        return nil
    end
end

function getWifiTxpwrList()
    local txpwrList = {}
    local network = LuciNetwork.init()
    local wifiNet1 = network:get_wifinet(_wifiNameForIndex(1))
    local wifiNet2 = network:get_wifinet(_wifiNameForIndex(2))
    if wifiNet1 then
        table.insert(txpwrList,tostring(wifiNet1:txpwr()))
    end
    if wifiNet2 then
        table.insert(txpwrList,tostring(wifiNet2:txpwr()))
    end
    return txpwrList
end

function getWifiChannelList()
    local channelList = {}
    local network = LuciNetwork.init()
    local wifiNet1 = network:get_wifinet(_wifiNameForIndex(1))
    local wifiNet2 = network:get_wifinet(_wifiNameForIndex(2))
    if wifiNet1 then
        table.insert(channelList,tostring(wifiNet1:channel()))
    end
    if wifiNet2 then
        table.insert(channelList,tostring(wifiNet2:channel()))
    end
    return channelList
end

function getWifiChannelTxpwrList()
    local result = {}
    local network = LuciNetwork.init()
    local wifiNet1 = network:get_wifinet(_wifiNameForIndex(1))
    local wifiNet2 = network:get_wifinet(_wifiNameForIndex(2))
    if wifiNet1 then
        table.insert(result,{
            channel = tostring(wifiNet1:channel()),
            txpwr = tostring(wifiNet1:txpwr())
        })
    else
        table.insert(result,{})
    end
    if wifiNet2 then
        table.insert(result,{
            channel = tostring(wifiNet2:channel()),
            txpwr = tostring(wifiNet2:txpwr())
        })
    else
        table.insert(result,{})
    end
    return result
end

function setWifiChannelTxpwr(channel1,txpwr1,channel2,txpwr2)
    local network = LuciNetwork.init()
    local wifiDev1 = network:get_wifidev(LuciUtil.split(_wifiNameForIndex(1),".")[1])
    local wifiDev2 = network:get_wifidev(LuciUtil.split(_wifiNameForIndex(2),".")[1])
    if wifiDev1 then
        if tonumber(channel1) then
            wifiDev1:set("channel",channel1)
        end
        if not XQFunction.isStrNil(txpwr1) then
            wifiDev1:set("txpwr",txpwr1);
        end
    end
    if wifiDev2 then
        if tonumber(channel2) then
            wifiDev2:set("channel",channel2)
        end
        if not XQFunction.isStrNil(txpwr2) then
            wifiDev2:set("txpwr",txpwr2);
        end
    end
    network:commit("wireless")
    network:save("wireless")
    return true
end

function setWifiTxpwr(txpwr)
    local network = LuciNetwork.init()
    local wifiDev1 = network:get_wifidev(LuciUtil.split(_wifiNameForIndex(1),".")[1])
    local wifiDev2 = network:get_wifidev(LuciUtil.split(_wifiNameForIndex(2),".")[1])
    if wifiDev1 then
        if not XQFunction.isStrNil(txpwr) then
            wifiDev1:set("txpwr",txpwr);
        end
    end
    if wifiDev2 then
        if not XQFunction.isStrNil(txpwr) then
            wifiDev2:set("txpwr",txpwr);
        end
    end
    network:commit("wireless")
    network:save("wireless")
    return true
end

function setWifiTxbf(txbf)
    local network = LuciNetwork.init()
    local wifiDev1 = network:get_wifidev(LuciUtil.split(_wifiNameForIndex(1),".")[1])
    local wifiDev2 = network:get_wifidev(LuciUtil.split(_wifiNameForIndex(2),".")[1])
    if wifiDev1 then
        if not XQFunction.isStrNil(txbf) then
            wifiDev1:set("txbf",txbf);
        end
    end
    if wifiDev2 then
        if not XQFunction.isStrNil(txbf) then
            wifiDev2:set("txbf",txbf);
        end
    end
    network:commit("wireless")
    network:save("wireless")
    return true
end

function setWifiAx(ax)
    local network = LuciNetwork.init()
    local wifiDev1 = network:get_wifidev(LuciUtil.split(_wifiNameForIndex(1),".")[1])
    local wifiDev2 = network:get_wifidev(LuciUtil.split(_wifiNameForIndex(2),".")[1])
    if wifiDev1 then
        if not XQFunction.isStrNil(ax) then
            wifiDev1:set("ax",ax);
        end
    end
    if wifiDev2 then
        if not XQFunction.isStrNil(ax) then
            wifiDev2:set("ax",ax);
        end
    end
    network:commit("wireless")
    network:save("wireless")
    return true
end

function checkWifiPasswd(passwd,encryption)
    if XQFunction.isStrNil(encryption) or (encryption and encryption ~= "none" and XQFunction.isStrNil(passwd)) then
        return 1502
    end
    if XQFunction.checkChineseChar(passwd) then
        return 1523
    end
    if encryption == "psk" or encryption == "psk2" then
        if  passwd:len() < 8 then
            return 1520
        end
    elseif encryption == "mixed-psk" then
        if  passwd:len()<8 or passwd:len()>63 then
            return 1521
        end
    elseif encryption == "wep-open" then
        if  passwd:len()~=5 and passwd:len()~=13 then
            return 1522
        end
    end
    return 0
end

function checkSSID(ssid,length)
    if XQFunction.isStrNil(ssid) then
        return 0
    end
    if string.len(ssid) > tonumber(length) then
        return 1572
    end
    if not XQFunction.checkSSID(ssid) then
        return 1573
    end
    return 0
end

function getWifiBasicInfo(wifiIndex)
    local network = LuciNetwork.init()
    local wifiNet = network:get_wifinet(_wifiNameForIndex(wifiIndex))
    local wifiDev = network:get_wifidev(LuciUtil.split(_wifiNameForIndex(wifiIndex),".")[1])
    if wifiNet and wifiDev then
        local options = {
            ["wifiIndex"]   = wifiIndex,
            ["channel"]     = wifiDev:get("channel") or 0,
            ["bandwidth"]   = wifiDev:get("bw") or 0,
            ["txpwr"]       = wifiDev:get("txpwr") or "mid",
            ["on"]          = wifiNet:get("disabled") or 0,
            ["ssid"]        = wifiNet:get("ssid"),
            ["encryption"]  = wifiNet:get("encryption"),
            ["password"]    = wifiNet:get("key"),
            ["hidden"]      = wifiNet:get("hidden") or 0,
            ["bsd"]         = wifiNet:get("bsd") or 0,
            ["txbf"]        = wifiDev:get("txbf") or 0,
            ["ax"]        = wifiNet:get("ax") or 0
        }
        if options.encryption == "ccmp" then
            options.password = wifiNet:get("sae_password")
        end
        return options
    end
    return nil
end

function backupWifiInfo(wifiIndex)
    local uci = require("luci.model.uci").cursor()
    local options = getWifiBasicInfo(wifiIndex)
    if options then
        uci:section("backup", "backup", "wifi"..tostring(wifiIndex), options)
        uci:commit("backup")
    end
end

function setWifiBasicInfo(wifiIndex, ssid, password, encryption, channel, txpwr, hidden, on, bandwidth, bsd, txbf, weakenable, weakthreshold, kickthreshold, ax)
    local network = LuciNetwork.init()
    local wifiNet = network:get_wifinet(_wifiNameForIndex(wifiIndex))
    local wifiDev = network:get_wifidev(LuciUtil.split(_wifiNameForIndex(wifiIndex),".")[1])
    local uci = require("luci.model.uci").cursor()
    if wifiNet == nil then
        return false
    end
    if wifiDev then
        if not XQFunction.isStrNil(channel) then
            wifiDev:set("channel",channel)
            if channel == "0" then
                wifiDev:set("autoch","2")
            else
                wifiDev:set("autoch","0")
            end
        end
        if not XQFunction.isStrNil(bandwidth) then
            wifiDev:set("bw",bandwidth)
        end
        if not XQFunction.isStrNil(txpwr) then
            wifiDev:set("txpwr",txpwr)
        end
        --[[ 
        if wifiIndex == 1 then
            local guestwifi = getGuestWifi(1)
            if guestwifi and tonumber(on) and tonumber(on) == 0 and XQFunction.getNetModeType() ~= 2 then
                setGuestWifi(1, nil, nil, nil, on, nil)
            end
        end
        if on == 1 then
            wifiDev:set("disabled", "0")
        elseif on == 0 then
            --wifiDev:set("disabled", "1")
        end
        ]]
        --logger.log(6, on)
        if on == 1 then
            wifiDev:set("disabled", "0")
        end
        if not XQFunction.isStrNil(txbf) then
            if tonumber(txbf) == 3 then
                wifiDev:set("txbf", "3")
            elseif tonumber(txbf) == 0 then
                wifiDev:set("txbf", "0")
            end
        end
        if not XQFunction.isStrNil(ax) then
            if tonumber(ax) == 0 then
                wifiDev:set("ax", "0")
            else
                wifiDev:set("ax", "1")
            end
        end
    end
    --wifiNet:get("disabled", nil)
    -- just set wifi net, do not set wifidev
    --local name = wifiNet:get("ifname")
    --logger.log(6, "===== set wifiNet ifname= "..name)    
    if on == 1 then
        wifiNet:set("disabled", "0")
    elseif on == 0 then
        wifiNet:set("disabled", "1")
    end

    if bsd then
        wifiNet:set("bsd", tostring(bsd))
        uci:set("lbd", "config", "Enable", tostring(bsd))
        wifiNet:set("rrm", tostring(bsd))
        wifiNet:set("wnm", tostring(bsd))
        uci:commit("lbd")
    end
    if not XQFunction.isStrNil(weakenable) then
        wifiNet:set("weakenable",weakenable)
    end
    if not XQFunction.isStrNil(weakthreshold) then
        wifiNet:set("weakthreshold",weakthreshold)
    end
    if not XQFunction.isStrNil(kickthreshold) then
        wifiNet:set("kickthreshold",kickthreshold)
    end
    if not XQFunction.isStrNil(ssid) and XQFunction.checkSSID(ssid) then
        local XQSync = require("xiaoqiang.util.XQSynchrodata")
        if wifiIndex == 1 then
            XQSync.syncWiFiSSID(ssid, nil)
            local sysutil = require("xiaoqiang.util.XQSysUtil")
            sysutil.doConfUpload({
                ["ssid_24G"] = ssid,
                ["wifi_24G_password"] = password
            })
        elseif wifiIndex == 2 then
            XQSync.syncWiFiSSID(nil, ssid)
        end
        wifiNet:set("ssid",ssid)
    end
    if encryption then
        local code = checkWifiPasswd(password, encryption)
        if code == 0 then
            wifiNet:set("encryption", encryption)
            wifiNet:set("key", password)
            if encryption == "none" then
                wifiNet:set("key","")
                wifiNet:set("sae", "")
                wifiNet:set("sae_password", "")
                wifiNet:set("ieee80211w", "")
            elseif encryption == "wep-open" then
                wifiNet:set("key1", "s:"..password)
                wifiNet:set("key", 1)
                wifiNet:set("sae", "")
                wifiNet:set("sae_password", "")
                wifiNet:set("ieee80211w", "")
            elseif encryption == "ccmp" then
                wifiNet:set("sae", "1")
                wifiNet:set("key", "")
                wifiNet:set("sae_password", password)
                wifiNet:set("ieee80211w", "2")
            elseif encryption == "psk2+ccmp" then
                wifiNet:set("sae", "1")
                wifiNet:set("key", password)
                wifiNet:set("sae_password", password)
                wifiNet:set("ieee80211w", "1")
            elseif encryption == "psk2" or encryption == "mixed-psk" then
                wifiNet:set("sae", "")
                wifiNet:set("sae_password", "")
                wifiNet:set("ieee80211w", "")
            end
            if wifiIndex == 1 then
                XQFunction.nvramSet("nv_wifi_ssid", ssid)
                XQFunction.nvramSet("nv_wifi_enc", encryption)
                XQFunction.nvramSet("nv_wifi_pwd", password)
                XQFunction.nvramCommit()
            else
                XQFunction.nvramSet("nv_wifi_ssid1", ssid)
                XQFunction.nvramSet("nv_wifi_enc1", encryption)
                XQFunction.nvramSet("nv_wifi_pwd1", password)
                XQFunction.nvramCommit()
            end
        elseif code > 1502 then
            return false
        end
    end
    if hidden == "1" then
        wifiNet:set("hidden","1")
    end
    if hidden == "0" then
        wifiNet:set("hidden","0")
    end
    network:save("wireless")
    network:commit("wireless")
    return true
end

function setWifiRegion(country, region, regionABand)
    if XQFunction.isStrNil(country) or not tonumber(region) or not tonumber(regionABand) then
        return false
    end
    local network = LuciNetwork.init()
    local wifiDev1 = network:get_wifidev(LuciUtil.split(_wifiNameForIndex(1),".")[1])
    local wifiDev2 = network:get_wifidev(LuciUtil.split(_wifiNameForIndex(2),".")[1])
    if wifiDev1 then
        wifiDev1:set("country",country)
        wifiDev1:set("region",region)
        wifiDev1:set("aregion",regionABand)
        wifiDev1:set("channel","0")
        wifiDev1:set("bw","0")
        wifiDev1:set("autoch","2")
    end
    if wifiDev2 then
        wifiDev2:set("country",country)
        wifiDev2:set("region",region)
        wifiDev2:set("aregion",regionABand)
        wifiDev2:set("channel","0")
        wifiDev2:set("bw","0")
        wifiDev2:set("autoch","2")
    end
    network:commit("wireless")
    network:save("wireless")
    return true
end

--
-- @return 
-- bsd:0/1 不融合/融合
-- mode:0/1/2 漫游/2.4G/5G
-- 
function getBsdInfo(mac)
    if XQFunction.isStrNil(mac) then
        return nil
    end
    local info = {
        ["bsd"] = 0,
        ["mode"] = 0
    }
    local network = LuciNetwork.init()
    local wifiNet = network:get_wifinet(_wifiNameForIndex(1))
    local bsd = tonumber(wifiNet:get("bsd") or 0)
    local bsd_m_enable = tonumber(wifiNet:get("bsd_maclist_mode") or 0)
    if bsd == 1 then
        info.bsd = 1
        if bsd_m_enable == 0 then
            info.mode = 0
        else
            local mlist2g = wifiNet:get("bsd_2g")
            local mlist5g = wifiNet:get("bsd_5g")
            if mlist2g and type(mlist2g) == "table" then
                for _, m in ipairs(mlist2g) do
                    if string.lower(mac) == string.lower(m) then
                        info.mode = 1
                        break
                    end
                end
            end
            if mlist5g and type(mlist5g) == "table" then
                for _, m in ipairs(mlist5g) do
                    if string.lower(mac) == string.lower(m) then
                        info.mode = 2
                        break
                    end
                end
            end
        end
    end
    return info
end

-- mode:0/1/2 漫游/2.4G/5G
function setBsdMaclist(mac, mode)
    if XQFunction.isStrNil(mac) or not mode then
        return nil
    end
    local info = {
        ["bsd"] = 0,
        ["mode"] = 0
    }
    local network = LuciNetwork.init()
    local wifiNet = network:get_wifinet(_wifiNameForIndex(1))
    local wifiNet5g = network:get_wifinet(_wifiNameForIndex(2))
    local bsd = tonumber(wifiNet:get("bsd") or 0)
    local bsd_m_enable = tonumber(wifiNet:get("bsd_maclist_mode") or 0)
    if bsd == 1 then
        info.bsd = 1
        info.mode = mode
        if wifiNet then
            wifiNet:set("bsd_maclist_mode", "1")
        end
        if wifiNet5g then
            wifiNet5g:set("bsd_maclist_mode", "1")
        end
        local mlist2g = wifiNet:get("bsd_2g")
        local mlist5g = wifiNet:get("bsd_5g")
        local index1
        local index2
        if mlist2g and type(mlist2g) == "table" then
            for i, m in ipairs(mlist2g) do
                if string.lower(mac) == string.lower(m) then
                    index1 = i
                    break
                end
            end
        else
            mlist2g = {}
        end
        if mlist5g and type(mlist5g) == "table" then
            for i, m in ipairs(mlist5g) do
                if string.lower(mac) == string.lower(m) then
                    index2 = i
                    break
                end
            end
        else
            mlist5g = {}
        end
        if mode == 0 then
            if index1 then
                table.remove(mlist2g, index1)
            end
            if index2 then
                table.remove(mlist5g, index2)
            end
        elseif mode == 1 then
            if not index1 then
                table.insert(mlist2g, mac)
            end
            if index2 then
                table.remove(mlist5g, index2)
            end
        elseif mode == 2 then
            if index1 then
                table.remove(mlist2g, index1)
            end
            if not index2 then
                table.insert(mlist5g, mac)
            end
        end
        if mlist2g and #mlist2g > 0 then
            wifiNet:set_list("bsd_2g", mlist2g)
            if wifiNet5g then
                wifiNet5g:set_list("bsd_2g", mlist2g)
            end
        else
            wifiNet:set_list("bsd_2g", nil)
            if wifiNet5g then
                wifiNet5g:set_list("bsd_2g", nil)
            end
        end
        if mlist5g and #mlist5g > 0 then
            wifiNet:set_list("bsd_5g", mlist5g)
            if wifiNet5g then
                wifiNet5g:set_list("bsd_5g", mlist5g)
            end
        else
            wifiNet:set_list("bsd_5g", nil)
            if wifiNet5g then
                wifiNet5g:set_list("bsd_5g", nil)
            end
        end
        network:commit("wireless")
    end
    return info
end

--[[
Turn on wifi
@param wifiIndex: 1 (2.4G)/ 2 (5G)
@return boolean
]]--
function turnWifiOn(wifiIndex)
    local wifiStatus = getWifiStatus(wifiIndex)
    if wifiStatus['up'] == 1 then
        return true
    end
    local network = LuciNetwork.init()
    local wifiNet = network:get_wifinet(_wifiNameForIndex(wifiIndex))
    local dev
    if wifiNet ~= nil then
        dev = wifiNet:get_device()
    end
    if dev and wifiNet then
        -- if wifiIndex == 1 then
        --     local guestwifi = getGuestWifi(1)
        --     if guestwifi and XQFunction.getNetModeType() ~= 2 then
        --         setGuestWifi(1, nil, nil, nil, 1, nil)
        --     end
        -- end
        dev:set("disabled", "0")
        wifiNet:set("disabled", nil)
        network:commit("wireless")
        XQFunction.forkRestartWifi()
        return true
    end
    return false
end

--[[
Turn off wifi
@param wifiIndex: 1 (2.4G)/ 2 (5G)
@return boolean
]]--
function turnWifiOff(wifiIndex)
    local wifiStatus = getWifiStatus(wifiIndex)
    if wifiStatus['up'] == 0 then
        return true
    end

    local network = LuciNetwork.init()
    local wifiNet = network:get_wifinet(_wifiNameForIndex(wifiIndex))
    local dev
    if wifiNet ~= nil then
        dev = wifiNet:get_device()
    end
    if dev and wifiNet then
        -- if wifiIndex == 1 then
        --     local guestwifi = getGuestWifi(1)
        --     if guestwifi and XQFunction.getNetModeType() ~= 2 then
        --         setGuestWifi(1, nil, nil, nil, 0, nil)
        --     end
        -- end
        dev:set("disabled", "1")
        wifiNet:set("disabled", nil)
        network:commit("wireless")
        XQFunction.forkRestartWifi()
        return true
    end
    return false
end

--[[
@return 0:close 1:start 2:connect 3:error 4:timeout
]]
function getWifiWpsStatus()
    local LuciUtil = require("luci.util")
    local status = LuciUtil.exec(XQConfigs.GET_WPS_STATUS)
    if not XQFunction.isStrNil(status) then
        status = LuciUtil.trim(status)
        return tonumber(status)
    end
    return 0
end

function getWpsConDevMac()
    local LuciUtil = require("luci.util")
    local mac = LuciUtil.exec(XQConfigs.GET_WPS_CONMAC)
    if mac then
        return XQFunction.macFormat(LuciUtil.trim(mac))
    end
    return nil
end

function stopWps()
    local LuciUtil = require("luci.util")
    LuciUtil.exec(XQConfigs.CLOSE_WPS)
    return
end

function openWifiWps()
    local LuciUtil = require("luci.util")
    local XQPreference = require("xiaoqiang.XQPreference")
    LuciUtil.exec(XQConfigs.OPEN_WPS)
    local timestamp = tostring(os.time())
    XQPreference.set(XQConfigs.PREF_WPS_TIMESTAMP,timestamp)
    return timestamp
end

function miwifiutil_rssi_to_signal(rssi)
    rssi = tonumber(rssi)
    if rssi >= 0 then
        return math.ceil(0)
    end
    if rssi >= -50 and rssi < 0 then
        rssi = 100
    elseif rssi >= -80 then
        rssi = 24 + ((rssi + 80) * 26)/10;
    elseif rssi >= -90 then
        rssi = ((rssi + 90) * 26)/10;
    else
        rssi = 0
    end
    return math.ceil(rssi)
end

--for R3/R3P/R1C/r1800//R1D/R2D/R4C/R3600/R2100/R2600/R2200
function apcli_set_scan(scan_item)
    local ifname = scan_item['scan_ifname']
    local ssid = scan_item['ssid']

    if HARDWARE:match("^rm1800$") or HARDWARE:match("^r3600") or HARDWARE:match("^r2200$") then
        local scancmd = "iwlist "..ifname.." scanning"
        return scancmd
    elseif HARDWARE:match("^r1d") or HARDWARE:match("^r2d") then
    else
        local scancmd = "iwpriv "..ifname.." set SiteSurvey=\""..ssid.."\";sleep 1;"
        os.execute(scancmd)
        return scancmd
    end
end

--for R3/R3P/R1C/rm1800/R1D/R2D/R4C/R3600/R2100/R2600/R2200
function apcli_get_connect(ifname)
    local connection
    if HARDWARE:match("^rm1800$") or HARDWARE:match("^r3600") or HARDWARE:match("^r2200") then
        connection = LuciUtil.exec("wpa_cli -i "..ifname.." -p /var/run/wpa_supplicant-"..ifname.." status | grep ^wpa_state= | cut -f2- -d=")
        if connection:match("COMPLETED") then
            return true, connection
        else
            return false, connection
        end
    elseif HARDWARE:match("^r1d") or HARDWARE:match("^r2d") then
    else
        connection = LuciUtil.exec("iwpriv "..ifname.." Connstatus")
        if connection:match("SSID:") then
            return true, connection
        else
            return false, connection
        end
    end
end

--暂时关闭apcli
function apcli_set_inactive(ifname)
    if HARDWARE:match("^r1800") or HARDWARE:match("^r4c$") or HARDWARE:match("^r3600") or HARDWARE:match("^r2200") then
        os.execute("killall -9 wpa_supplicant")
        --os.execute("rm -rf /var/run/wpa_supplicantglobal")
        --os.execute("rm -rf /var/run/wpa_supplicant-global.pid")
        --os.execute("rm -rf /var/run/wpa_supplicant-"..ifname.."")
        --os.execute("rm -rf /var/run/wpa_supplicant-"..ifname..".pid")
        --os.execute("rm -rf /var/run/wpa_supplicant-"..ifname..".lock")
        --os.execute("rm -rf /var/run/wpa_supplicant-"..ifname..".conf")
        os.execute("ifconfig "..ifname.." down")
        if HARDWARE:match("^r3600") then
            os.execute("wlanconfig "..ifname.." destroy -cfg80211")
            os.execute("iw dev "..ifname.." del")
        else
            os.execute("wlanconfig "..ifname.." destroy")
        end
        local dev = apcli_get_device(ifname)
        os.execute("ifconfig "..dev:name().." down up")
    elseif HARDWARE:match("^r1d") or HARDWARE:match("^r2d") then
        os.execute("wl -i "..ifname.." bss down")
    else
        os.execute("iwpriv "..ifname.." set ApCliEnable=0")
        os.execute("iwpriv "..ifname.." set ApCliAutoConnect=0")
        os.execute("ifconfig "..ifname.." down")
    end
end

--for R3/R3P/R1C/r1800/R1D/R2D/R4C/R3600/R2100/R2600/R2200
function apcli_set_connect(apcliitem, extend)
    local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
    local XQSecureUtil  = require("xiaoqiang.util.XQSecureUtil")
    local cmdssid       = apcliitem.cmdssid
    local ifname        = apcliitem.ifname
    local cmdencryption = XQSecureUtil.parseCmdline(apcliitem.encryption)
    local cmdpassword   = apcliitem.cmdpassword
    local cmdenctype    = XQSecureUtil.parseCmdline(apcliitem.enctype)
    local extendwifi    = tonumber(extend) or 0
    local ssid_base64   = XQCryptoUtil.binaryBase64Enc(apcliitem.cmdssid)
    local password_base64   = XQCryptoUtil.binaryBase64Enc(apcliitem.cmdpassword)
    if HARDWARE:match("^rm1800") or HARDWARE:match("^r3600") or HARDWARE:match("^r2200") then
        local cmd = string.format("/usr/sbin/check_apcli_connected \"%s\" \"%s\" \"%s\" \"%s\" \"%s\"",
                ssid_base64, ifname, cmdenctype, cmdencryption, password_base64)
        local is_connected = LuciUtil.trim(LuciUtil.exec(cmd))
        if tonumber(is_connected) == 1 then
            return
        end

        local band = apcliitem.band
        local dev = apcli_get_device(ifname)
        local device = dev:name()
        --[[if band:match("2g") then
            device = "wifi1"
        else
            device = "wifi0"
        end
        if HARDWARE:match("^r4c$") then
            device = "wifi0"
        end
        --]]
        --logger.log(4, string.format("ifname=%s, device=%s", tostring(ifname), tostring(device)))
        apcli_set_inactive(ifname)
        os.execute("sleep 1")
        if HARDWARE:match("^r3600") then
            os.execute("wlanconfig "..ifname.." create wlandev "..device.." wlanmode sta -cfg80211")
            os.execute("iw dev "..device.." interface add "..ifname.." type __ap")
        else
            os.execute("wlanconfig "..ifname.." create wlandev "..device.." wlanmode sta nosbeacon")
        end
        os.execute("iwpriv "..ifname.." extap 1")
        os.execute("iwpriv "..ifname.." athnewind 0")

        os.execute("killall -9 wpa_supplicant")
        local file = io.open("/var/run/wpa_supplicant-"..ifname..".conf", "w+")
        file:write(string.format("ctrl_interface=/var/run/wpa_supplicant-%s\n", ifname))
        file:write(string.format("network={\n"))
        file:write(string.format("        scan_ssid=1\n"))
        file:write(string.format("        ssid=\"%s\"\n", cmdssid))
        if apcliitem.enctype:match("AES") then
            file:write(string.format("        key_mgmt=WPA-PSK\n"))
            if cmdencryption:match("WPA2PSK") then
                file:write(string.format("        proto=RSN\n"))
            else
                file:write(string.format("        proto=WPA\n"))
            end
            file:write(string.format("        psk=\"%s\"\n", cmdpassword))
            file:write(string.format("        pairwise=CCMP\n"))
            file:write(string.format("        group=CCMP TKIP\n"))
        elseif apcliitem.enctype:match("TKIP") then
            file:write(string.format("        key_mgmt=WPA-PSK\n"))
            if cmdencryption:match("WPA2PSK") then
                file:write(string.format("        proto=RSN\n"))
            else
                file:write(string.format("        proto=WPA\n"))
            end
            file:write(string.format("        psk=\"%s\"\n", cmdpassword))
            file:write(string.format("        pairwise=TKIP\n"))
            file:write(string.format("        group=CCMP TKIP\n"))
        elseif apcliitem.enctype:match("WEP") then
            file:write(string.format("        key_mgmt=NONE\n"))
            file:write(string.format("        wep_key0=\"%s\"\n", cmdpassword))
            file:write(string.format("        wep_tx_keyidx=0\n"))
            file:write(string.format("        auth_alg=OPEN\n"))
        elseif apcliitem.enctype:match("NONE") then
            file:write(string.format("        key_mgmt=NONE\n"))
        end
        file:write(string.format("}\n"))
        file:flush()
        file:close()
        os.execute("wpa_supplicant -i "..ifname.." -Dathr -c /var/run/wpa_supplicant-"..ifname..".conf -b br-lan -B")
        if extendwifi == 0 then
            os.execute("brctl addif br-lan "..ifname)
        end
        os.execute("ifconfig "..ifname.." up")
    elseif HARDWARE:match("^r1d") or HARDWARE:match("^r2d") then
    else
-- 设置信道反而更加难连接
--    if not XQFunction.isStrNil(apcliitem.channel) then
--       os.execute("iwpriv "..ifname.." set Channel="..apcliitem.channel)
--       os.execute("sleep 1")
--    end
        os.execute("ifconfig "..ifname.." up")
        os.execute("sleep 2")
        os.execute("iwpriv "..ifname.." set ApCliEnable=0")

        if apcliitem.enctype:match("AES") then
            os.execute("iwpriv "..ifname.." set ApCliAuthMode=\""..cmdencryption.."\"")
            os.execute("iwpriv "..ifname.." set ApCliEncrypType=AES")
            os.execute("iwpriv "..ifname.." set bs64_ApCliSsid=\""..ssid_base64.."\"")
            os.execute("iwpriv "..ifname.." set bs64_ApCliWPAPSK=\""..password_base64.."\"")
        elseif apcliitem.enctype:match("TKIP") then
            os.execute("iwpriv "..ifname.." set ApCliAuthMode=\""..cmdencryption.."\"")
            os.execute("iwpriv "..ifname.." set ApCliEncrypType=TKIP")
            os.execute("iwpriv "..ifname.." set bs64_ApCliSsid=\""..ssid_base64.."\"")
            os.execute("iwpriv "..ifname.." set bs64_ApCliWPAPSK=\""..password_base64.."\"")
        elseif apcliitem.enctype:match("WEP") then
            os.execute("iwpriv "..ifname.." set ApCliAuthMode=OPEN")
            os.execute("iwpriv "..ifname.." set ApCliEncrypType=WEP")
            os.execute("iwpriv "..ifname.." set ApCliDefaultKeyID=1")
            os.execute("iwpriv "..ifname.." set bs64_ApCliKey1=\""..password_base64.."\"")
            os.execute("iwpriv "..ifname.." set bs64_ApCliSsid=\""..ssid_base64.."\"")
        elseif apcliitem.enctype:match("NONE") then
            os.execute("iwpriv "..ifname.." set ApCliAuthMode=OPEN")
            os.execute("iwpriv "..ifname.." set ApCliEncrypType=NONE")
            os.execute("iwpriv "..ifname.." set bs64_ApCliSsid=\""..ssid_base64.."\"")
        end
        os.execute("iwpriv "..ifname.." set ApCliEnable=1")
        os.execute("iwpriv "..ifname.." set ApCliAutoConnect=1")
    end
end

function apcli_check_apcliitem(apcliitem)

return XQFunction.isStrNil(apcliitem.enctype) or XQFunction.isStrNil(apcliitem.encryption) or XQFunction.isStrNil(apcliitem.band) or XQFunction.isStrNil(apcliitem.channel)

end

--wifi-iface
function apcli_get_wifinet(ifname)
    local network = LuciNetwork.init()
    local dev
    local wifinet
    for _, dev in ipairs(network:get_wifidevs()) do
        for _, wifinet in ipairs(dev:get_wifinets()) do
            if wifinet and wifinet:ifname() == ifname then
                wifinet['dev'] = dev
                return wifinet
            end
        end
    end

    return nil
end

function apcli_get_ifname_form_band(band)
    local uci = require("luci.model.uci").cursor()
    return uci:get("misc",  "wireless", "apclient_"..string.upper(band))
end

function apcli_get_device(ifname)
    local device
    local uci = require("luci.model.uci").cursor()
    local network = LuciNetwork.init()
    local wifinet = apcli_get_wifinet(ifname)
    if not XQFunction.isStrNil(wifinet) then
         device = wifinet:get("device") or ""
    end
    if XQFunction.isStrNil(device) then
        device = uci:get("misc",  "wireless", ifname.."_device")
    end
    return network:get_wifidev(device)
end

function apcli_get_scanifname(ifname)
    local uci = require("luci.model.uci").cursor()
    local wifinet = apcli_get_wifinet(ifname)
    if not XQFunction.isStrNil(wifinet) then
         local scanifname = wifinet:get("scanifname") or ""
         if not XQFunction.isStrNil(scanifname) then
              return scanifname
         end
    end
    return uci:get("misc",  "wireless", ifname.."_scanifname")
end

function apcli_get_scanband(ifname)
    local uci = require("luci.model.uci").cursor()
    local wifinet = apcli_get_wifinet(ifname)
    if not XQFunction.isStrNil(wifinet) then
         local scanband = wifinet:get("scanband") or ""
         if not XQFunction.isStrNil(scanband) then
              return scanband
         end
    end
    return uci:get("misc",  "wireless", ifname.."_scanband")
end

function apcli_get_apclimode(ifname)
    local uci = require("luci.model.uci").cursor()
    return uci:get("misc",  "wireless", ifname.."_mode")
end

function apcli_get_ifnames()
    local uci = require("luci.model.uci").cursor()
    return uci:get_list("misc", "wireless", "APCLI_IFNAMES") or {}
end

function apcli_disable(ifname)
    local LuciNetwork = require("luci.model.network").init()
    apcli_set_inactive(ifname)
    local wifinet = apcli_get_wifinet(ifname)
    wifinet:set("disabled","1")

    LuciNetwork:save("wireless")
    LuciNetwork:commit("wireless")
end

--当前只开启一个band 的apcli
function apcli_enable(apcli_item)
    local ifname = apcli_item.ifname
    local ssid = apcli_item.ssid
    local encryption = apcli_item.encryption
    local enctype = apcli_item.enctype
    local key = apcli_item.password
    local uci = require("luci.model.uci").cursor()
    local LuciNetwork = require("luci.model.network").init()
    local XQSynchrodata = require("xiaoqiang.util.XQSynchrodata")
    local wifinet
    local ifname_other
    local wifinet_other
    local qca_encryption

    wifinet = apcli_get_wifinet(ifname)

    if HARDWARE:match("^rm1800") or HARDWARE:match("^r3600") then
        if encryption:match("WPA2PSK") then
            qca_encryption = "psk2"
        elseif encryption:match("NONE") then
            qca_encryption = "none"
        else
            qca_encryption = "mixed-psk"
        end
    end

--new
    if XQFunction.isStrNil(wifinet) then
        local dev = apcli_get_device(ifname)
        local iface = {
            device = dev:name(),
            ifname = ifname,
            scanifname = apcli_get_scanifname(ifname),
            apcliband = apcli_get_scanband(ifname),
            network = "lan",
            mode = "sta",
            ssid = ssid,
            key = key,
            encryption = encryption,
            enctype = enctype,
            disabled = "0"
        }
        if HARDWARE:match("^r1800") or HARDWARE:match("^r4c$") or HARDWARE:match("^r3600") or HARDWARE:match("^r2200$") then
            iface["extap"] = "1"
            iface["athnewind"] = "0"
            iface["encryption"] = qca_encryption
        end
        dev:add_wifinet(iface)
        uci:commit("xiaoqiang")
    else
        wifinet:set("ssid", ssid)
        wifinet:set("key", key)
        wifinet:set("enctype", enctype)
        if HARDWARE:match("^rm1800") or HARDWARE:match("^r3600") or HARDWARE:match("^r2200$") then
            wifinet:set("extap","1")
            wifinet:set("athnewind","0")
            wifinet:set("encryption", qca_encryption)
        else
            wifinet:set("encryption", encryption)
        end
        wifinet:set("disabled","0")
    end

--防止环路
    local ifnames = apcli_get_ifnames()
    for _,ifname_other in pairs(ifnames) do
        if ifname_other ~= ifname then
            os.execute("ifconfig "..ifname_other.." down")
            wifinet_other = apcli_get_wifinet(ifname_other)
--要不要这个??
            if wifinet_other ~= nil then
                wifinet_other:set("disabled", "1")
            end
        end
    end

    os.execute("ifconfig "..ifname.." up")

    apcli_set_active(ifname)

    -- Save and commit
    LuciNetwork:save("wireless")
    LuciNetwork:commit("wireless")
end

function apcli_get_active()
    local uci = require("luci.model.uci").cursor()
    local active_apcli = uci:get("xiaoqiang", "common", "active_apcli")

    if XQFunction.isStrNil(active_apcli) then
        active_apcli = nil
    end
    return active_apcli
end

function apcli_set_active(ifname)
    local XQSynchrodata = require("xiaoqiang.util.XQSynchrodata")
    local uci = require("luci.model.uci").cursor()
    local mode

    if ifname then
        mode = tonumber(apcli_get_apclimode(ifname))
        if HARDWARE:match("^r3600") then
            uci:set("xiaoqiang", "common", "active_apcli", ifname)
        end
    else
        mode = 0
        uci:delete("xiaoqiang", "common", "active_apcli")
    end
    uci:commit("xiaoqiang")
    XQSynchrodata.syncActiveApcliMode(mode)
end

-- 0/1/2 unknown/2.4G/5G
function apcli_get_active_type()
    local recovery = XQFunction.miscRecovery()
    if recovery == 1 then
        return 0
    end
    local activeApcli = 0
    local apcli = apcli_get_active()

    if XQFunction.isStrNil(apcli) then
        return 0
    end

    activeApcli = tonumber(apcli_get_apclimode(apcli))
    return activeApcli
end

function rssi_cmp(a, b)
    if a['band'] == b['band'] then
        return tonumber(a['rssi']) > tonumber(b['rssi'])
    elseif a['band'] == "5g" then
        return true
    else
        return false
    end
end

-- return scanlist:
function apcli_get_scanlist(apcliitem)
    local result = {}
    local scan = ""
    local found = 0
    local scan_ifname
    local scan_band
    local scan_item
    local scan_dev_list = {}
    local ifname
    local app_ssid = apcliitem["ssid"]
    local app_band = apcliitem["band"]

    if XQFunction.isStrNil(app_ssid) then
        app_ssid = ""
    end
    if XQFunction.isStrNil(app_band) then
        app_band = ""
    end

    for i, ifname in ipairs(apcli_get_ifnames()) do
        if not XQFunction.isStrNil(ifname) then
            local dev = apcli_get_device(ifname)
            --logger.log(6, "===== ifname: " ..ifname)
            if dev:is_up() then
                scan_band = apcli_get_scanband(ifname)
                scan_ifname = apcli_get_scanifname(ifname)
                --logger.log(6, "===== scan_ifname: " ..scan_ifname)
                if not XQFunction.isStrNil(scan_ifname) and not XQFunction.isStrNil(scan_band) then
                    if XQFunction.isStrNil(app_band) or scan_band == app_band then
                         scan_item = {}
                         scan_item['scan_ifname'] = scan_ifname
                         scan_item['ifname'] = ifname
                         scan_item['band'] = scan_band
                         scan_item['ssid'] = app_ssid
                         scan = scan..apcli_set_scan(scan_item)
                         table.insert(scan_dev_list , scan_item)
                    end
                end
            end
        end
    end

    if scan == "" then
        return result
    end

    os.execute("sleep 2")
    for i, scan_item in ipairs(scan_dev_list) do
         if not XQFunction.isStrNil(scan_item) then
            local scannet = apcli_get_wifinet(scan_item['scan_ifname'])
            --add wifinet status check, jump disabled band
            --logger.log(6, "===== ifname: " ..scan_item['scan_ifname'])
            --logger.log(6, "===== disabled: " ..scannet:disabled())
            if scannet:disabled() == "1" then
                --logger.log(6, "===== break: " ..scannet:disabled())
                break
            end

            local scanresult = scannet:scanlist()
            if #scanresult > 0 then
                for j, item in ipairs(scanresult) do
--format signal:rssi -> %
                    item['rssi'] = item['signal']
                    item['signal'] = miwifiutil_rssi_to_signal(item['signal'])
--format band: for ui
                    item['band'] = scan_item['band']
                end
                for j, item in ipairs(scanresult) do
                    found = 0
                    for k, prev in ipairs(result) do
                        if not XQFunction.isStrNil(item['ssid']) and prev['ssid'] == item['ssid'] and prev['band'] == item['band'] then
                            found = 1
                            break
                        end
                    end
                    if found == 0 and  not XQFunction.isStrNil(item['ssid']) then
                        --exclude the ssid which contain Greek letter α~ω using GB2312 code because they can't be supported in IE
                        local essid = item['ssid']
                        local skip = 0
                        for k = 1, string.len(essid) - 1 do
                            local first, second = string.byte(essid, k, k + 1)
                            if first == 166 and second > 192 and second < 217 then
                                skip = 1
                                logger.log(4, string.format("filter out the SSID %s as it contains Greek letter α~ω using GB2312 code", essid))
                                break
                            end
                        end
                        if skip == 0 then
                            table.insert(result, item)
                        end
                    end
                end
            end
        end
    end

    table.sort(result, rssi_cmp)
    return result
end

--only return uninitialized xiaomi wifi
function extendwifi_get_scanlist(apcliitem)
    local result = apcli_get_scanlist(apcliitem)
    local miwifi_result = {}

    for _,item in ipairs(result) do
        if  not XQFunction.isStrNil(item['wsc_devicename']) and item['wsc_devicename'] == 'XiaoMiRouter' and item['enctype'] == 'NONE' then
            table.insert(miwifi_result, item)
        end
    end

    return miwifi_result
end
--return all xiaomi wifi
function extendwifi_get_all_scanlist(apcliitem)
    local result = apcli_get_scanlist(apcliitem)
    local miwifi_result = {}

    for _,item in ipairs(result) do
        if  not XQFunction.isStrNil(item['wsc_devicename']) and item['wsc_devicename'] == 'XiaoMiRouter' then
            table.insert(miwifi_result, item)
        end
    end

    return miwifi_result
end


local uci_org = require("luci.model.uci").cursor("/tmp/extendwifi/etc/config")
local uci_new = require("luci.model.uci").cursor()

--txbf default must be 3
EXTENDWIFI_DEVICE_OPTION = {
{"disabled", "string", "0"},
{"channel", "string", "0"},
{"bw", "string", "0"},
{"country", "string", "CN"},
{"txbf",  "string", "3"},
{"ax",  "string", "1"},
{"txpwr", "string", "max"}
}

--name, type
EXTENDWIFI_IFACE_OPTION = {
{"disabled", "string", "0"},
{"network", "string", nil},
{"ssid", "string", nil},
{"key", "string", nil},
{"encryption", "string", nil},
{"enctype", "string", nil},
{"hidden", "string", nil},
{"macfilter", "string", nil},
{"maclist", "list", nil},
{"wpsdevicename", "string", nil},
{"bsd", "string", nil},
{"wscconfigstatus", "string", nil},
{"dynbcn", "string", nil},
{"rssithreshold", "string", nil},
{"ap_isolate", "string", nil}
}

EXTENDWIFI_FILE = {
"/etc/xqDb",
"/etc/config/wifiblist",
"/etc/config/wifiwlist",
"/etc/config/devicelist"
}

function __extendwifi_getdev(devs, name)
   for _,dev in ipairs(devs) do
--        logger.log(3, "__extendwifi_getdev "..device.." ?= "..dev['.name'])
        if dev['.name'] == name then
            return dev
        end
   end
   return nil
end

function __extendwifi_getiface(ifaces, ifname)
--   logger.log(3, "__extendwifi_getiface".." get "..ifname)
   for _,iface in ipairs(ifaces) do
        if iface['ifname'] == ifname then
            return iface
        end
   end

   return nil
end

function __extendwifi_tranlate_iface(org, new)
   local org_value
   logger.log(3,"__extendwifi_tranlate_iface ("..org['ifname'].." --> "..new['ifname']..")")
   for _,opt in pairs(EXTENDWIFI_IFACE_OPTION) do
       org_value = org[opt[1]] or opt[3]

       if org_value == nil then
           logger.log(3, "rm "..opt[1])
           uci_new:delete("wireless", new['.name'], opt[1])
       else
           if opt[2] == "string" then
           logger.log(3,opt[1].." = "..org_value)
           else
           logger.log(3,opt[1].." = ", org_value)
           end
           uci_new:set("wireless", new['.name'], opt[1], org_value)
       end
   end
    uci_new:commit("wireless")
end

function __extendwifi_tranlate_device(org, new)
    local org_value
    logger.log(3,"__extendwifi_tranlate_device ("..org['.name'].." --> "..new['.name']..")")
    for _,opt in pairs(EXTENDWIFI_DEVICE_OPTION) do
         org_value = org[opt[1]] or opt[3]
         if org_value == nil then
             logger.log(3, "rm "..opt[1])
             uci_new:delete("wireless", new['.name'], opt[1])
         else
             logger.log(3,opt[1].." = "..org_value)
             uci_new:set("wireless", new['.name'], opt[1], org_value)
         end
    end
    uci_new:commit("wireless")
end

function extendwifi_tranlate_wireless_config()
    local device_list_org = {}
    local device_list_new = {}
    local device_idx_list_org = {}
    local device_idx_list_new = {}
    local device_idx_list_nofound = {}

    local iface_list_org = {}
    local iface_list_new = {}
    local iface_idx_list_org = {}
    local iface_idx_list_new = {}
    local iface_idx_list_nofound = {}

--read device iface apcli idx form /etc/config/misc
    org_device = uci_org:get_list("misc", "wireless", "DEVICE_LIST") or {}
    new_device = uci_new:get_list("misc", "wireless", "DEVICE_LIST") or {}
    for _,idx in ipairs(org_device) do
        device_idx_list_org[#device_idx_list_org + 1] = {
            ['idx'] = idx,
            ['.name'] = uci_org:get("misc", "wireless", idx.."_name") or ""
        }
    end
    for _,idx in ipairs(new_device) do
        device_idx_list_new[#device_idx_list_new + 1] = {
            ['idx'] = idx,
            ['.name'] = uci_new:get("misc", "wireless", idx.."_name") or ""
        }
    end
    org_iface = uci_org:get_list("misc", "wireless", "IFACE_LIST") or {}
    new_iface = uci_new:get_list("misc", "wireless", "IFACE_LIST") or {}
    for _,idx in ipairs(org_iface) do
        iface_idx_list_org[#iface_idx_list_org + 1] = {
            ['idx'] = idx,
            ['.name'] = uci_org:get("misc", "wireless", idx.."_name"),
            ['ifname'] = uci_org:get("misc", "wireless", idx.."_ifname") or "",
            ['device'] = uci_org:get("misc", "wireless", (uci_new:get("misc", "wireless", idx.."_deviceidx") or "").."_name") or "",
            ['band'] = uci_org:get("misc", "wireless", (uci_new:get("misc", "wireless", idx.."_deviceidx") or "").."_band") or "",
            ['network'] = uci_org:get("misc", "wireless", idx.."_network") or "",
            ['mode'] = "ap"
        }
    end
    for _,idx in ipairs(new_iface) do
        iface_idx_list_new[#iface_idx_list_new + 1] = {
            ['idx'] = idx,
            ['.name'] = uci_new:get("misc", "wireless", idx.."_name"),
            ['ifname'] = uci_new:get("misc", "wireless", idx.."_ifname") or "",
            ['device'] = uci_new:get("misc", "wireless", (uci_new:get("misc", "wireless", idx.."_deviceidx") or "").."_name") or "",
            ['band'] = uci_new:get("misc", "wireless", (uci_new:get("misc", "wireless", idx.."_deviceidx") or "").."_band") or "",
            ['network'] = uci_new:get("misc", "wireless", idx.."_network") or "",
            ['mode'] = "ap"
        }
    end
    if HARDWARE:match("^r3600") then
    else
        org_apcli = uci_org:get_list("misc", "wireless", "APCLI_LIST") or {}
        new_apcli = uci_new:get_list("misc", "wireless", "APCLI_LIST") or {}
        for _,idx in ipairs(org_apcli) do
            iface_idx_list_org[#iface_idx_list_org + 1] = {
                ['idx'] = idx,
                ['.name'] = uci_org:get("misc", "wireless", idx.."_name"),
                ['ifname'] = uci_org:get("misc", "wireless", idx.."_ifname") or "",
                ['device'] = uci_org:get("misc", "wireless", (uci_new:get("misc", "wireless", idx.."_deviceidx") or "").."_name") or "",
                ['band'] = uci_org:get("misc", "wireless", (uci_new:get("misc", "wireless", idx.."_deviceidx") or "").."_band") or "",
                ['network'] = uci_org:get("misc", "wireless", idx.."_network") or "",
                ['mode'] = "sta"
            }
        end
        for _,idx in ipairs(new_apcli) do
            iface_idx_list_new[#iface_idx_list_new + 1] = {
                ['idx'] = idx,
                ['.name'] = uci_new:get("misc", "wireless", idx.."_name"),
                ['ifname'] = uci_new:get("misc", "wireless", idx.."_ifname") or "",
                ['device'] = uci_new:get("misc", "wireless", (uci_new:get("misc", "wireless", idx.."_deviceidx") or "").."_name") or "",
                ['band'] = uci_new:get("misc", "wireless", (uci_new:get("misc", "wireless", idx.."_deviceidx") or "").."_band") or "",
                ['network'] = uci_new:get("misc", "wireless", idx.."_network") or "",
                ['mode'] = "sta"
            }
        end
    end
--    logger.log(3, "device_idx_list_org", device_idx_list_org)
--    logger.log(3, "device_idx_list_new", device_idx_list_new)
--    logger.log(3, "iface_idx_list_org", iface_idx_list_org)
--    logger.log(3, "iface_idx_list_new", iface_idx_list_new)

--tranlate device config
--device list
    uci_org:foreach("wireless", "wifi-device",
        function(s)
            device_list_org[#device_list_org + 1] = s
        end)

    uci_new:foreach("wireless", "wifi-device",
        function(s)
            device_list_new[#device_list_new + 1] = s
        end)

--    logger.log(3, "device_list_org",  device_list_org)
--    logger.log(3, "device_list_new",  device_list_new)

-- tranlate device
    for _,idx_new in ipairs(device_idx_list_new) do
          local found
          found = false
          for _,idx_org in ipairs(device_idx_list_org) do
               if idx_new.idx == idx_org.idx then
                    dev_new = __extendwifi_getdev(device_list_new, idx_new['.name'])
                    dev_org = __extendwifi_getdev(device_list_org, idx_org['.name'])
--                    logger.log(3, dev_new, dev_org)
                    if dev_new and dev_org then
                        found = true
                        __extendwifi_tranlate_device(dev_org, dev_new)
                    end
 
               end
          end
          if found == false then
               device_idx_list_nofound[#device_idx_list_nofound + 1] = idx_new['.name']
          end
    end
--no found device use default setting
    logger.log("3", "device_idx_list_nofound(use default config)", device_idx_list_nofound)

--read iface list
    uci_org:foreach("wireless", "wifi-iface",
        function(s)
            iface_list_org[#iface_list_org + 1] = s
        end)

    uci_new:foreach("wireless", "wifi-iface",
        function(s)
            iface_list_new[#iface_list_new + 1] = s
        end)

--check basic info
    for _,idx_new in ipairs(iface_idx_list_new) do
        local my_old = __extendwifi_getiface(iface_list_new, idx_new.ifname)
        local new = {
            ['.name'] = idx_new['.name'] or idx_new.ifname,
            ['.type'] = "wifi-iface",
            ['ifname'] = idx_new.ifname,
            ['device'] = idx_new.device,
            ['network'] = idx_new.network,
            ['mode'] = idx_new.mode
        }
        if my_old == nil then
            if HARDWARE:match("^r3600") then
            else
                logger.log(3, "creat new iface"..idx_new.idx.."  "..new['.name'].." "..new['ifname'])
                uci_new:set("wireless", new['.name'], new['.type'])
                iface_list_new[#iface_list_new + 1] = new

                uci_new:set("wireless", new['.name'], "ifname", new.ifname)
                uci_new:set("wireless", new['.name'], "device", new.device)
                uci_new:set("wireless", new['.name'], "network", new.network)
                uci_new:set("wireless", new['.name'], "mode", new.mode)
                uci_new:commit("wireless")
            end
        else
            if idx_new['.name'] and idx_new['.name'] ~= my_old['.name'] then
                logger.log(3, "reset section name "..idx_new.idx.."  "..idx_new['.name'].." form "..my_old['.name'])
                uci_new:delete("wireless", my_old['.name'])
                uci_new:set("wireless", new['.name'], new['.type'])

                uci_new:set("wireless", new['.name'], "ifname", new.ifname)
                uci_new:set("wireless", new['.name'], "device", new.device)
                uci_new:set("wireless", new['.name'], "network", new.network)
                uci_new:set("wireless", new['.name'], "mode", new.mode)
                uci_new:commit("wireless")
            end
        end
    end

--reload iface list
    iface_list_new = {}
    uci_new:foreach("wireless", "wifi-iface",
        function(s)
            iface_list_new[#iface_list_new + 1] = s
        end)

--tranlate iface
    for _,idx_new in ipairs(iface_idx_list_new) do
          local found
          found = false
          for _,idx_org in ipairs(iface_idx_list_org) do
               if idx_new.idx == idx_org.idx then
                    local iface_org = __extendwifi_getiface(iface_list_org, idx_org.ifname)
                    local iface_new = __extendwifi_getiface(iface_list_new, idx_new.ifname)
                    if iface_org and iface_new then
                        found = true
                        __extendwifi_tranlate_iface(iface_org, iface_new)
                        break
                    end
               end
          end
          if found == false then
               iface_idx_list_nofound[#iface_idx_list_nofound + 1] = idx_new
          end
    end
    logger.log("3", "iface_idx_list_nofound", iface_idx_list_nofound)

--nofound tranlate
    for _,idx_new in ipairs(iface_idx_list_nofound) do
        for _,idx_org in ipairs(iface_idx_list_org) do
            local iface_org = __extendwifi_getiface(iface_list_org, idx_org.ifname)
            local iface_new = __extendwifi_getiface(iface_list_new, idx_new.ifname)
            if iface_org and iface_new then
                if HARDWARE:match("^r3600") then
                    if idx_new.mode == "ap" and idx_new.network == "lan" then
                        __extendwifi_tranlate_iface(iface_org, iface_new)
                        local post_= string.upper(idx_new.band)
                        uci_new:set("wireless", iface_new['.name'], "ssid", iface_org.ssid.."_"..post_)
                        uci_new:set("wireless", iface_new['.name'], "disabled", "0")
                    end
                else
-- normal bss
                    if idx_new.mode == "ap" and idx_new.network == "lan" then
                        __extendwifi_tranlate_iface(iface_org, iface_new)
                        local post_= string.upper(idx_new.band)
                        uci_new:set("wireless", iface_new['.name'], "ssid", iface_org.ssid.."_"..post_)
                        uci_new:set("wireless", iface_new['.name'], "disabled", "0")
-- guset
                    elseif idx_new.mode == "ap" and idx_new.network == "guest" then
                        if iface_org.macfilter then
                            uci_new:set("wireless", iface_new['.name'], "macfilter", iface_org.macfilter)
                        end
                        if iface_org.maclist then
                            uci_new:set("wireless", iface_new['.name'], "maclist", iface_org.maclist)
                        end
                        uci_new:set("wireless", iface_new['.name'], "disabled", "1")
-- miwifi ready
                    elseif idx_new.mode == "ap" and idx_new.network == "ready" then
                        uci_new:set("wireless", iface_new['.name'], "ssid", "minet_ready")
                        uci_new:set("wireless", iface_new['.name'], "dynbcn", "1")
                        uci_new:set("wireless", iface_new['.name'], "rssithreshold", "-20")
                        uci_new:set("wireless", iface_new['.name'], "encryption", "none")
                        uci_new:set("wireless", iface_new['.name'], "hidden", "1")
                        uci_new:set("wireless", iface_new['.name'], "disabled", "0")
                    else
-- apcli
                         logger.log(3, idx_new.idx.." ("..iface_new.ifname..") no found & set disabled")
                         uci_new:set("wireless", iface_new['.name'], "disabled", "1")
                    end
                    uci_new:commit("wireless")
                    break
                end
            end
        end
    end

    if HARDWARE:match("^r3600") then
    else
--apcli init for /etc/config/xiaoqiang
        local netmode = uci_org:get("xiaoqiang", "common", "NETMODE") or ""
        local active = uci_org:get("xiaoqiang", "common", "active_apcli") or ""
        if netmode ~= "" then
            uci_new:set("wireless", "NETMODE", netmode)
        end
        if active ~= "" then
            local active_idx = ""
            for _,iface_org in ipairs(iface_idx_list_org) do
                local ifname_org = uci_org:get("misc", "wireless", iface_org.idx.."_ifname") or ""
                if ifname_org == active then
                    active_idx = iface_org.idx
                end
            end
            ifname_new = uci_new:get("misc", "wireless", active_idx.."_ifname") or ""
            uci_new:set("xiaoqiang", "common", "active_apcli", ifname_new)
            mode = uci_new:get("misc", "wireless", active_idx.."_workmode") or ""
            local XQSynchrodata = require("xiaoqiang.util.XQSynchrodata")
            XQSynchrodata.syncActiveApcliMode(mode)
        end
        uci_new:commit("xiaoqiang")
    end

--cp wifi rel file
    for _,wififile in ipairs(EXTENDWIFI_FILE) do
--        luci.util.exec("rm "..wififile.." -f  2> /dev/NULL >&2")
        luci.util.exec("cp ".."/tmp/extendwifi"..wififile.." "..wififile.." -f  2> /dev/NULL >&2")
    end

    return 0
end

--- model: 0/1  black/white list
function getWiFiMacfilterList(model)
    local uci = require("luci.model.uci").cursor()
    local config = tonumber(model) == 0 and "wifiblist" or "wifiwlist"
    local maclist = uci:get_list(config, "maclist", "mac") or {}
    return maclist
end

-- model: 0/1/2
-- 0 - Disable MAC address matching.
-- 1 - Deny association to stations on the MAC list.
-- 2 - Allow association to stations on the MAC list.

function getWiFiMacfilterModel()
    local LuciNetwork = require("luci.model.network").init()
    local wifiNet = LuciNetwork:get_wifinet(_wifiNameForIndex(1))
    if wifiNet then
        local macfilter = wifiNet:get("macfilter")
        if macfilter == "disabled" then
            return 0
        elseif macfilter == "deny" then
            return 1
        elseif macfilter == "allow" then
            return 2
        else
            return 0
        end
    else
        return 0
    end
end

function getCurrentMacfilterList()
    local LuciNetwork = require("luci.model.network").init()
    local wifiNet = LuciNetwork:get_wifinet(_wifiNameForIndex(1))
    return wifiNet:get("maclist")
end

--- 0/1/2/3 操作成功/数量超过限制/参数不正确/Mesh路由不能添加到黑名单
function addDevice(model, mac, name)
    local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
    local XQSync = require("xiaoqiang.util.XQSynchrodata")
    if not XQFunction.isStrNil(mac) and not XQFunction.isStrNil(name) then
        mac = XQFunction.macFormat(mac)
        local macstr = XQFunction._cmdformat(mac)
        if HARDWARE:match("^d01") and tonumber(model) == 0 then
            local cmd = string.format("/sbin/chk_sta_re \"%s\"", macstr)
            local isresta = tostring(LuciUtil.trim(LuciUtil.exec(cmd)))
            if isresta == "resta" then
                return 3
            end
        end
        XQDBUtil.saveDeviceInfo(mac, name, name, "", "")
        local uci = require("luci.model.uci").cursor()
        local config = tonumber(model) == 0 and "wifiblist" or "wifiwlist"
        local maclist = uci:get_list(config, "maclist", "mac") or {}
        for _, macaddr in ipairs(maclist) do
            if mac == macaddr then
                return 0
            end
        end
        table.insert(maclist, mac)
        if #maclist > 32 then
            return 1
        end
        XQSync.syncDeviceInfo({["mac"] = mac, ["limited"] = 1})
        uci:set_list(config, "maclist", "mac", maclist)
        uci:commit(config)

        -- config
        local macfilter
        if tonumber(model) == 1 then
            macfilter = "allow"
        else
            macfilter = "deny"
        end
        --- Guest wifi
        local guestwifi = uci:get_all("wireless", "guest_2G")
        if guestwifi and tonumber(model) == 0 then
            guestwifi["macfilter"] = macfilter
            if maclist and #maclist > 0 then
                guestwifi["maclist"] = maclist
            else
                guestwifi["maclist"] = nil
                uci:delete("wireless", "guest_2G", "maclist")
            end
            uci:section("wireless", "wifi-iface", "guest_2G", guestwifi)
            uci:commit("wireless")
        end
        local LuciNetwork = require("luci.model.network").init()
        local wifiNet1 = LuciNetwork:get_wifinet(_wifiNameForIndex(1))
        local wifiNet2 = LuciNetwork:get_wifinet(_wifiNameForIndex(2))
        if wifiNet1 then
            wifiNet1:set("macfilter", macfilter)
            if maclist and #maclist > 0 then
                wifiNet1:set_list("maclist", maclist)
            else
                wifiNet1:set_list("maclist", nil)
            end
        end
        if wifiNet2 then
            wifiNet2:set("macfilter", macfilter)
            if maclist and #maclist > 0 then
                wifiNet2:set_list("maclist", maclist)
            else
                wifiNet2:set_list("maclist", nil)
            end
        end
        LuciNetwork:save("wireless")
        LuciNetwork:commit("wireless")

        if tonumber(model) == 0 then
            if HARDWARE:match("^r1800") or HARDWARE:match("^r4c$") or HARDWARE:match("^r3600") or HARDWARE:match("^r2200$") then
                os.execute("iwpriv wl0 addmac_sec \""..macstr.."\"")
                os.execute("iwpriv wl1 addmac_sec \""..macstr.."\"")
                os.execute("iwpriv wl14 addmac_sec \""..macstr.."\"")
                os.execute("iwpriv wl0 maccmd_sec 2")
                os.execute("iwpriv wl1 maccmd_sec 2")
                os.execute("iwpriv wl14 maccmd_sec 2")
                os.execute("iwpriv wl0 kickmac \""..macstr.."\"")
                os.execute("iwpriv wl1 kickmac \""..macstr.."\"")
                os.execute("iwpriv wl14 kickmac \""..macstr.."\"")
            else
                os.execute("wl -i wl0 mac \""..macstr.."\"")
                os.execute("wl -i wl1 mac \""..macstr.."\"")
                os.execute("wl -i wl1.2 mac \""..macstr.."\"")
                os.execute("wl -i wl0 macmode 1")
                os.execute("wl -i wl1 macmode 1")
                os.execute("wl -i wl1.2 macmode 1")
                os.execute("wl -i wl0 deauthenticate \""..macstr.."\"")
                os.execute("wl -i wl1 deauthenticate \""..macstr.."\"")
                os.execute("wl -i wl1.2 deauthenticate \""..macstr.."\"")
            end
        elseif tonumber(model) == 1 then
            if HARDWARE:match("^r1800") or HARDWARE:match("^r4c$") or HARDWARE:match("^r3600") or HARDWARE:match("^r2200$") then
                os.execute("iwpriv wl0 addmac_sec \""..macstr.."\"")
                os.execute("iwpriv wl1 addmac_sec \""..macstr.."\"")
                -- os.execute("iwpriv wl14 addmac_sec \""..macstr.."\"")
                os.execute("iwpriv wl0 maccmd_sec 1")
                os.execute("iwpriv wl1 maccmd_sec 1")
                -- remove guestwifi white list
                os.execute("iwpriv wl14 maccmd_sec 0")
            else
                os.execute("wl -i wl0 mac \""..macstr.."\"")
                os.execute("wl -i wl1 mac \""..macstr.."\"")
                -- os.execute("wl -i wl1.2 mac \""..macstr.."\"")
                os.execute("wl -i wl0 macmode 2")
                os.execute("wl -i wl1 macmode 2")
                -- remove guestwifi white list
                os.execute("wl -i wl1.2 macmode 0")
            end
        end
        return 0
    else
        return 2
    end
end

--- private function
--- model: 0/1  black/white list
--- option: 0/1 add/remove
function wl_editWiFiMacfilterList(model, macs, option)
    if not macs or XQFunction.isStrNil(option) then
        return
    end
    local XQSync = require("xiaoqiang.util.XQSynchrodata")
    local uci = require("luci.model.uci").cursor()
    local config = tonumber(model) == 0 and "wifiblist" or "wifiwlist"
    local maclist = uci:get_list(config, "maclist", "mac") or {}
    local cmodel = getWiFiMacfilterModel()
    local current = getCurrentMacfilterList()

    if option == 0 then
        local macdic = {}
        for _, macaddr in ipairs(maclist) do
            macdic[XQFunction.macFormat(macaddr)] = 1
        end
        for _, macaddr in ipairs(macs) do
            if not XQFunction.isStrNil(macaddr) then
                macdic[XQFunction.macFormat(macaddr)] = 1
            end
        end
        maclist = {}
        for mac, value in pairs(macdic) do
            if value == 1 then
                table.insert(maclist, mac)
            end
        end
        if #maclist > 32 then
            return 1
        end
    else
        local macdic = {}
        for _, macaddr in ipairs(maclist) do
            macdic[XQFunction.macFormat(macaddr)] = 1
        end
        for _, macaddr in ipairs(macs) do
            if not XQFunction.isStrNil(macaddr) then
                macdic[XQFunction.macFormat(macaddr)] = 0
            end
        end
        maclist = {}
        for mac, value in pairs(macdic) do
            if value == 1 then
                table.insert(maclist, mac)
            end
        end
    end

    if model == 0 then
        local dict = {}
        local needsync = {}
        if current then
            for _, mac in ipairs(current) do
                dict[XQFunction.macFormat(mac)] = 1
            end
        end
        if option == 0 then
            for _, mac in ipairs(macs) do
                mac = XQFunction.macFormat(mac)
                if not dict[mac] then
                    needsync[mac] = 1
                end
            end
        elseif option == 1 then
            for _, mac in ipairs(macs) do
                mac = XQFunction.macFormat(mac)
                if dict[mac] then
                    needsync[mac] = 0
                end
            end
        end
        for mac, limited in pairs(needsync) do
            XQSync.syncDeviceInfo({["mac"] = mac, ["limited"] = limited})
        end
    end

    os.execute("wl -i wl0 mac none")
    os.execute("wl -i wl1 mac none")
    os.execute("wl -i wl1.2 mac none")
    local nmaclist = {}
    for _, value in ipairs(maclist) do
        local nvalue = XQFunction._cmdformat(value)
        table.insert(nmaclist, nvalue)
    end
    local macstr = table.concat(nmaclist, "\" \"")
    if tonumber(model) == 0 then
        os.execute("wl -i wl0 mac \""..macstr.."\"")
        os.execute("wl -i wl1 mac \""..macstr.."\"")
        os.execute("wl -i wl1.2 mac \""..macstr.."\"")
        os.execute("wl -i wl0 macmode 1")
        os.execute("wl -i wl1 macmode 1")
        os.execute("wl -i wl1.2 macmode 1")
        for _, value in ipairs(nmaclist) do
            os.execute("wl -i wl0 deauthenticate \""..value.."\"")
            os.execute("wl -i wl1 deauthenticate \""..value.."\"")
            os.execute("wl -i wl1.2 deauthenticate \""..value.."\"")
        end
    elseif tonumber(model) == 1 then
        os.execute("wl -i wl0 mac \""..macstr.."\"")
        os.execute("wl -i wl1 mac \""..macstr.."\"")
        -- os.execute("wl -i wl1.2 mac \""..macstr.."\"")
        os.execute("wl -i wl0 macmode 2")
        os.execute("wl -i wl1 macmode 2")
        os.execute("wl -i wl1.2 macmode 0")
        if option == 1 and macs then
            for _, mac in ipairs(macs) do
                if mac then
                    mac = XQFunction._cmdformat(mac)
                    os.execute("wl -i wl0 deauthenticate \""..mac.."\"")
                    os.execute("wl -i wl1 deauthenticate \""..mac.."\"")
                    os.execute("wl -i wl1.2 deauthenticate \""..mac.."\"")
                end
            end
        end
    end
    if #maclist > 0 then
        uci:set_list(config, "maclist", "mac", maclist)
    else
        uci:delete(config, "maclist", "mac")
    end
    uci:commit(config)
    -- wireless
    local macfilter
    if tonumber(model) == 1 then
        macfilter = "allow"
    else
        macfilter = "deny"
    end
    -- Guest wifi
    local guestwifi = uci:get_all("wireless", "guest_2G")
    if guestwifi and tonumber(model) == 0 then
        guestwifi["macfilter"] = macfilter
        if maclist and #maclist > 0 then
            guestwifi["maclist"] = maclist
        else
            guestwifi["maclist"] = nil
            uci:delete("wireless", "guest_2G", "maclist")
        end
        uci:section("wireless", "wifi-iface", "guest_2G", guestwifi)
        uci:commit("wireless")
    end
    local LuciNetwork = require("luci.model.network").init()
    local wifiNet1 = LuciNetwork:get_wifinet(_wifiNameForIndex(1))
    local wifiNet2 = LuciNetwork:get_wifinet(_wifiNameForIndex(2))
    if wifiNet1 then
        wifiNet1:set("macfilter", macfilter)
        if maclist and #maclist > 0 then
            wifiNet1:set_list("maclist", maclist)
        else
            wifiNet1:set_list("maclist", nil)
        end
    end
    if wifiNet2 then
        wifiNet2:set("macfilter", macfilter)
        if maclist and #maclist > 0 then
            wifiNet2:set_list("maclist", maclist)
        else
            wifiNet2:set_list("maclist", nil)
        end
    end
    LuciNetwork:save("wireless")
    LuciNetwork:commit("wireless")
    os.execute("ubus call trafficd update_assoclist")
end

--- private function
--- 0/1/2 op success/num over limit/para wrong
--- model: 0/1  black/white list
--- macs: mac address array
--- option: 0/1 add/remove
function iwpriv_editWiFiMacfilterList(model, macs, option)
    local XQSync = require("xiaoqiang.util.XQSynchrodata")
    if not macs or type(macs) ~= "table" or XQFunction.isStrNil(option) then
        return 2
    end
    local uci = require("luci.model.uci").cursor()
    local config = tonumber(model) == 0 and "wifiblist" or "wifiwlist"
    local maclist = uci:get_list(config, "maclist", "mac") or {}
    local current = getCurrentMacfilterList()
    if option == 0 then
        local macdic = {}
        for _, macaddr in ipairs(maclist) do
            macdic[XQFunction.macFormat(macaddr)] = 1
        end
        for _, macaddr in ipairs(macs) do
            if not XQFunction.isStrNil(macaddr) then
                macdic[XQFunction.macFormat(macaddr)] = 1
            end
        end
        maclist = {}
        for mac, value in pairs(macdic) do
            if value == 1 then
                table.insert(maclist, mac)
            end
        end
        if #maclist > 32 then
            return 1
        end
    else
        local macdic = {}
        for _, macaddr in ipairs(maclist) do
            macdic[XQFunction.macFormat(macaddr)] = 1
        end
        for _, macaddr in ipairs(macs) do
            if not XQFunction.isStrNil(macaddr) then
                macdic[XQFunction.macFormat(macaddr)] = 0
            end
        end
        maclist = {}
        for mac, value in pairs(macdic) do
            if value == 1 then
                table.insert(maclist, mac)
            end
        end
    end

    if model == 0 then
        local dict = {}
        local needsync = {}
        if current then
            for _, mac in ipairs(current) do
                dict[XQFunction.macFormat(mac)] = 1
            end
        end
        if option == 0 then
            for _, mac in ipairs(macs) do
                mac = XQFunction.macFormat(mac)
                if not dict[mac] then
                    needsync[mac] = 1
                end
            end
        elseif option == 1 then
            for _, mac in ipairs(macs) do
                mac = XQFunction.macFormat(mac)
                if dict[mac] then
                    needsync[mac] = 0
                end
            end
        end
        for mac, limited in pairs(needsync) do
            XQSync.syncDeviceInfo({["mac"] = mac, ["limited"] = limited})
        end
    end
    -- local macstr = XQFunction._cmdformat(table.concat(maclist, ";"))
    -- os.execute("iwpriv wl0 set ACLClearAll=1")
    -- os.execute("iwpriv wl1 set ACLClearAll=1")
    -- os.execute("iwpriv wl3 set ACLClearAll=1")
    -- if tonumber(model) == 0 then
    --     for _, mac in ipairs(maclist) do
    --         local cmac = XQFunction._cmdformat(mac)
    --         os.execute("iwpriv wl0 set DisConnectSta=\""..cmac.."\"")
    --         os.execute("iwpriv wl1 set DisConnectSta=\""..cmac.."\"")
    --         os.execute("iwpriv wl3 set DisConnectSta=\""..cmac.."\"")
    --     end
    -- end
    -- os.execute("iwpriv wl0 set ACLAddEntry=\""..macstr.."\"")
    -- os.execute("iwpriv wl1 set ACLAddEntry=\""..macstr.."\"")
    -- os.execute("iwpriv wl3 set ACLAddEntry=\""..macstr.."\"")   local s = player1+action1[r]+

    -- if tonumber(model) == 0 then
    --     os.execute("iwpriv wl0 set AccessPolicy=2")
    --     os.execute("iwpriv wl1 set AccessPolicy=2")
    --     os.execute("iwpriv wl3 set AccessPolicy=2")
    -- else
    --     os.execute("iwpriv wl0 set AccessPolicy=1")
    --     os.execute("iwpriv wl1 set AccessPolicy=1")
    --     os.execute("iwpriv wl3 set AccessPolicy=1")
    -- end
    if #maclist > 0 then
        uci:set_list(config, "maclist", "mac", maclist)
    else
        uci:delete(config, "maclist", "mac")
        -- os.execute("iwpriv wl0 set AccessPolicy=0")
        -- os.execute("iwpriv wl1 set AccessPolicy=0")
        -- os.execute("iwpriv wl3 set AccessPolicy=0")
    end
    uci:commit(config)
    -- wireless
    local macfilter
    if tonumber(model) == 1 then
        macfilter = "allow"
    else
        macfilter = "deny"
    end
    -- Guest wifi
    local guestwifi = uci:get_all("wireless", "guest_2G")
    if guestwifi and tonumber(model) == 0 then
        guestwifi["macfilter"] = macfilter
        if maclist and #maclist > 0 then
            guestwifi["maclist"] = maclist
        else
            guestwifi["maclist"] = nil
            uci:delete("wireless", "guest_2G", "maclist")
        end
        uci:section("wireless", "wifi-iface", "guest_2G", guestwifi)
        uci:commit("wireless")
    end
    local LuciNetwork = require("luci.model.network").init()
    local wifiNet1 = LuciNetwork:get_wifinet(_wifiNameForIndex(1))
    local wifiNet2 = LuciNetwork:get_wifinet(_wifiNameForIndex(2))
    if wifiNet1 then
        wifiNet1:set("macfilter", macfilter)
        if maclist and #maclist > 0 then
            wifiNet1:set_list("maclist", maclist)
        else
            wifiNet1:set_list("maclist", nil)
        end
    end
    if wifiNet2 then
        wifiNet2:set("macfilter", macfilter)
        if maclist and #maclist > 0 then
            wifiNet2:set_list("maclist", maclist)
        else
            wifiNet2:set_list("maclist", nil)
        end
    end
    LuciNetwork:save("wireless")
    LuciNetwork:commit("wireless")
    -- os.execute("ubus call trafficd update_assoclist")
    local json = require("json")
    local payload = json.encode({
        ["model"] = model,
        ["maclist"] = maclist
    })
    XQFunction.forkExec("lua /usr/sbin/iwpriv_macfilter.lua 2 \""..XQFunction._cmdformat(payload).."\"")
    return 0
end

--- private function
--- 0/1/2 op success/num over limit/para wrong
--- model: 0/1  black/white list
--- macs: mac address array
--- option: 0/1 add/remove
function qca_iwpriv_editWiFiMacfilterList(model, macs, option)
    if not macs or type(macs) ~= "table" or XQFunction.isStrNil(option) then
        return 2
    end
    local XQSync = require("xiaoqiang.util.XQSynchrodata")
    local uci = require("luci.model.uci").cursor()
    local config = tonumber(model) == 0 and "wifiblist" or "wifiwlist"
    local maclist = uci:get_list(config, "maclist", "mac") or {}
    local current = getCurrentMacfilterList()

    if option == 0 then
        local macdic = {}
        for _, macaddr in ipairs(maclist) do
            macdic[XQFunction.macFormat(macaddr)] = 1
        end
        for _, macaddr in ipairs(macs) do
            if not XQFunction.isStrNil(macaddr) then
                macdic[XQFunction.macFormat(macaddr)] = 1
            end
        end
        maclist = {}
        for mac, value in pairs(macdic) do
            if value == 1 then
                table.insert(maclist, mac)
            end
        end
        if #maclist > 32 then
            return 1
        end
    else
        local macdic = {}
        for _, macaddr in ipairs(maclist) do
            macdic[XQFunction.macFormat(macaddr)] = 1
        end
        for _, macaddr in ipairs(macs) do
            if not XQFunction.isStrNil(macaddr) then
                macdic[XQFunction.macFormat(macaddr)] = 0
            end
        end
        maclist = {}
        for mac, value in pairs(macdic) do
            if value == 1 then
                table.insert(maclist, mac)
            end
        end
    end

    if model == 0 then
        local dict = {}
        local needsync = {}
        if current then
            for _, mac in ipairs(current) do
                dict[XQFunction.macFormat(mac)] = 1
            end
        end
        if option == 0 then
            for _, mac in ipairs(macs) do
                mac = XQFunction.macFormat(mac)
                if not dict[mac] then
                    needsync[mac] = 1
                end
            end
        elseif option == 1 then
            for _, mac in ipairs(macs) do
                mac = XQFunction.macFormat(mac)
                if dict[mac] then
                    needsync[mac] = 0
                end
            end
        end
        for mac, limited in pairs(needsync) do
            XQSync.syncDeviceInfo({["mac"] = mac, ["limited"] = limited})
        end
    end

    os.execute("iwpriv wl0 maccmd_sec 3")
    os.execute("iwpriv wl1 maccmd_sec 3")
    os.execute("iwpriv wl14 maccmd_sec 3")
    os.execute("iwpriv wl0 maccmd_sec 0")
    os.execute("iwpriv wl1 maccmd_sec 0")
    os.execute("iwpriv wl14 maccmd_sec 0")
    local nmaclist = {}
    for _, value in ipairs(maclist) do
        local nvalue = XQFunction._cmdformat(value)
        table.insert(nmaclist, nvalue)
    end
--    local macstr = table.concat(nmaclist, "\" \"")
    for _, value in ipairs(nmaclist) do
        os.execute("iwpriv wl0 addmac_sec \""..value.."\"")
        os.execute("iwpriv wl1 addmac_sec \""..value.."\"")
        os.execute("iwpriv wl14 addmac_sec \""..value.."\"")
    end
    --model=0, black list
    if tonumber(model) == 0 then
        os.execute("iwpriv wl0 maccmd_sec 2")
        os.execute("iwpriv wl1 maccmd_sec 2")
        os.execute("iwpriv wl14 maccmd_sec 2")
        for _, value in ipairs(nmaclist) do
            os.execute("iwpriv wl0 kickmac \""..value.."\"")
            os.execute("iwpriv wl1 kickmac \""..value.."\"")
            os.execute("iwpriv wl14 kickmac \""..value.."\"")
        end
    --model=1, white list
    elseif tonumber(model) == 1 then
        os.execute("iwpriv wl0 maccmd_sec 1")
        os.execute("iwpriv wl1 maccmd_sec 1")
        -- remove guestwifi white list
        os.execute("iwpriv wl14 maccmd_sec 0")
        if option == 1 and macs then
            for _, mac in ipairs(macs) do
                if mac then
                    mac = XQFunction._cmdformat(mac)
                    os.execute("iwpriv wl0 kickmac \""..mac.."\"")
                    os.execute("iwpriv wl1 kickmac \""..mac.."\"")
                    os.execute("iwpriv wl14 kickmac \""..mac.."\"")
                end
            end
        end
    end
    if #maclist > 0 then
        uci:set_list(config, "maclist", "mac", maclist)
    else
        uci:delete(config, "maclist", "mac")
    end
    uci:commit(config)
    -- wireless
    local macfilter
    if tonumber(model) == 1 then
        macfilter = "allow"
    else
        macfilter = "deny"
    end
    -- Guest wifi
    local guestwifi = uci:get_all("wireless", "guest_2G")
    if guestwifi and tonumber(model) == 0 then
        guestwifi["macfilter"] = macfilter
        if maclist and #maclist > 0 then
            guestwifi["maclist"] = maclist
        else
            guestwifi["maclist"] = nil
            uci:delete("wireless", "guest_2G", "maclist")
        end
        uci:section("wireless", "wifi-iface", "guest_2G", guestwifi)
        uci:commit("wireless")
    end
    local LuciNetwork = require("luci.model.network").init()
    local wifiNet1 = LuciNetwork:get_wifinet(_wifiNameForIndex(1))
    local wifiNet2 = LuciNetwork:get_wifinet(_wifiNameForIndex(2))
    if wifiNet1 then
        wifiNet1:set("macfilter", macfilter)
        if maclist and #maclist > 0 then
            wifiNet1:set_list("maclist", maclist)
        else
            wifiNet1:set_list("maclist", nil)
        end
    end
    if wifiNet2 then
        wifiNet2:set("macfilter", macfilter)
        if maclist and #maclist > 0 then
            wifiNet2:set_list("maclist", maclist)
        else
            wifiNet2:set_list("maclist", nil)
        end
    end
    LuciNetwork:save("wireless")
    LuciNetwork:commit("wireless")
    os.execute("ubus call trafficd update_assoclist")
end

--- model: 0/1  black/white list
--- option: 0/1 add/remove
editWiFiMacfilterList = wl_editWiFiMacfilterList

if HARDWARE:match("^r1800") or HARDWARE:match("^r4c$") or HARDWARE:match("^r3600") or HARDWARE:match("^r2200$") then
    editWiFiMacfilterList = qca_iwpriv_editWiFiMacfilterList
elseif HARDWARE:match("^r1c") or HARDWARE:match("^r3") or HARDWARE:match("^r4") or HARDWARE:match("^r2100") or HARDWARE:match("^r2600") then
    editWiFiMacfilterList = iwpriv_editWiFiMacfilterList
end

--- 2015.7.31, auth default: false->true (PM:cy)
--- model: 0/1  black/white list
function getWiFiMacfilterInfo(model)
    local LuciUtil      = require("luci.util")
    local LuciNetwork   = require("luci.model.network").init()
    local XQDBUtil      = require("xiaoqiang.util.XQDBUtil")
    local XQEquipment   = require("xiaoqiang.XQEquipment")
    local XQPushUtil    = require("xiaoqiang.util.XQPushUtil")
    local wifiNet = LuciNetwork:get_wifinet(_wifiNameForIndex(1))
    local settings = XQPushUtil.pushSettings()
    local info = {
        ["enable"] = settings.auth and 1 or 0,
        ["model"] = 0
    }
    if wifiNet then
        local macfilter = wifiNet:get("macfilter")
        if macfilter == "disabled" then
            info["model"] = 0
        elseif macfilter == "deny" then
            info["model"] = 0
        elseif macfilter == "allow" then
            info["model"] = 1
        else
            info["model"] = 0
        end
    end
    local maclist = {}
    local mlist = getWiFiMacfilterList(model == nil and info.model or model)
    for _, mac in ipairs(mlist) do
        mac = XQFunction.macFormat(mac)
        local item = {
            ["mac"] = mac
        }
        local name = ""
        local device = XQDBUtil.fetchDeviceInfo(mac)
        if device then
            local originName = device.oName
            local nickName = device.nickname
            if not XQFunction.isStrNil(nickName) then
                name = nickName
            else
                local company = XQEquipment.identifyDevice(mac, originName)
                local dtype = company["type"]
                if XQFunction.isStrNil(name) and not XQFunction.isStrNil(dtype.n) then
                    name = dtype.n
                end
                if XQFunction.isStrNil(name) and not XQFunction.isStrNil(originName) then
                    name = originName
                end
                if XQFunction.isStrNil(name) and not XQFunction.isStrNil(company.name) then
                    name = company.name
                end
                if XQFunction.isStrNil(name) then
                    name = mac
                end
                if dtype.c == 3 and XQFunction.isStrNil(nickName) then
                    name = dtype.n
                end
            end
            item["name"] = name
        end
        table.insert(maclist, item)
    end
    info["maclist"] = maclist
    info["weblist"] = mlist
    return info
end

--- model: 0/1  black/white list
function setWiFiMacfilterModel(enable, model)
    local macfilter
    local maclist
    if enable then
        if tonumber(model) == 1 then
            macfilter = "allow"
            maclist = getWiFiMacfilterList(1)
        else
            macfilter = "deny"
            maclist = getWiFiMacfilterList(0)
        end
    else
        macfilter = "disabled"
        local XQPushUtil = require("xiaoqiang.util.XQPushUtil")
        XQPushUtil.pushConfig("auth", "0")
    end
    -- Guest wifi
    local uci = require("luci.model.uci").cursor()
    local guestwifi = uci:get_all("wireless", "guest_2G")
    if guestwifi and tonumber(model) == 0 then
        guestwifi["macfilter"] = macfilter
        if maclist and #maclist > 0 then
            guestwifi["maclist"] = maclist
        else
            guestwifi["maclist"] = nil
            uci:delete("wireless", "guest_2G", "maclist")
        end
        uci:section("wireless", "wifi-iface", "guest_2G", guestwifi)
        uci:commit("wireless")
    end
    local LuciUtil = require("luci.util")
    local LuciNetwork = require("luci.model.network").init()
    local wifiNet1 = LuciNetwork:get_wifinet(_wifiNameForIndex(1))
    local wifiNet2 = LuciNetwork:get_wifinet(_wifiNameForIndex(2))
    if wifiNet1 then
        wifiNet1:set("macfilter", macfilter)
        if maclist and #maclist > 0 then
            wifiNet1:set_list("maclist", maclist)
        else
            wifiNet1:set_list("maclist", nil)
        end
    end
    if wifiNet2 then
        wifiNet2:set("macfilter", macfilter)
        if maclist and #maclist > 0 then
            wifiNet2:set_list("maclist", maclist)
        else
            wifiNet2:set_list("maclist", nil)
        end
    end
    LuciNetwork:save("wireless")
    LuciNetwork:commit("wireless")
    local wifi1 = getWifiConnectDeviceList(1)
    local wifi2 = getWifiConnectDeviceList(2)
    local macdict = {}
    if maclist and type(maclist) == "table" then
        for _, value in ipairs(maclist) do
            if value then
                macdict[value] = true
            end
        end
    end
    if not enable then
        if HARDWARE:match("^r1800") or HARDWARE:match("^r4c$") or HARDWARE:match("^r3600") or HARDWARE:match("^r2200$") then
            local cmd = [[
                iwpriv wl0 maccmd_sec 3;
                iwpriv wl1 maccmd_sec 3;
                iwpriv wl14 maccmd_sec 3;
                iwpriv wl0 maccmd_sec 0;
                iwpriv wl1 maccmd_sec 0;
                iwpriv wl14 maccmd_sec 0
            ]]
            XQFunction.forkExec(cmd)
            uci:delete("wireless", "guest", "maclist")
            uci:set("wireless", "guest", "macfilter", macfilter)
            uci:commit("wireless")
    elseif HARDWARE:match("^r1c") or HARDWARE:match("^r3") or HARDWARE:match("^r4") or HARDWARE:match("^r2100") or HARDWARE:match("^r2600") then
            -- os.execute("iwpriv wl0 set ACLClearAll=1")
            -- os.execute("iwpriv wl1 set ACLClearAll=1")
            -- os.execute("iwpriv wl3 set ACLClearAll=1")
            -- os.execute("iwpriv wl0 set AccessPolicy=0")
            -- os.execute("iwpriv wl1 set AccessPolicy=0")
            -- os.execute("iwpriv wl3 set AccessPolicy=0")
            local cmd = [[
                sleep 2;
                iwpriv wl0 set ACLClearAll=1;
                iwpriv wl1 set ACLClearAll=1;
                iwpriv wl3 set ACLClearAll=1;
                iwpriv wl0 set AccessPolicy=0;
                iwpriv wl1 set AccessPolicy=0;
                iwpriv wl3 set AccessPolicy=0
            ]]
            XQFunction.forkExec(cmd)
        else
            os.execute("wl -i wl0 mac none")
            os.execute("wl -i wl1 mac none")
            os.execute("wl -i wl1.2 mac none")
            os.execute("wl -i wl0 macmode 0")
            os.execute("wl -i wl1 macmode 0")
            os.execute("wl -i wl1.2 macmode 0")
            uci:delete("wireless", "guest", "maclist")
            uci:set("wireless", "guest", "macfilter", macfilter)
            uci:commit("wireless")
        end
    else
        if HARDWARE:match("^r1800") or HARDWARE:match("^r4c$") or HARDWARE:match("^r3600") or HARDWARE:match("^r2200$") then
            os.execute("iwpriv wl0 maccmd_sec 3")
            os.execute("iwpriv wl1 maccmd_sec 3")
            os.execute("iwpriv wl14 maccmd_sec 3")
            os.execute("iwpriv wl0 maccmd_sec 0")
            os.execute("iwpriv wl1 maccmd_sec 0")
            os.execute("iwpriv wl14 maccmd_sec 0")
            local nmaclist = {}
            for _, value in ipairs(maclist) do
                local nvalue = XQFunction._cmdformat(value)
                table.insert(nmaclist, nvalue)
            end
--            local macstr = table.concat(nmaclist, "\" \"")
            for _, value in ipairs(nmaclist) do
                os.execute("iwpriv wl0 addmac_sec \""..value.."\"")
                os.execute("iwpriv wl1 addmac_sec \""..value.."\"")
                os.execute("iwpriv wl14 addmac_sec \""..value.."\"")
            end
            if tonumber(model) == 0 then
                os.execute("iwpriv wl0 maccmd_sec 2")
                os.execute("iwpriv wl1 maccmd_sec 2")
                os.execute("iwpriv wl14 maccmd_sec 2")
                for _, value in ipairs(nmaclist) do
                    os.execute("iwpriv wl0 kickmac \""..value.."\"")
                    os.execute("iwpriv wl1 kickmac \""..value.."\"")
                    os.execute("iwpriv wl14 kickmac \""..value.."\"")
                end
            elseif tonumber(model) == 1 then
                os.execute("iwpriv wl0 maccmd_sec 1")
                os.execute("iwpriv wl1 maccmd_sec 1")
                -- remove guestwifi white list
                os.execute("iwpriv wl14 maccmd_sec 0")
                if wifi1 and type(wifi1) == "table" then
                    for _, value in ipairs(wifi1) do
                        if not macdict[value] then
                            local cmac = XQFunction._cmdformat(value)
                            os.execute("iwpriv wl1 kickmac \""..cmac.."\"")
                        end
                    end
                end
                if wifi2 and type(wifi2) == "table" then
                    for _, value in ipairs(wifi2) do
                        if not macdict[value] then
                            local cmac = XQFunction._cmdformat(value)
                            os.execute("iwpriv wl0 kickmac \""..cmac.."\"")
                        end
                    end
                end
                local assoclist = LuciUtil.execl("wlanconfig wl14 list | awk -F ' ' '{if(NR>1) print$1}'")
                if assoclist then
                    for _, line in ipairs(assoclist) do
                        if not XQFunction.isStrNil(line) then
                            local mac = line:match("(%S+)")
                            if mac then
                                mac = XQFunction._cmdformat(XQFunction.macFormat(mac))
                                os.execute("iwpriv wl14 kickmac \""..mac.."\"")
                            end
                        end
                    end
                end
            end
        elseif HARDWARE:match("^r1c") or HARDWARE:match("^r3") or HARDWARE:match("^r4") or HARDWARE:match("^r2100") or HARDWARE:match("^r2600") or HARDWARE:match("^r2200") then
            -- local macstr = XQFunction._cmdformat(table.concat(maclist, ";"))
            -- os.execute("iwpriv wl0 set ACLClearAll=1")
            -- os.execute("iwpriv wl1 set ACLClearAll=1")
            -- os.execute("iwpriv wl3 set ACLClearAll=1")
            -- os.execute("iwpriv wl0 set ACLAddEntry=\""..macstr.."\"")
            -- os.execute("iwpriv wl1 set ACLAddEntry=\""..macstr.."\"")
            -- os.execute("iwpriv wl3 set ACLAddEntry=\""..macstr.."\"")

            -- if tonumber(model) == 0 then
            --     os.execute("iwpriv wl0 set AccessPolicy=2")
            --     os.execute("iwpriv wl1 set AccessPolicy=2")
            --     os.execute("iwpriv wl3 set AccessPolicy=2")
            --     for _, mac in ipairs(maclist) do
            --         local cmac = XQFunction._cmdformat(mac)
            --         os.execute("iwpriv wl0 set DisConnectSta=\""..cmac.."\"")
            --         os.execute("iwpriv wl1 set DisConnectSta=\""..cmac.."\"")
            --         os.execute("iwpriv wl3 set DisConnectSta=\""..cmac.."\"")
            --     end
            -- else
            --     os.execute("iwpriv wl0 set AccessPolicy=1")
            --     os.execute("iwpriv wl1 set AccessPolicy=1")
            --     os.execute("iwpriv wl3 set AccessPolicy=1")
            --     if wifi1 and type(wifi1) == "table" then
            --         for _, value in ipairs(wifi1) do
            --             if not macdict[value] then
            --                 local cmac = XQFunction._cmdformat(value)
            --                 os.execute("iwpriv wl1 set DisConnectSta=\""..cmac.."\"")
            --             end
            --         end
            --     end
            --     if wifi2 and type(wifi2) == "table" then
            --         for _, value in ipairs(wifi2) do
            --             if not macdict[value] then
            --                 local cmac = XQFunction._cmdformat(value)
            --                 os.execute("iwpriv wl0 set DisConnectSta=\""..cmac.."\"")
            --             end
            --         end
            --     end
            -- end
            local json = require("json")
            local payload = json.encode({
                ["model"] = model,
                ["maclist"] = maclist
            })
            XQFunction.forkExec("lua /usr/sbin/iwpriv_macfilter.lua 2 \""..XQFunction._cmdformat(payload).."\"")
        else
            os.execute("wl -i wl0 mac none")
            os.execute("wl -i wl1 mac none")
            os.execute("wl -i wl1.2 mac none")
            local nmaclist = {}
            for _, value in ipairs(maclist) do
                local nvalue = XQFunction._cmdformat(value)
                table.insert(nmaclist, nvalue)
            end
            local macstr = table.concat(nmaclist, "\" \"")
            if tonumber(model) == 0 then
                os.execute("wl -i wl0 mac \""..macstr.."\"")
                os.execute("wl -i wl1 mac \""..macstr.."\"")
                os.execute("wl -i wl1.2 mac \""..macstr.."\"")
                os.execute("wl -i wl0 macmode 1")
                os.execute("wl -i wl1 macmode 1")
                os.execute("wl -i wl1.2 macmode 1")
                for _, value in ipairs(nmaclist) do
                    os.execute("wl -i wl0 deauthenticate \""..value.."\"")
                    os.execute("wl -i wl1 deauthenticate \""..value.."\"")
                    os.execute("wl -i wl1.2 deauthenticate \""..value.."\"")
                end
            elseif tonumber(model) == 1 then
                os.execute("wl -i wl0 mac \""..macstr.."\"")
                os.execute("wl -i wl1 mac \""..macstr.."\"")
                -- os.execute("wl -i wl1.2 mac \""..macstr.."\"")
                os.execute("wl -i wl0 macmode 2")
                os.execute("wl -i wl1 macmode 2")
                os.execute("wl -i wl1.2 macmode 0")
                if wifi1 and type(wifi1) == "table" then
                    for _, value in ipairs(wifi1) do
                        if not macdict[value] then
                            local cmac = XQFunction._cmdformat(value)
                            os.execute("wl -i wl1 deauthenticate \""..cmac.."\"")
                        end
                    end
                end
                if wifi2 and type(wifi2) == "table" then
                    for _, value in ipairs(wifi2) do
                        if not macdict[value] then
                            local cmac = XQFunction._cmdformat(value)
                            os.execute("wl -i wl0 deauthenticate \""..cmac.."\"")
                        end
                    end
                end
                local assoclist = LuciUtil.execl("wl -i wl1.2 assoclist")
                if assoclist then
                    for _, line in ipairs(assoclist) do
                        if not XQFunction.isStrNil(line) then
                            local mac = line:match("assoclist (%S+)")
                            if mac then
                                mac = XQFunction._cmdformat(XQFunction.macFormat(mac))
                                os.execute("wl -i wl1.2 deauthenticate \""..mac.."\"")
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Add new method to get guest wifi ssid
function getGuestWifi_ssid()
    -- Get mac from mtd
    local defaultMac
    if HARDWARE:match("^r3600") then
        defaultMac = luci.sys.exec("getmac wan")
    else
        defaultMac = luci.sys.exec("getmac eth")
    end
    local ssidSuffix = string.upper(string.sub(string.gsub(defaultMac,":",""),-5,-2))
    local XQCountryCode = require("xiaoqiang.XQCountryCode")
    local ccode = XQCountryCode.getCurrentCountryCode()

    local guest_ssid
    local guest_ssid_ext="  MiShareWiFi_"
    if ccode == "CN" then
        guest_ssid_ext="  小米共享WiFi_"
    end
    guest_ssid = guest_ssid_ext..ssidSuffix

    return guest_ssid
end

function getGuestWifi(wifiIndex)
    local uci = require("luci.model.uci").cursor()
    local guest_wifi = uci:get("misc", "modules", "guestwifi")
    if not guest_wifi then
        return nil
    end
    local index = tonumber(wifiIndex)
    local status
    if index then
        status = getWifiStatus(index)
        if index == 1 then
            index = "guest_2G"
        elseif index == 2 then
            index = "guest_5G"
        else
            index = nil
        end
    end
    local guestwifi
    local guest_ssid = getGuestWifi_ssid()
    if index and status then
        guestwifi = uci:get_all("wireless", index)
        if guestwifi then
            return {
                ["ifname"]      = guestwifi.ifname,
                ["ssid"]        = guestwifi.ssid or guest_ssid,
                ["encryption"]  = guestwifi.encryption or "mixed-psk",
                ["password"]    = guestwifi.key or "12345678",
                ["status"]      = tonumber(guestwifi.disabled) == 0 and 1 or 0,
                ["enabled"]     = "1"
            }
        end
    end
    if not guestwifi then
        guestwifi = {
            ["ifname"]      = guest_wifi,
            ["ssid"]        = guest_ssid,
            ["encryption"]  = "mixed-psk",
            ["password"]    = "12345678",
            ["status"]      = "0",
            ["enabled"]     = "1"
        }
    end
    return guestwifi
end

function setGuestWifi(wifiIndex, ssid, encryption, key, enabled, open, wps)
    local LuciNetwork = require("luci.model.network").init()
    local wifiDev = LuciNetwork:get_wifidev(LuciUtil.split(_wifiNameForIndex(1),".")[1])
    local wifiNet = LuciNetwork:get_wifinet(_wifiNameForIndex(1))
    if wifiDev == nil or wifiNet == nil then
    	return false
    end
    local macfilter = wifiNet:get("macfilter")
    local open = tonumber(open)
    local disabled = tonumber(wifiDev:get("disabled")) == 1
    if disabled and open == 1 then
        --do not set uci wl0, wl2 enable
        --[[
        local bsd = wifiNet:get("bsd")
        if bsd and tonumber(bsd) == 1 then
            local wifiDev2 = LuciNetwork:get_wifidev(LuciUtil.split(_wifiNameForIndex(2),".")[1])
            if wifiDev2 then
                wifiDev2:set("disabled", "0")
            end
        end
        ]]
        wifiDev:set("disabled", "0")
        LuciNetwork:commit("wireless")
    end

    local uci = require("luci.model.uci").cursor()
    local wifinetid, ifname
    local enabled = tonumber(enabled) == 1 and 1 or 0

    local guest_wifi = uci:get("misc", "modules", "guestwifi")
    if not guest_wifi then
        return true
    end

    if tonumber(wifiIndex) == 1 then
        wifinetid = "guest_2G"
        ifname = uci:get("misc", "wireless", "ifname_guest_2G")
    elseif tonumber(wifiIndex) == 2 then
        wifinetid = "guest_5G"
    else
        return false
    end
    guestwifi = uci:get_all("wireless", wifinetid)
    if guestwifi then
        guestwifi["ifname"] = ifname
        if not XQFunction.isStrNil(ssid) and XQFunction.checkSSID(ssid) then
            guestwifi["ssid"] = ssid
        end
        if encryption and string.lower(tostring(encryption)) == "none" then
            if key and string.lower(tostring(key)) == "12345678" then
                guestwifi["encryption"] = "none"
                guestwifi["key"] = key
            else
                guestwifi["encryption"] = "none"
                guestwifi["key"] = ""
            end
        end
        if encryption and string.lower(tostring(encryption)) ~= "none" and not XQFunction.isStrNil(key) then
            local check = checkWifiPasswd(key,encryption)
            if check == 0 then
                guestwifi["encryption"] = encryption
                guestwifi["key"] = key
            else
                return false
            end
        end
        local oldconf = guestwifi.disabled or 1
        if enabled then
            guestwifi["disabled"] = enabled == 1 and 0 or 1
        end
        if open then
            guestwifi["disabled"] = open == 1 and 0 or 1
        end
        if oldconf ~= guestwifi.disabled then
            -- if guestwifi.disabled == 1 then
            --     os.execute(string.format("wl -i %s bss down; ifconfig %s down", ifname, ifname))
            -- else
            --     XQFunction.forkExec(string.format("wl -i %s bss up; ifconfig %s up", ifname, ifname))
            -- end
        end
    else
        if XQFunction.isStrNil(ssid) or XQFunction.isStrNil(encryption) then
            return false
        end
        local gdisabled = 1
        if open == 1 then
            gdisabled = 0
        end
        guestwifi = {
            ["device"] = WIFI_DEVS[wifiIndex],
            ["ifname"] = ifname,
            ["network"] = "guest",
            ["ssid"] = ssid,
            ["mode"] = "ap",
            ["encryption"] = encryption,
            ["key"] = key,
            ["disabled"] = gdisabled
        }

        if macfilter == "deny" then
            guestwifi.macfilter= macfilter
            guestwifi.maclist = getCurrentMacfilterList()
        end

        -- if guestwifi.disabled == 1 then
        --     os.execute(string.format("wl -i %s bss down; ifconfig %s down", ifname, ifname))
        -- else
        --     XQFunction.forkExec(string.format("wl -i %s bss up; ifconfig %s up", ifname, ifname))
        -- end
    end

    --XQLog.log(6," ==========   key: " .. guestwifi["key"])
    guestwifi["wpsdevicename"] = wps or "XIAOMI_ROUTER_GUEST"
    uci:section("wireless", "wifi-iface", wifinetid, guestwifi)
    uci:commit("wireless")
    return true
end

function delGuestWifi(wifiIndex)
    local uci = require("luci.model.uci").cursor()
    local wifinetid
    if tonumber(wifiIndex) == 1 then
        wifinetid = "guest_2G"
    elseif tonumber(wifiIndex) == 2 then
        wifinetid = "guest_5G"
    else
        return false
    end
    uci:delete("wireless", wifinetid)
    uci:commit("wireless")
    return true
end

function scanWifiChannel(wifiIndex)
    local result = {["code"] = 0}
    local cchannel, schannel, cscore, sscore
    local wifi = tonumber(wifiIndex) == 1 and "wl1" or "wl0"
    local scancmd
    if HARDWARE:match("^r1800") or HARDWARE:match("^r4c$") or HARDWARE:match("^r3600") or HARDWARE:match("^r2200$") then
        scancmd = "setchanauto.sh "..tostring(wifi).." getresult"
    else
        scancmd  = "iwpriv "..tostring(wifi).." ScanResult"
    end
    local scanresult = LuciUtil.execl(scancmd)
    local scandict = {}
    if scanresult then
        for _, line in ipairs(scanresult) do
            if not XQFunction.isStrNil(line) then
                if not cchannel or not cscore then
                    cchannel, cscore = line:match("^Current Channel (%S+) : Score = (%d+)")
                end
                if not schannel or not sscore then
                    schannel, sscore = line:match("^Select Channel (%S+) : Score = (%d+)")
                end
                local ichannel, iscore = line:match("^Channel (%S+) : Score = (%d+)")
                if ichannel and iscore then
                    scandict[ichannel] = tonumber(iscore)
                end
            end
        end
    end

    if cchannel and schannel and cscore and sscore then
        result["cchannel"] = tostring(cchannel)
        result["schannel"] = tostring(schannel)
        result["cscore"] = tonumber(cscore)
        result["sscore"] = tonumber(sscore)
        local ranking = 1
        for key, value in pairs(scandict) do
            if key ~= cchannel then
                if result.cscore > value then
                    ranking = ranking + 1
                end
            end
        end
        result["ranking"] = ranking
    else
        result["code"] = 1
        result["cchannel"] = tostring(cchannel) or ""
        result["schannel"] = tostring(schannel) or ""
        result["cscore"] = tonumber(cscore) or 0
        result["sscore"] = tonumber(sscore) or 0
        result["ranking"] = 0
    end
    return result
end

function wifiChannelQuality()
    local wifiinfo = getAllWifiInfo()
    if wifiinfo[1] and wifiinfo[1].status == "1" then
        if HARDWARE:match("^r1800") or HARDWARE:match("^r4c$") or HARDWARE:match("^r3600") or HARDWARE:match("^r2200$") then
            XQFunction.forkExec("sleep 4; iwpriv wl1 acsreport 1 > /dev/null")
        else
            XQFunction.forkExec("sleep 4; iwpriv wl1 set AutoChannelSel=4")
        end
    end
    --[[ stop 5G channel auto scan
    if wifiinfo[2] and wifiinfo[2].status == "1" then
        if HARDWARE:match("^r1800") or HARDWARE:match("^r4c$") or HARDWARE:match("^r3600") then
            XQFunction.forkExec("sleep 4; iwpriv wl0 acsreport 1 > /dev/null")
        else
            XQFunction.forkExec("sleep 4; iwpriv wl0 set AutoChannelSel=3")
        end
    end
    ]]--
end

function iwprivSetChannel(channel1, channel2)
    if channel1 then
        local setcmd
        if HARDWARE:match("^r1800") or HARDWARE:match("^r4c$") or HARDWARE:match("^r3600") or HARDWARE:match("^r2200$") then
            setcmd = "sleep 4; iwconfig wl1 channel \""..XQFunction._cmdformat(tostring(channel1)).."\""
        else
            setcmd = "sleep 4; iwpriv wl1 set Channel=\""..XQFunction._cmdformat(tostring(channel1)).."\""
        end
        local chinf = channelHelper(channel1)
        local network = LuciNetwork.init()
        local wifiDev = network:get_wifidev(LuciUtil.split(_wifiNameForIndex(1),".")[1])
        wifiDev:set("bw", chinf.bandwidth)
        wifiDev:set("autoch","0")
        wifiDev:set("channel", chinf.channel)
        network:commit("wireless")
        XQFunction.forkExec(setcmd)
    end
    --[[
    if channel2 then
        local setcmd = "sleep 4; iwpriv wl0 set Channel="..tostring(channel2)
        XQFunction.forkExec(setcmd)
    end
    ]]--
end

function wifiutil_get_dev_info_form_band(band)
    local uci = require("luci.model.uci").cursor()
    local network = LuciNetwork.init()
    local device = uci:get_list("misc", "wireless", "device_"..band.."_name")
    if device ~= nil then
        return network:get_wifidev(device)
    else
        return nil
    end
end

function setWifiWeakInfo(wifiIndex, weakenable, weakthreshold, kickthreshold)
    local network = LuciNetwork.init()
    local wifiNet = network:get_wifinet(_wifiNameForIndex(wifiIndex))
    if wifiNet == nil then
        return false
    end

    if not XQFunction.isStrNil(weakenable) then
        wifiNet:set("weakenable",weakenable);
    end
    if not XQFunction.isStrNil(weakthreshold) then
        wifiNet:set("weakthreshold",weakthreshold);
    end
    if not XQFunction.isStrNil(kickthreshold) then
        wifiNet:set("kickthreshold",kickthreshold);
    end

    network:save("wireless")
    network:commit("wireless")
    return true
end

function getWifiWeakInfo()
    local infoList = {}
    local infoDict = {}
    local wifis = wifiNetworks()
    for i,wifiNet in ipairs(wifis) do
        local item = {}
        local index = 1

        item["weakenable"] = wifiNet.networks[index].weakenable or 0
        item["weakthreshold"] = wifiNet.networks[index].weakthreshold or 0
        item["kickthreshold"] = wifiNet.networks[index].kickthreshold or 0
        infoDict[wifiNet.device] = item
    end
    if infoDict[WIFI2G] then
        table.insert(infoList, infoDict[WIFI2G])
    end
    if infoDict[WIFI5G] then
        table.insert(infoList, infoDict[WIFI5G])
    end
    --[[
    local guestwifi = getGuestWifi(1)
    if guestwifi and XQFunction.getNetModeType() == 0 then
        table.insert(infoList, guestwifi)
    end
    ]]--
    return infoList
end

function miscanSwitch(on)
    local success
    local uci = require("luci.model.uci").cursor()

    if on then
        uci:set("miscan", "config", "enabled", "1")
    else
        uci:set("miscan", "config", "enabled", "0")
    end
    uci:commit("miscan")

    if on then
        success = tonumber(os.execute("/etc/init.d/scan start"))
    else
        success = tonumber(os.execute("/etc/init.d/scan stop"))
    end

    if success ~= 0 then
        if on then
            uci:set("miscan", "config", "enabled", "0")
        else
            uci:set("miscan", "config", "enabled", "1")
        end
        uci:commit("miscan")
        return false
    end

    return true
end

function getMiscanSwitch()
    local enabled
    local uci = require("luci.model.uci").cursor()
    enabled = uci:get("miscan", "config", "enabled")  or "0"
    return enabled
end

--wifi-iface
function apcli_get_real_signal(ifname)
    if ifname then
        local get_signal_cmd = "iwconfig "..ifname.." | awk 'NR==7' | awk -F '=' '{print $3}' | awk '{print $1}'"
        local file = io.popen(get_signal_cmd)
        local signal = file:read("*all")
        return tonumber(signal)
    else
        return 0
    end
end
