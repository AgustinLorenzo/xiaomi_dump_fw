module ("xiaoqiang.util.XQQoSUtil", package.seeall)

local cursor = require("luci.model.uci").cursor()

local XQConfigs = require("xiaoqiang.common.XQConfigs")
local XQFunction = require("xiaoqiang.common.XQFunction")
local XQSysUtil = require("xiaoqiang.util.XQSysUtil")

function _application()
    local cursor = luci.model.uci.cursor()
    local config = cursor:get_all("app-tc","config")
    local xunlei = cursor:get_all("app-tc","xunlei")
    local kuaipan = cursor:get_all("app-tc","kuaipan")
    local application = {}
    if config then
        application.enable = config.enable
    end
    if xunlei then
        application.xunlei = xunlei
    end
    if kuaipan then
        application.kuaipan = kuaipan
    end
    return application
end

function _set(section, option, value)
    cursor:set("app-tc", section, option, value)
end

function _apply()
    cursor:save("app-tc")
    cursor:commit("app-tc")
end

function _appSpeedlimit(app, maxdownload, maxupload)
    if maxdownload then
        _set(app, "max_download_speed", tostring(maxdownload))
    end
    if maxupload then
        _set(app, "max_upload_speed", tostring(maxupload))
    end
    _apply()
end

function appSpeedlimitSwitch(enable)
    local cmd = enable and XQConfigs.QOS_APPSL_ENABLE or XQConfigs.QOS_APPSL_DISABLE
    local value = enable and "1" or "0"
    _set("config", "enable", value)
    _apply()
    return (os.execute(cmd) == 0)
end

function appInfo()
    local json = require("json")
    local LuciUtil = require("luci.util")
    local info = {}
    local xunlei = {}
    local kuaipan = {}
    local application = _application()

    local xlcspeed = XQFunction.thrift_tunnel_to_datacenter([[{"api":45,"appCode":1}]])
    local kpcspeed = XQFunction.thrift_tunnel_to_datacenter([[{"api":45,"appCode":0}]])

    if xlcspeed and xlcspeed.code == 0 then
        xunlei.download = tonumber(xlcspeed.downloadSpeed)
        xunlei.upload = tonumber(xlcspeed.uploadSpeed)
    else
        xunlei.download = 0
        xunlei.upload = 0
    end
    if kpcspeed and kpcspeed.code == 0 then
        kuaipan.download = tonumber(kpcspeed.downloadSpeed)
        kuaipan.upload = tonumber(kpcspeed.uploadSpeed)
    else
        kuaipan.download = 0
        kuaipan.upload = 0
    end
    info.enable = application.enable
    xunlei.enable = application.xunlei.enable
    xunlei.maxdownload = tonumber(application.xunlei.max_download_speed)
    xunlei.maxupload = tonumber(application.xunlei.max_upload_speed)

    kuaipan.enable = application.kuaipan.enable
    kuaipan.maxdownload = tonumber(application.kuaipan.max_download_speed)
    kuaipan.maxupload = tonumber(application.kuaipan.max_upload_speed)
    info.xunlei = xunlei
    info.kuaipan = kuaipan
    return info
end

function setXunlei(maxdownload, maxupload)
    _appSpeedlimit("xunlei", maxdownload, maxupload)
end

function setKuaipan(maxdownload, maxupload)
    _appSpeedlimit("kuaipan", maxdownload, maxupload)
end

function reload()
    os.execute(XQConfigs.QOS_APPSL_RELOAD)
end

--
-- smart qos
--
-- return KB
function _bitFormat(bits)
    if XQFunction.isStrNil(bits) then
        return 0
    end
    if type(bits) == "number" then
        return tonumber(string.format("%0.2f", bits/8192))
    end
    if bits:match("Gbit") then
        return tonumber(bits:match("(%S+)Gbit"))*131072
    elseif bits:match("Mbit") then
        return tonumber(bits:match("(%S+)Mbit"))*128
    elseif bits:match("Kbit") then
        return tonumber(string.format("%0.2f",tonumber(bits:match("(%S+)Kbit"))/8))
    elseif bits:match("bit") then
        return tonumber(string.format("%0.2f",tonumber(bits:match("(%S+)bit"))/8192))
    else
        return 0
    end
end

function _weightHelper(level)
    if level == 1 then
        return 0.25
    elseif level == 2 then
        return 0.5
    elseif level == 3 then
        return 0.75
    else
        return 0.1
    end
end

-- 0/1/2/3  unset/low/middel/high
function _levelHelper(weight)
    if weight == 0 then
        return 2
    elseif weight > 0 and weight <= 0.25 then
        return 1
    elseif weight > 0.25 and weight <= 0.5 then
        return 2
    elseif weight > 0.5 then
        return 3
    end
    return 0
end

function qosSwitch(on)
    if on then
        return os.execute("/etc/init.d/miqos on") == 0
    else
        return os.execute("/etc/init.d/miqos off") == 0
    end
end

function setQoSMode(mode)
    local mode = tonumber(mode)
    if mode then
        if mode == 0 then
            return os.execute("/etc/init.d/miqos set_type auto") == 0
        elseif mode == 1 then
            return os.execute("/etc/init.d/miqos set_type min") == 0
        elseif mode == 2 then
            return os.execute("/etc/init.d/miqos set_type max") == 0
        elseif mode == 3 then -- auto
            return os.execute("/etc/init.d/miqos set_type service && /etc/init.d/miqos set_seq auto") == 0
        elseif mode == 4 then -- game
            return os.execute("/etc/init.d/miqos set_type service && /etc/init.d/miqos set_seq game") == 0
        elseif mode == 5 then -- web
            return os.execute("/etc/init.d/miqos set_type service && /etc/init.d/miqos set_seq web") == 0
        elseif mode == 6 then -- video
            return os.execute("/etc/init.d/miqos set_type service && /etc/init.d/miqos set_seq video") == 0
        end
    end
    return false
end

function qosRestart()
    return os.execute("/etc/init.d/miqos restart")
end

-- on   : 0/1 close/open
-- mode : 0/1/2 auto/min/max
-- service-mode: 3/4/5/6 auto/game-1st/web-1st/video-1st
function qosStatus()
    local uci = require("luci.model.uci").cursor()
    local status = {}
    if os.execute("/etc/init.d/miqos status") == 0 then
        status["on"] = 1
        status["mode"] = 0
        local MiQos = require("miqos")
        local showlimit = MiQos.cmd("show_limit")
        local seq_list = {
                auto =3,
                game =4,
                web  =5,
                video=6,
            }
        if showlimit and showlimit.status == 0 and showlimit.mode then
            if showlimit.mode == "auto" then
                status["mode"] = 0
            elseif showlimit.mode == "min" then
                status["mode"] = 1
            elseif showlimit.mode == "max" then
                status["mode"] = 2
            elseif showlimit.mode == "service" or showlimit.mode == "noifb" then
                local seq = MiQos.cmd("get_seq")
                if seq.status == 0 then
                    status["mode"] = seq_list[seq.data.seq_prio] or seq_list["auto"]
                else
                    status["mode"] = seq_list["auto"]
                end
            else
                status["mode"] = seq_list["auto"]
            end
        end
    else
        status["on"] = 0
        status["mode"] = 0
    end
    return status
end

-- M bits/s
function qosBand()
    local MiQos = require("miqos")
    local result = {
        ["download"] = 0,
        ["upload"] = 0
    }
    local band = MiQos.cmd("show_band")
    if band and band.status == 0 and band.data then
        result.download = tonumber(string.format("%0.2f", band.data.downlink/1024))
        result.upload = tonumber(string.format("%0.2f", band.data.uplink/1024))
    end
    return result
end

function wangzheInfo()
    local MiQos = require("miqos")
    local result = {
        ["switch"] = 0,
    }
    local wangzhe = MiQos.cmd("show_wangzhe")
    if wangzhe and wangzhe.status == 0 and wangzhe.data then
        result.switch = wangzhe.data.switch
    end
    return result
end
-- get band in /etc/config/miqos
-- function qosBandinConf()
--     local uci = require "luci.model.uci"
--     local cursor = uci.cursor()
--     local config = "miqos"
--     local _upload = cursor:get(config, "settings", "upload") or 0
--     local _download = cursor:get(config, "settings", "download") or 0
--     _upload = tonumber(_upload)
--     _download = tonumber(_download)
--     local result = {
--         ["download"] = tonumber(string.format("%0.2f", _download/1000)),
--         ["upload"] = tonumber(string.format("%0.2f", _upload/1000))
--     }
--     return result
-- end

-- M bits/s
function setQosBand(upload, download)
    local MiQos = require("miqos")
    if upload and download then
        local _upload = tostring(math.floor(1024*upload))
        local _download = tostring(math.floor(1024*download))
        local setband = MiQos.cmd(string.format("change_band %s %s", _upload, _download))
        if setband and setband.status == 0 then
            return true
        end
    end
    return false
end

-- set band in /etc/config/miqos
-- function setQosBandinConf(upload, download)
--     local XQPreference = require("xiaoqiang.XQPreference")
--     local uci = require "luci.model.uci"
--     local cursor = uci.cursor()
--     local config = "miqos"
--     if upload and download then
--         local _upload = tostring(math.floor(1000*upload))
--         local _download = tostring(math.floor(1000*download))
--         cursor:set(config, "settings", "upload", _upload)
--         cursor:set(config, "settings", "download", _download)
--         cursor:save(config)
--         cursor:commit(config)

--         XQPreference.set("BANDWIDTH", tostring(download), "xiaoqiang")
--         XQPreference.set("BANDWIDTH2", tostring(upload), "xiaoqiang")

--     else
--         return false
--     end
--     return true
-- end

function qosList()
    local LuciUtil = require("luci.util")
    local MiQos = require("miqos")
    local XQDeviceUtil = require("xiaoqiang.util.XQDeviceUtil")
    local result = {}
    local devicedict = {}
    local devicelist = XQDeviceUtil.getDeviceList(true, true)
    local qoslist = MiQos.cmd("show_limit")
    local band = qosBand()
    if devicelist and type(devicelist) == "table" and #devicelist > 0 then
        for _, item in ipairs(devicelist) do
            devicedict[item.ip] = item
        end
    end
    if devicedict and qoslist and qoslist.status == 0 and qoslist.data then
        for ip, value in pairs(qoslist.data) do
            local device = devicedict[ip]
            if device then
                device = LuciUtil.clone(device, true)
                device.ip = ip
                local qos = {}
                qos["downmax"] = tonumber(value.DOWN.max_per) / 8
                qos["downmin"] = tonumber(value.DOWN.min_per) / 8
                local dpercent
                local level
                if band.download > 0 then
                    dpercent = 100 * (tonumber(value.DOWN.max_per) or 1)
                    level = _levelHelper(tonumber(value.DOWN.min_per) or 0)
                else
                    level = 2
                    dpercent = 100
                end
                qos["maxdownper"] = dpercent
                qos["upmax"] = tonumber(value.UP.max_per) / 8
                qos["upmin"] = tonumber(value.UP.min_per) / 8
                local upercent
                if band.upload > 0 then
                    upercent = 100 * (tonumber(value.UP.max_per) or 1)
                else
                    upercent = 100
                end
                qos["level"] = level
                qos["upmaxper"] = upercent
                device["qos"] = qos
                -- Remove hw node in ap mode for qos devicelist.
                if device.isap == 0 then
                    table.insert(result, device)
                end
            end
        end
    end
    return result
end

function macQosInfo(mac)
    local MiQos = require("miqos")
    local cfg_list = MiQos.cmd("show_cfg")

    local macInfo={
        ["upmax"] = 0,
        ["downmax"] = 0,
        ["flag"] = "off",
    }
    if cfg_list.status ~= 0 then
        return nil
    end

    if cfg_list.data and cfg_list.data[mac] then
        macInfo["upmax"] = tonumber(cfg_list.data[mac]["max_grp_uplink"]) / 8
        macInfo["downmax"] = tonumber(cfg_list.data[mac]["max_grp_downlink"]) / 8
        macInfo["flag"] = cfg_list.data[mac].flag
        if not cfg_list.data[mac].flag then
            if macInfo["upmax"] > 0 or macInfo["downmax"] > 0 then
                macInfo["flag"] = "on"
            else
                macInfo["flag"] = "off"
            end
        end
    end
    return macInfo
end

-- only set 1 device qos's up/down maxlimit
function setMacQosInfo(mac, upmax, downmax)
    local MiQos = require("miqos")
    if not XQFunction.isStrNil(mac) then
        mac = XQFunction.macFormat(mac)
        if tonumber(upmax) and tonumber(downmax) then
            local data=MiQos.cmd(string.format("on_limit max %s %s %s", mac, tostring(8 * tonumber(upmax)), tostring(8 * tonumber(downmax))))
            if data.status == 0 then
                return true
            end
        end
    end
    return false
end

-- maxup/maxdown (0, 1]
-- upweight/downweight (low, middle, high)
-- function qosOnLimit(mac, maxup, maxdown, upweight, downweight)
--     local MiQos = require("miqos")
--     if mac and maxup and maxdown and upweight and downweight then
--         local maxup = tonumber(maxup)
--         local maxdown = tonumber(maxdown)
--         if maxup > 1 then
--             maxup = 1
--         elseif maxup <= 0 then
--             maxup = 0.1
--         end
--         if maxdown > 1 then
--             maxdown = 1
--         elseif maxdown <= 0 then
--             maxdown = 0.1
--         end
--         local upweight = tostring(_weightHelper(upweight))
--         local downweight = tostring(_weightHelper(downweight))
--         local mac = XQFunction.macFormat(mac)
--         local limit = MiQos.cmd(string.format("set_limit %s %s %s %s %s", mac, maxup, maxdown, upweight, downweight))
--         if limit and limit.status == 0 then
--             return true
--         end
--     end
--     return false
-- end

-- mode: 0/1/2 自动/优先级/手动
function qosOnLimit(mac, mode, maxup, maxdown)
    local MiQos = require("miqos")
    if not XQFunction.isStrNil(mac) and tonumber(mode) then
        local mac = XQFunction.macFormat(mac)
        local mode = tonumber(mode)
        local cmode = qosStatus()
        if cmode and cmode.mode ~= mode then
            if not setQoSMode(mode) then
                return false
            end
        end
        if mode == 1 then
            local maxup = _weightHelper(tonumber(maxup))
            local maxdown = _weightHelper(tonumber(maxdown))
            if maxup and maxdown then
                XQFunction.execute_safe(string.format("/etc/init.d/miqos on_limit min %s %s %s", mac, tostring(maxup), tostring(maxdown)))
                return true
            end
        else
            if tonumber(maxup) and tonumber(maxdown) then
                XQFunction.execute_safe(string.format("/etc/init.d/miqos on_limit max %s %s %s", mac, tostring(8 * tonumber(maxup)), tostring(8 * tonumber(maxdown))))
                return true
            end
        end
    end
    return false
end

function qosLimitFlag(mac, on_flag)
    local MiQos = require("miqos")
    if not XQFunction.isStrNil(mac) and (on_flag == 'on' or on_flag == 'off') then
        local mac = XQFunction.macFormat(mac)
        local ret=MiQos.cmd("limit_flag ".. mac .. " " .. on_flag)
        if ret.status == 0 then
            return true
        else
            return false
        end
    else
        return false
    end
end

function qosOnLimits(mode, data)

    if not data or type(data) ~= "table" or #data <= 0 then
        return false
    end

    local MiQos = require("miqos")
    if mode and tonumber(mode) then
        local cmode = qosStatus()
        if cmode and cmode.mode ~= mode then
            if not setQoSMode(mode) then
                return false
            end
        end

        for _, item in ipairs(data) do
            local mac = XQFunction.macFormat(item.mac)
            local maxup = tonumber(item.maxup)
            local maxdown = tonumber(item.maxdown)
            if mode == 1 then
                local maxup = _weightHelper(tonumber(item.maxup))
                local maxdown = _weightHelper(tonumber(item.maxdown))
                if maxup and maxdown then
                    XQFunction.execute_safe(string.format("/etc/init.d/miqos set_limit min %s %s %s", mac, tostring(maxup), tostring(maxdown)))
                end
            else
                if tonumber(maxup) and tonumber(maxdown) then
                    XQFunction.execute_safe(string.format("/etc/init.d/miqos on_limit max %s %s %s", mac, tostring(8 * tonumber(maxup)), tostring(8 * tonumber(maxdown))))
                end
            end
        end
        MiQos.cmd("apply")
        return true
    else
        for _, item in ipairs(data) do
            local mac = XQFunction.macFormat(item.mac)
            local maxup = tonumber(item.maxup)
            local maxdown = tonumber(item.maxdown)
            if tonumber(maxup) and tonumber(maxdown) then
                XQFunction.execute_safe(string.format("/etc/init.d/miqos set_limit max %s %s %s", mac, tostring(8 * tonumber(maxup)), tostring(8 * tonumber(maxdown))))
            end
        end
        MiQos.cmd("apply")
        return true
    end
    return false
end

-- if mac = nil then clear all limits
function qosOffLimit(mac)
    local MiQos = require("miqos")
    local offlimit
    if not XQFunction.isStrNil(mac) then
        offlimit = MiQos.cmd(string.format("off_limit %s", XQFunction.macFormat(mac)))
    else
        offlimit = MiQos.cmd(string.format("off_limit"))
    end
    if offlimit and offlimit.status == 0 then
        return true
    else
        return false
    end
end

-- macs : mac array
-- on   : 0/1 close/open
-- mode : 0/1/2 auto/min/max
function qosHistory(macs)
    local LuciUtil = require("luci.util")
    local MiQos = require("miqos")
    local history = {
        ["status"] = {
            ["on"] = 0,
            ["mode"] = 0,
        },
        ["band"] = {
            ["upload"] = 0,
            ["download"] = 0
        }
    }
    local status = qosStatus()
    history.status = status
    history.band = qosBand()
    local cfg = MiQos.cmd("show_cfg")
    if cfg then
        if cfg.status == 0 and status.mode ~= 0 then
            local dict = {}
            if macs and type(macs) == "table" and #macs > 0 then
                for _, mac in ipairs(macs) do
                    local item = {}
                    item["mac"]= XQFunction.macFormat(mac)
                    local value = cfg.data[item.mac]
                    if value then
                        if status.mode == 1 then
                            item["level"] = _levelHelper(tonumber(value.min_grp_downlink))
                        else
                            item["upmax"] = tonumber(value.max_grp_uplink) / 8
                            item["downmax"] = tonumber(value.max_grp_downlink) / 8
                        end
                        if not value.flag then
                            if (item['upmax'] and item['upmax'] > 0) or (item['downmax'] and item['downmax'] > 0) then
                                item["flag"] = "on"
                            else
                                item["flag"] = "off"
                            end
                        elseif value.flag == "on" then
                            item["flag"] = "on"
                        else
                            item["flag"] = "off"
                        end
                    else
                        if status.mode == 1 then
                            item["level"] = 2
                        else
                            item["upmax"] = 0
                            item["downmax"] = 0
                        end
                        item["flag"] = "off"
                    end
                    dict[mac] = item
                end
            else
                for mac, value in pairs(cfg.data) do
                    local item = {}
                    if status.mode == 1 then
                        item["mac"] = mac
                        item["level"] = _levelHelper(tonumber(value.min_grp_downlink))
                    else
                        item["mac"] = mac
                        item["upmax"] = tonumber(value.max_grp_uplink) / 8
                        item["downmax"] = tonumber(value.max_grp_downlink) / 8
                    end
                    if not value.flag then
                        if (item['upmax'] and item['upmax'] > 0) or (item['downmax'] and item['downmax'] > 0) then
                            item["flag"] = "on"
                        else
                            item["flag"] = "off"
                        end
                    elseif value.flag == "on" then
                        item["flag"] = "on"
                    else
                        item["flag"] = "off"
                    end
                    dict[mac] = item
                end
            end
            history["dict"] = dict
        end
    end
    return history
end

function guestQoSInfo()
    local MiQos = require("miqos")
    local info = {
        ["up"] = 0,
        ["down"] = 0,
        ["percent"] = 0.6,
        ["percent_up"] = 0.6,
    }
    local qosinfo = MiQos.cmd("show_guest")
    if qosinfo and qosinfo.data and qosinfo.data.inner then
        info.up = tonumber(qosinfo.data.UP)
        info.down = tonumber(qosinfo.data.DOWN)
        info.percent = tonumber(qosinfo.data.inner.DOWN)
        info.percent_up = tonumber(qosinfo.data.inner.UP)
    end
    return info
end

function xqQoSInfo()
    local MiQos = require("miqos")
    local info={
        ["up"] = 0,
        ["down"] = 0,
        ["percent"] = 0.9,
        ["percent_up"] = 0.9,
    }
    local xqinfo = MiQos.cmd("show_xq")
    if xqinfo and xqinfo.data and xqinfo.data.inner then
        info.up = tonumber(xqinfo.data.UP)
        info.down = tonumber(xqinfo.data.DOWN)
        info.percent = tonumber(xqinfo.data.inner.DOWN)
        info.percent_up = tonumber(xqinfo.data.inner.UP)
    end

    return info
end

function setQosGuestAndXQ(type, percent, percent_up)
    local MiQos = require("miqos")
    local cmd_line
    if percent and tonumber(percent) and tonumber(percent) >= 0 and tonumber(percent) <= 1 then
        if not percent_up or tonumber(percent_up) < 0 and tonumber(percent_up) > 1 then
            percent_up = percent
        end
        if type == "guest" then
            cmd_line = "on_guest "
        elseif type == "xq" then
            cmd_line = "on_xq "
        else
            return false
        end
        cmd_line = cmd_line .. tostring(percent_up) .. " " ..tostring(percent)
        MiQos.cmd(cmd_line)
        return true
    else
        return false
    end
end

function qosGuest(percent,percent_up)
    return setQosGuestAndXQ("guest", percent, percent_up)
end

function qosXQ(percent, percent_up)
    return setQosGuestAndXQ("xq", percent, percent_up)
end

--
-- appname: app name
-- sip: client ip
-- dip: remote ip
-- dport: remote port
-- opt: 0/1 add/delete
--
-- @return
--  0: 操作成功
-- -1: 参数不正确
-- -2: 创建/删除APP Entry失败
-- -3: 创建/删除Lan Entry失败
-- -4: 创建/删除Remote Entry失败
--
function qos_app(appname, sip, dip, dport, opt)
    local cryp = require("xqcrypto")
    if not appname or not opt then
        return -1
    end
    local appid = cryp.app_opt(tostring(appname), "+")
    if appid >= 0 then
        if opt == 0 then
            if cryp.lan_opt(tostring(appid), "+", sip or "0.0.0.0") == 0 then
                if dip or dport then
                    if cryp.remote_opt(tostring(appid), "+", tostring(dip or "0.0.0.0"), tostring(dport or 0)) == 0 then
                        return 0
                    else
                        return -4
                    end
                end
            else
                return -3
            end
        elseif opt == 1 then
            if not sip then
                if cryp.app_opt(tostring(appname), "-") >= 0 then
                    return 0
                else
                    return -2
                end
            else
                if cryp.lan_opt(tostring(appid), "-", sip) == 0 then
                    return 0
                else
                    return -3
                end
                if dip or dport then
                    if cryp.remote_opt(tostring(appid), "-", tostring(dip or "0.0.0.0"), tostring(dport or 0)) == 0 then
                        return 0
                    else
                        return -4
                    end
                end
                return 0
            end
        else
            return -1
        end
    else
        return -2
    end
end
