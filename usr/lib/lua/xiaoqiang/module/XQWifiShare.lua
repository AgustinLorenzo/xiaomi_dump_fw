module ("xiaoqiang.module.XQWifiShare", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")
local XQSysUtil = require("xiaoqiang.util.XQSysUtil")
local LuciUtil = require("luci.util")
local XQLog = require("xiaoqiang.XQLog")

local HARDWARE = string.upper(XQSysUtil.getHardware())




function wifi_share_needset(info)
    local needset = 1
    if not info or type(info) ~= "table" then
        return 1
    end
    if not info.guest or not info.share or not info.active then
        return 1
    end

    if info.guest ~= 1 or info.share ~= 1 then
        return 1
    end

    for k,v in ipairs(info.active) do
        if v ~= "user" then
             return 1
        end
    end

    for k,v in ipairs(info.sns) do
        if v == "wifirent_wechat_pay" then
             return 0
        end 
    end

    --XQLog.log(1,"wifishare 0")
    return 1
end

function wifi_share_info()
    local uci = require("luci.model.uci").cursor()
    local wifi = require("xiaoqiang.util.XQWifiUtil")
    local info = {
        ["guest"] = 0,
        ["share"] = 0,
        ["sns"] = {}
    }
    local guest = wifi.getGuestWifi(1)
    info["guest"] = tonumber(guest.status)
    info["data"] = {
        ["ssid"] = guest.ssid,
        ["encryption"] = guest.encryption,
        ["password"] = guest.password
    }
    local disabled = uci:get("wifishare", "global", "disabled") or 1
    if disabled then
        info.share = tonumber(disabled) == 0 and 1 or 0
    end
    -- 只有在未设置过时显示为wifi share模式
    local mark = uci:get("wifishare", "global", "mark")
    if not mark then
        if info.guest == 0 then
            info.share = 1
        end
    end
    info.active = uci:get_list("wifishare", "global", "active") or {}
    info.sns = uci:get_list("wifishare", "global", "sns") or {}
    info.need = wifi_share_needset(info)
    return info
end

function wifi_share_info_web()
    local result = {
        ["need"] = 1
    }
    info=wifi_share_info()
    -- info={}
    result.need = wifi_share_needset(info)
    return result
end

function wifi_share_switch(on)
    local uci = require("luci.model.uci").cursor()
    uci:set("wifishare", "global", "disabled", on == 1 and "0" or "1")
    uci:commit("wifishare")
    if on == 1 then
        XQFunction.forkExec("sleep 4; /usr/sbin/wifishare.sh on")
    else
        XQFunction.forkExec("sleep 4; /usr/sbin/wifishare.sh off")
    end
end

--
-- wps_device_name=XIAOMI_ROUTER_GUEST_DP  显示大众点评图标
-- wps_device_name=XIAOMI_ROUTER_GUEST_MT  显示美团图标
-- wps_device_name=XIAOMI_ROUTER_GUEST_NM  显示糯米图标
-- wps_device_name=XIAOMI_ROUTER_GUEST_WX  显示微信图标
-- wps_device_name=XIAOMI_ROUTER_GUEST     显示访客图标
--
function set_wifi_share(info)
    if not info or type(info) ~= "table" then
        return false
    end
    local uci = require("luci.model.uci").cursor()
    local guest = require("xiaoqiang.module.XQGuestWifi")
    if info.guest and info.share then
        local cmd = "/usr/sbin/wifishare.sh off; /usr/sbin/wifishare.sh on"
        --if info.share == 0 and info.guest == 0 then
        if info.guest == 0 then
            cmd = "/usr/sbin/wifishare.sh off"
        end

        XQLog.log(6,"info.guest " .. info.guest)
        XQLog.log(6,"info.share " .. info.share)

        -- wps device name
        local wps = "XIAOMI_ROUTER_GUEST"
        if info.share == 1 and info.guest == 1 then
            if info["type"] and info["type"] == "user" then
                wps = "XIAOMI_ROUTER_GUEST_WX"
            elseif info["type"] and info["type"] == "business" then
                if info.business and type(info.business) == "table" and #info.business > 0 then
                    for _, business_flag in ipairs(info.business) do
                        if business_flag == "dianping" then
                            wps = "XIAOMI_ROUTER_GUEST_DP"
                        elseif business_flag == "meituan" then
                            wps = "XIAOMI_ROUTER_GUEST_MT"
                        elseif business_flag == "nuomi" then
                            wps = "XIAOMI_ROUTER_GUEST_NM"
                        end
                    end
                end
            end
        end

        -- timeout & dhcp-lease-time
        if info.share ~= 0 then
            if wps == "XIAOMI_ROUTER_GUEST" then
                -- do nothing
            elseif wps == "XIAOMI_ROUTER_GUEST_WX" then
                cmd = cmd .. " 90 86400 2h"
            else
                cmd = cmd .. " 120 7200 2h"
            end
        end

        local function callback(networkrestart)
            if networkrestart then
                -- must sleep a while, between guestwifi.sh open and cmd(wifishare.sh off; wifishare.sh on).
                -- avoid fw3 reload hit wifishare.sh on, will make wifishare_nat rule delete.
                XQFunction.forkExec("sleep 4; /usr/sbin/guestwifi.sh open; sleep 25; "..cmd..";lua /usr/sbin/sync_guest_bssid.lua")
            else
                XQFunction.forkExec("sleep 4; /sbin/wifi >/dev/null 2>/dev/null; sleep 3; "..cmd..";lua /usr/sbin/sync_guest_bssid.lua")
                --XQFunction.forkExec("sleep 4; "..cmd..";lua /usr/sbin/sync_guest_bssid.lua")
            end
        end
        -- set wifi share
        if info.sns and type(info.sns) == "table" and #info.sns > 0 then
            uci:set_list("wifishare", "global", "sns", info.sns)
        end
        -- set business
        if info.business and type(info.business) == "table" and #info.business > 0 then
            uci:set_list("wifishare", "global", "business", info.business)
        end
        -- set type(user/business)
        if info["type"] then
            uci:set("wifishare", "global", "active", info["type"])
        end
        uci:set("wifishare", "global", "mark", "1")
        uci:set("wifishare", "global", "disabled", info.share == 1 and "0" or "1")
        uci:commit("wifishare")
        -- set guest wifi
        local ssid, encryption, key
        if info.data and type(info.data) == "table" then
            ssid = info.data.ssid
            encryption = info.data.encryption
            key = info.data.password
        end
        XQLog.log(6,"ssid " .. ssid)
        XQLog.log(6,"encryption " .. encryption)
        XQLog.log(6,"key " .. key)

        if info.share == 0 and info.guest == 1 and encryption == "none" then
            key = "12345678"
            XQLog.log(6,"set guest not share, key = " .. key)
        end

        if info.share == 1 and info.guest == 1 then
            key = nil
            XQLog.log(6,"set guest and share, key = nil")
        end

        if info.share == 1 and info.guest == 0 then
            key = nil
            XQLog.log(6,"off guest and share, key = nil")
        end

        if info.share == 1 then
            encryption = "none"
        end
        guest.setGuestWifi(1, ssid, encryption, key, 1, info.guest, wps, callback)
    end
    return true
end

-- config device 'D04F7EC0D55D'
--      option disbaled '0'
--      option mac 'D0:4F:7E:C0:D5:5D'
--      option state 'auth'
--      option start_date       2015-06-18
--      option timeout '3600'
--      option sns 'wechat'
--      option guest_user_id '24214185'
--      option extra_payload 'payload test'
function wifi_access(mac, sns, timeout, uid, grant, extra)
    local uci = require("luci.model.uci").cursor()
    if XQFunction.isStrNil(mac) then
        return false
    end


    local mac = XQFunction.macFormat(mac)
    local key = mac:gsub(":", "")
    local info = uci:get_all("wifishare", key)


    if info then
        info["mac"] = mac
        if not XQFunction.isStrNil(sns) then
            info["sns"] = sns
        end
        if not XQFunction.isStrNil(uid) then
            info["guest_user_id"] = uid
        end
        if not XQFunction.isStrNil(extra) then
            info["extra_payload"] = extra
        end
        if grant then
            if grant == 0 then
                info["disabled"] = "1"
            elseif grant == 1 then
                info["disabled"] = "0"
            end
        end
    else
        if XQFunction.isStrNil(sns) or XQFunction.isStrNil(uid) or not grant then
            return false
        end
        info = {
            ["mac"] = mac,
            ["state"] = "auth",
            ["sns"] = sns,
            ["guest_user_id"] = uid,
            ["extra_payload"] = extra,
            ["disabled"] = grant == 1 and "0" or "1"
        }
    end
    uci:section("wifishare", "device", key, info)
    uci:commit("wifishare")
    if grant then
        if grant == 0 then
            if sns ~= "direct_request" then
                os.execute("/usr/sbin/wifishare.sh deny '"..mac.."'")
            end
        elseif grant == 1 then
            XQFunction.forkExec("/usr/sbin/wifishare.sh allow '"..mac .."' '" ..sns .."' '" ..timeout.."'")
        end
    end
    return true
end

-- only for testing
function wifi_share_clearall(blacklist)
    os.execute("/usr/sbin/wifishare.sh clean")
    -- local uci = require("luci.model.uci").cursor()
    -- uci:foreach("wifishare", "device",
    --     function(s)
    --         if s["mac"] then
    --             uci:delete("wifishare", s[".name"])
    --             os.execute("/usr/sbin/wifishare.sh deny "..s["mac"])
    --         end
    --     end
    -- )
    -- uci:foreach("wifishare", "record",
    --     function(r)
    --         if r["mac"] then
    --             uci:delete("wifishare", r[".name"])
    --         end
    --    end
    -- )
    -- if blacklist then
    --     uci:delete("wifishare", "blacklist")
    -- end
    --uci:commit("wifishare")
    --if blacklist then
    --    os.execute("/usr/sbin/wifishare.sh block_apply")
    --end
end

function sns_list(sns)
    local uci = require("luci.model.uci").cursor()
    local info = {}
    if XQFunction.isStrNil(sns) then
        return info
    end
    uci:foreach("wifishare", "device",
        function(s)
            if s["sns"] and s["sns"] == sns then
                if not s["disabled"] or tonumber(s["disabled"]) == 0 then
                    table.insert(info, s["guest_user_id"])
                end
            end
        end
    )
    return info
end

function wifi_share_prepare(mac, rnum)
    local uci = require("luci.model.uci").cursor()
    local result = true
    local key = mac:gsub(":", "").."_RECORD"..rnum
    local record = uci:get_all("wifishare", key)
    local currenttime = tonumber(os.time())
    local interval=90
    local maxtimes=3
    local timeout=1800
    local INTERVAL_SET = {1800, 86400, 3600}
    local MAXTIMES_SET = {3,    3,   3}
    local TIMEOUT_SET  = {90,   600, 180}
    if rnum<0 or rnum>3 then
        result = false
        return result
    end
    interval=INTERVAL_SET[rnum]
    maxtimes=MAXTIMES_SET[rnum]
    timeout=TIMEOUT_SET[rnum]
    if record then
        local check = currenttime - tonumber(record.timestamp)
        if check >= interval or check < 0 then
            record.timestamp = currenttime
            record.count = 1
        else
            local count = tonumber(record.count) + 1
            if count > maxtimes then
                if tonumber(record.count) <= maxtimes then
                    record.timestamp = currenttime
                end
                result = false
            end
            record.count = count
        end
    else
        record = {
            ["mac"] = mac,
            ["timestamp"] = os.time(),
            ["count"] = 1
        }
    end
    uci:section("wifishare", "record", key, record)
    uci:commit("wifishare")
    if result then
        XQFunction.forkExec("/usr/sbin/wifishare.sh prepare "..mac.." "..timeout)
    end
    return result
end

function wifi_share_prepare_status(mac)
    local t = io.popen('/usr/sbin/wifishare.sh pstatus '..mac)
    return t:read("*l")
    -- local t = os.execute("/usr/sbin/wifishare.sh pstatus "..mac)
    -- return t == 0
end

function wifi_share_blacklist()
    local uci = require("luci.model.uci").cursor()
    local block = uci:get_all("wifishare", "blacklist")
    local blacklist = {}
    if block and block["mac"] and type(block["mac"]) == "table" then
        blacklist = block["mac"]
    end
    return blacklist
end

-- t1: table
-- t2: table
-- opt: +/- (t1 + t2)/(t1 - t2)
function merge(t1, t2, opt)
    if not t1 and not t2 then
        return nil
    end
    if opt == "+" then
        if t1 then
            if not t2 then
                return t1
            end
            local d = {}
            for _, v in ipairs(t1) do
                d[v] = true
            end
            for _, v in ipairs(t2) do
                if not d[v] then
                    table.insert(t1, v)
                end
            end
            return t1
        else
            if not t2 then
                return nil
            else
                return t2
            end
        end
    elseif opt == "-" then
        if t1 then
            if not t2 then
                return t1
            end
            local s = {}
            local d = {}
            for _, v in ipairs(t2) do
                d[v] = true
            end
            for _, v in ipairs(t1) do
                if not d[v] then
                    table.insert(s, v)
                end
            end
            return s
        end
    end
    return nil
end

-- macs table<mac>
-- option "+"/"-" (add/delete)
function wifi_share_blacklist_edit(macs, option)
    local uci = require("luci.model.uci").cursor()
    local block = uci:get_all("wifishare", "blacklist")
    local blist
    if block then
        blist = block["mac"]
    end
    local mergelist = merge(blist, macs, option)
    if block then
        if mergelist and #mergelist > 0 then
            block["mac"] = mergelist
            uci:section("wifishare", "block", "blacklist", block)
        else
            uci:delete("wifishare", "blacklist", "mac")
        end
        uci:commit("wifishare")
    else
        if mergelist and #mergelist > 0 then
            uci:section("wifishare", "block", "blacklist", {["mac"] = mergelist})
            uci:commit("wifishare")
        end
    end
    if HARDWARE:match("^R1C") then
        XQFunction.forkExec("sleep 2; /usr/sbin/wifishare.sh block_apply")
    else
        os.execute("/usr/sbin/wifishare.sh block_apply")
    end
end

--
-- 查询授权状态
--
-- @return 0/1/2 处理中/成功/失败
function authorization_status(mac)
    local status = 0
    if not mac then
        return status
    end
    local uci = require("luci.model.uci").cursor()
    local key = mac:gsub(":", "")
    local record = uci:get_all("wifishare", key)
    if record then
        if record.sns and record.sns == "direct_request" then
            if record.disabled and tonumber(record.disabled) == 1 then
                status = 2
            else
                status = 1
            end
        end
    else
        local blacklist = uci:get_list("wifishare", "blacklist", "mac")
        if blacklist and type(blacklist) == "table" then
            for _, lmac in ipairs(blacklist) do
                if mac == lmac then
                    status = 2
                    break
                end
            end
        end
    end
    return status
end

--
-- 检查重复(针对允许上网之后发Push)
-- @return true/false 属于重复请求/不属于重复请求
--
function check_repeat_request(mac)
    local uci = require("luci.model.uci").cursor()
    if not mac then
        return false
    end
    local key = mac:gsub(":", "")
    local record = uci:get_all("wifishare", key)
    if record then
        if record.datestop then
            local current = tostring(os.date("%Y-%m-%d")) .. "T" .. tostring(os.date("%X"))
            if current <= record.datestop then
                return true
            else
                return false
            end
        else
            return true
        end
    else
        return false
    end
end
