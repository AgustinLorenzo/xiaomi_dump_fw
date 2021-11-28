module ("xiaoqiang.module.XQParentControl", package.seeall)

local XQFunction    = require("xiaoqiang.common.XQFunction")
local XQConfigs     = require("xiaoqiang.common.XQConfigs")

local bit   = require("bit")
local math  = require("math")
local fs    = require("nixio.fs")

local uci   = require("luci.model.uci").cursor()
local lutil = require("luci.util")
local datatypes = require("luci.cbi.datatypes")

local LIMIT = 5  -- < 64

local WEEKDAYS = {
    ["Mon"] = 1,
    ["Tue"] = 2,
    ["Wed"] = 3,
    ["Thu"] = 4,
    ["Fri"] = 5,
    ["Sat"] = 6,
    ["Sun"] = 7
}

local WEEK = {
    "Mon",
    "Tue",
    "Wed",
    "Thu",
    "Fri",
    "Sat",
    "Sun"
}

function get_global_info()
    local global = uci:get_all("parentalctl", "global")
    local info = {
        ["on"] = 1
    }
    if global then
        if global.disabled and tonumber(global.disabled) == 1 then
            info.on = 0
        end
    end
    return info
end

function get_macfilter_wan(mac)
    local wanper = true
    local data = lutil.exec("/usr/sbin/sysapi macfilter get | grep \""..string.lower(mac).."\"")
    if data then
        data = lutil.trim(data)
        data = data..";"
        local wan = data:match('wan=(%S-);')
        if wan and wan ~= "yes" then
            wanper = false
        end
    end
    return wanper
end

-- @param wan:true/false
-- true, macfilter wan=yes
-- false, macfilter wan=no
function macfilter_wan_changed(mac, wan)
    local XQSync = require("xiaoqiang.util.XQSynchrodata")
    local key = mac:gsub(":", "")
    summary = {
        ["mac"] = mac,
        ["disabled"] = "0",
        ["mark"] = "1",
        ["mode"] = wan and "none" or "limited"
    }
    uci:section("parentalctl", "summary", key, summary)
    uci:commit("parentalctl")
    apply()
    -- local key = mac:gsub(":", "")
    -- local fast = uci:get_all("parentalctl", key)
    -- if fast then
    --     uci:set("parentalctl", "key", "disabled", wan and 1 or 0)
    -- else
    --     local section = {
    --         ["mac"] = mac,
    --         ["weekdays"] = "Mon Tue Wed Thu Fri Sat Sun",
    --         ["disabled"] = wan and 1 or 0,
    --         ["time_seg"] = "00:00-23:59"
    --     }
    --     uci:section("parentalctl", "device", key, section)
    -- end
    -- if not wan then
    --     uci:foreach("parentalctl", "device",
    --         function(s)
    --             if s[".name"]:match("^"..key.."_") then
    --                 uci:set("parentalctl", s[".name"], "disabled", "1")
    --             end
    --         end
    --     )
    -- end
    -- uci:commit("parentalctl")
    -- apply()
    -- local count = 0
    -- local mark = 0
    -- uci:foreach("parentalctl", "device",
    --     function(s)
    --         count = count + 1
    --         if s[".name"]:match("^"..key) then
    --             if wan then
    --                 uci:set("parentalctl", s[".name"], "disabled", "1")
    --             else
    --                 if s.weekdays and s.time_seg and s.time_seg == "00:00-23:59" then
    --                     local weekdays = lutil.split(s.weekdays, " ")
    --                     if #weekdays == 7 then
    --                         mark = 1
    --                         uci:set("parentalctl", s[".name"], "disabled", "0")
    --                     end
    --                 end
    --                 if mark == 0 then
    --                     if tonumber(s.disabled) == 1 then
    --                         mark = s[".name"]
    --                     end
    --                 end
    --                 if count == 5 and mark == 0 then
    --                     mark = s[".name"]
    --                 end
    --             end
    --         end
    --     end
    -- )
    -- if not wan then
    --     local section = {
    --         ["mac"] = mac,
    --         ["weekdays"] = "Mon Tue Wed Thu Fri Sat Sun",
    --         ["disabled"] =  0,
    --         ["time_seg"] = "00:00-23:59"
    --     }
    --     if mark == 0 then
    --         local key = _generate_key(mac)
    --         uci:section("parentalctl", "device", key, section)
    --     elseif mark == 1 then
    --         -- do nothing.
    --     else
    --         uci:delete("parentalctl", mark)
    --         uci:section("parentalctl", "device", mark, section)
    --     end
    -- end
    -- uci:commit("parentalctl")
    -- apply()
end

-- Compatible sysapi/macfilter function
-- function parentctl_rule_changed(mac)
--     local key = mac:gsub(":", "")
--     local wanper = get_macfilter_wan(mac)
--     local rule7 = false
--     uci:foreach("parentalctl", "device",
--         function(s)
--             if s[".name"]:match("^"..key.."_") and s.weekdays and s.time_seg and s.time_seg == "00:00-23:59" then
--                 local weekdays = lutil.split(s.weekdays, " ")
--                 if #weekdays == 7 then
--                     if tonumber(s.disabled) == 0 then
--                         rule7 = true
--                     end
--                 end
--             end
--         end
--     )
--     if datatypes.macaddr(mac) then
--         if rule7 and wanper then
--             os.execute("/usr/sbin/sysapi macfilter set mac="..mac.." wan=no; /usr/sbin/sysapi macfilter commit")
--         elseif not rule7 and not wanper then
--             os.execute("/usr/sbin/sysapi macfilter set mac="..mac.." wan=yes; /usr/sbin/sysapi macfilter commit")
--         end
--     end
-- end

function _generate_key(mac)
    local key = mac:gsub(":", "")
    local flag = math.pow(2, LIMIT) - 1
    uci:foreach("parentalctl", "device",
        function(s)
            if s[".name"]:match("^"..key.."_") then
                local ind = s[".name"]:gsub(key.."_", "")
                local ind = tonumber(ind)
                if ind and ind <= LIMIT then
                    flag = bit.bxor(flag, math.pow(2, ind - 1))
                end
            end
        end
    )
    for i = 1, LIMIT do
        if bit.band(flag, math.pow(2, i - 1)) > 0 then
            return key.."_"..tostring(i)
        end
    end
    return nil
end

function _parse_frequency(frequency, timeseg)
    local days = {}
    for _, day in ipairs(frequency) do
        if tonumber(day) == 0 then
            days = nil
            break
        end
        local day = WEEK[tonumber(day)]
        if day then
            table.insert(days, day)
        end
    end
    local start, stop
    if days then
        days = table.concat(days, " ")
    else
        start = os.date("%Y-%m-%d")
        stop = os.date("%Y-%m-%d", os.time() + 86400)
        if not XQFunction.isStrNil(timeseg) then
            local ctime = os.date("%X"):gsub(":%d+$", "")
            local entseg = timeseg:match("[%d:]+%-([%d:]+)")
            if ctime > entseg then
                start = os.date("%Y-%m-%d", os.time() + 86400)
                stop = os.date("%Y-%m-%d", os.time() + 2*86400)
            end
        end
    end
    return days, start, stop
end

function apply(async)
    if async then
        XQFunction.forkExec("/usr/sbin/parentalctl.sh 2>/dev/null >/dev/null")
    else
        os.execute("/usr/sbin/parentalctl.sh 2>/dev/null >/dev/null")
    end
end

-- enable: 0/1 关/开
-- mode: none/limited/time 正常/立即断网/定时断网
function get_device_mode_info(mac)
    if XQFunction.isStrNil(mac) or not datatypes.macaddr(mac) then
        return nil
    else
        mac = XQFunction.macFormat(mac)
    end
    local wanper = get_macfilter_wan(mac)
    local info = {}
    local key = mac:gsub(":", "")
    local summary = uci:get_all("parentalctl", key)
    if summary and tonumber(summary.mark) and tonumber(summary.mark) == 1 then
        info["enable"] = tonumber(summary.disabled) == 0 and 1 or 0
        info["mode"] = summary.mode or "time"
        -- in case of downgrade
        if not wanper then
            info["mode"] = "limited"
            info["enable"] = 1
            uci:set("parentalctl", key, "disabled", "0")
            uci:set("parentalctl", key, "mode", "limited")
            uci:commit("parentalctl")
        end
    else
        info["enable"] = 1
        if wanper then
            info["mode"] = "none"
        else
            info["mode"] = "limited"
        end
        local section = {
            ["disabled"] = "0",
            ["mode"] = info.mode,
            ["mac"] = mac
        }
        -- check old cfg
        local rules = parentctl_rules({[mac] = 1})
        if rules and rules[mac] then
            if rules[mac].enabled > 0 then
                info["mode"] = "time"
                os.execute("/usr/sbin/sysapi macfilter set mac="..mac.." wan=yes; /usr/sbin/sysapi macfilter commit")
            end
        end
        if summary and not summary.mark then
            uci:delete("parentalctl", key)
            uci:commit("parentalctl")
        end
        -- uci:section("parentalctl", "summary", key, section)
        -- uci:commit("parentalctl")
    end
    -- 网址黑白名单功能
    local url_filter = get_parentctl_url_filter(mac)
    info.urlfilter = {
        ["mode"] = url_filter.mode,
        ["count"] = url_filter.count
    }
    return info
end

-- open: 0/1 关/开
-- mode: none/limited/time 正常/立即断网/定时断网
function set_device_mode_info(mac, open, mode)
    if XQFunction.isStrNil(mac) or not datatypes.macaddr(mac) then
        return nil
    else
        mac = XQFunction.macFormat(mac)
    end
    local XQSync = require("xiaoqiang.util.XQSynchrodata")
    local info = {}
    local key = mac:gsub(":", "")
    local summary = uci:get_all("parentalctl", key)
    if summary then
        if open then
            summary["disabled"] = open == 1 and "0" or "1"
        end
        if mode then
            summary["mode"] = mode
        end
    else
        summary = {
            ["disabled"] = "0",
            ["mode"] = "time",
            ["mac"] = mac
        }
        if open then
            summary["disabled"] = open == 1 and "0" or "1"
        end
        if mode then
            summary["mode"] = mode
        end
    end
    summary["mark"] = 1
    info["enable"] = tonumber(summary.disabled) == 0 and 1 or 0
    info["mode"] = summary.mode
    if info.mode == "limited" then
        if info.enable == 1 then
            os.execute("/usr/sbin/sysapi macfilter set mac="..mac.." wan=no; /usr/sbin/sysapi macfilter commit")
        else
            os.execute("/usr/sbin/sysapi macfilter set mac="..mac.." wan=yes; /usr/sbin/sysapi macfilter commit")
        end
    else
        local wanper = get_macfilter_wan(mac)
        if not wanper then
            os.execute("/usr/sbin/sysapi macfilter set mac="..mac.." wan=yes; /usr/sbin/sysapi macfilter commit")
        end
    end
    uci:section("parentalctl", "summary", key, summary)
    uci:commit("parentalctl")
    XQSync.syncDeviceInfo({["mac"] = mac})
    return info
end

function get_device_info(mac)
    if XQFunction.isStrNil(mac) or not datatypes.macaddr(mac) then
        return nil
    else
        mac = XQFunction.macFormat(mac)
    end
    local info = {}
    local rules = {}
    local key = mac:gsub(":", "")
    local ctime = os.date("%X"):gsub(":%d+$", "")
    local cday = os.date("%Y-%m-%d")
    -- local fast = uci:get_all("parentalctl", key)
    -- if fast then
    --     info["fastswitch"] = tonumber(fast.disabled) == 1 and 0 or 1
    -- else
    --     local wanper = get_macfilter_wan(mac)
    --     local section = {
    --         ["mac"] = mac,
    --         ["weekdays"] = "Mon Tue Wed Thu Fri Sat Sun",
    --         ["disabled"] = wanper and 1 or 0,
    --         ["time_seg"] = "00:00-23:59"
    --     }
    --     info["fastswitch"] = wanper and 0 or 1
    --     uci:section("parentalctl", "device", key, section)
    --     uci:commit("parentalctl")
    -- end
    uci:foreach("parentalctl", "device",
        function(s)
            if s[".name"]:match("^"..key.."_") then
                local item = {
                    ["id"] = s[".name"],
                    ["mac"] = s.mac,
                    ["enable"] = tonumber(s.disabled) == 1 and 0 or 1
                }
                local entseg
                if s.time_seg then
                    entseg = s.time_seg:match("[%d:]+%-([%d:]+)")
                end
                if s.start_date and s.stop_date then
                    item["frequency"] = {0}
                    if item.enable == 1 and (cday > s.start_date or (cday == s.start_date and ctime > entseg) or not entseg) then
                        item["enable"] = 0
                        uci:set("parentalctl", s[".name"], "disabled", 1)
                    end
                end
                if s.weekdays then
                    local fre = {}
                    local weekdays = lutil.split(s.weekdays, " ")
                    for _, day in ipairs(weekdays) do
                        table.insert(fre, WEEKDAYS[day])
                    end
                    item["frequency"] = fre
                end
                if s.time_seg then
                    local from, to = s.time_seg:match("([%d:]+)%-([%d:]+)")
                    if from and to then
                        item["timeseg"] = {
                            ["from"] = from,
                            ["to"] = to
                        }
                    end
                end
                table.insert(rules, item)
            end
        end
    )
    info["rules"] = rules
    return info
    -- local mark = uci:get_all("parentalctl", "mark")
    -- if not mark then
    --     mark = false
    --     uci:section("parentalctl", "record", "mark", {[key] = 1})
    -- else
    --     if mark[key] then
    --         mark = true
    --     else
    --         mark = false
    --         uci:set("parentalctl", "mark", key, 1)
    --     end
    -- end
    -- uci:commit("parentalctl")
    -- if #info > 0 then
    --     return info
    -- else
    --     if not mark then
    --         local wanper = get_macfilter_wan(mac)
    --         local key = _generate_key(mac)
    --         local section = {
    --             ["mac"] = mac,
    --             ["weekdays"] = "Mon Tue Wed Thu Fri Sat Sun",
    --             ["disabled"] = wanper and 1 or 0,
    --             ["time_seg"] = "00:00-23:59"
    --         }
    --         uci:section("parentalctl", "device", key, section)
    --         uci:commit("parentalctl")
    --         local inf = {
    --             ["id"] = key,
    --             ["mac"] = mac,
    --             ["frequency"] = {1,2,3,4,5,6,7},
    --             ["enable"] = wanper and 0 or 1,
    --             ["timeseg"] = {
    --                 ["from"] = "00:00",
    --                 ["to"] = "23:59"
    --             }
    --         }
    --         table.insert(info, inf)
    --         return info
    --     else
    --         return nil
    --     end
    -- end
end

-- function fast_switch(mac, enable)
--     if XQFunction.isStrNil(mac) or not datatypes.macaddr(mac) then
--         return false
--     else
--         mac = XQFunction.macFormat(mac)
--     end
--     local key = mac:gsub(":", "")
--     local fast = uci:get_all("parentalctl", key)
--     if fast then
--         uci:set("parentalctl", key, "disabled", enable and 0 or 1)
--     else
--         local section = {
--             ["mac"] = mac,
--             ["weekdays"] = "Mon Tue Wed Thu Fri Sat Sun",
--             ["disabled"] = enable and 0 or 1,
--             ["time_seg"] = "00:00-23:59"
--         }
--         uci:section("parentalctl", "device", key, section)
--     end
--     uci:commit("parentalctl")
--     if enable then
--         os.execute("/usr/sbin/sysapi macfilter set mac="..mac.." wan=no; /usr/sbin/sysapi macfilter commit")
--     else
--         os.execute("/usr/sbin/sysapi macfilter set mac="..mac.." wan=yes; /usr/sbin/sysapi macfilter commit")
--     end
--     return true
-- end

function add_device_info(mac, enable, frequency, timeseg)
    local XQSync = require("xiaoqiang.util.XQSynchrodata")
    if XQFunction.isStrNil(mac)
        or not frequency or type(frequency) ~= "table"
        or XQFunction.isStrNil(timeseg)
        or not timeseg:match("[%d:]+%-[%d:]+") then
        return false
    else
        mac = XQFunction.macFormat(mac)
    end
    local key = _generate_key(mac)
    if not key then
        return false
    end
    local days, start, stop = _parse_frequency(frequency)
    local section = {
        ["mac"] = mac,
        ["weekdays"] = days,
        ["start_date"] = start,
        ["stop_date"] = stop,
        ["disabled"] = (enable == 1) and 0 or 1,
        ["time_seg"] = timeseg
    }
    uci:section("parentalctl", "device", key, section)
    uci:commit("parentalctl")
    -- parentctl_rule_changed(mac)
    XQSync.syncDeviceInfo({["mac"] = mac})
    return key
end

function update_device_info(id, mac, enable, frequency, timeseg)
    local XQSync = require("xiaoqiang.util.XQSynchrodata")
    if XQFunction.isStrNil(id) then
        return false
    end
    local section = uci:get_all("parentalctl", id)
    if not section then
        return false
    end
    if enable then
        section["disabled"] = (enable == 1) and 0 or 1
    end
    if frequency then
        local days, start, stop = _parse_frequency(frequency, timeseg or section.time_seg)
        if days then
            section["weekdays"] = days
            section["start_date"] = nil
            section["stop_date"] = nil
            uci:delete("parentalctl", id, "start_date")
            uci:delete("parentalctl", id, "stop_date")
        end
        if start then
            section["start_date"] = start
        end
        if stop then
            section["stop_date"] = stop
        end
        if start or stop then
            section["weekdays"] = nil
            uci:delete("parentalctl", id, "weekdays")
        end
    else
        if enable and enable == 1 and section.start_date and section.stop_date then
            local days, start, stop = _parse_frequency({0}, timeseg or section.time_seg)
            if start then
                section["start_date"] = start
            end
            if stop then
                section["stop_date"] = stop
            end
        end
    end
    if timeseg and timeseg:match("[%d:]+%-[%d:]+") then
        section["time_seg"] = timeseg
    end
    uci:section("parentalctl", "device", id, section)
    uci:commit("parentalctl")
    -- parentctl_rule_changed(mac)
    -- comment: Do not change wan mode when update time config on APP!
    --if not get_macfilter_wan(mac) then
        --os.execute("/usr/sbin/sysapi macfilter set mac="..mac.." wan=yes; /usr/sbin/sysapi macfilter commit")
    --end
    XQSync.syncDeviceInfo({["mac"] = mac})
    return true
end

function delete_device_info(id)
    if XQFunction.isStrNil(id) then
        return false
    end
    local XQSync = require("xiaoqiang.util.XQSynchrodata")
    local sec = uci:get_all("parentalctl", id)
    local mac
    if sec then
        mac = sec.mac
    end
    uci:delete("parentalctl", id)
    uci:commit("parentalctl")
    -- if mac then
    --     parentctl_rule_changed(mac)
    -- end
    XQSync.syncDeviceInfo({["mac"] = mac})
    return true
end

-- macs: nil or {["XX:XX:XX:XX:XX:XX"] = 1,...}
function parentctl_rules(macs)
    local rules = {}
    uci:foreach("parentalctl", "device",
        function(s)
            if s.mac and s[".name"]:match("_") then
                if not macs or (macs and macs[s.mac]) then
                    local rule = rules[s.mac]
                    if rule then
                        rule.total = rule.total + 1
                        if s.disabled and tonumber(s.disabled) == 0 then
                            rule.enabled = rule.enabled + 1
                        end
                    else
                        rule = {
                            ["total"] = 1,
                            ["enabled"] = 0
                        }
                        if s.disabled and tonumber(s.disabled) == 0 then
                            rule.enabled = 1
                        end
                    end
                    rules[s.mac] = rule
                end
            end
        end
    )
    if macs then
        for mac, value in pairs(macs) do
            if not rules[mac] then
                rules[mac] = {
                    ["total"] = 0,
                    ["enabled"] = 0
                }
            end
        end
    end
    return rules
end

-- macs: {["XX:XX:XX:XX:XX:XX"] = 1,...}
function netacctl_status(macs)
    local device = require("xiaoqiang.util.XQDeviceUtil")
    local status = {}
    local macFilterDict = device.getMacfilterInfoDict()
    if macs and type(macs) == "table" then
        for mac, v in pairs(macs) do
            local wanper = true
            if macFilterDict[mac] then
                wanper = macFilterDict[mac]["wan"]
            end
            local info = {}
            local key = mac:gsub(":", "")
            local summary = uci:get_all("parentalctl", key)
            if summary and tonumber(summary.mark) and tonumber(summary.mark) == 1 then
                info["enable"] = tonumber(summary.disabled) == 0 and 1 or 0
                info["mode"] = summary.mode or "time"
                -- in case of downgrade
                if not wanper then
                    info["mode"] = "limited"
                    info["enable"] = 1
                end
            else
                info["enable"] = 1
                if wanper then
                    info["mode"] = "none"
                else
                    info["mode"] = "limited"
                end
                local section = {
                    ["disabled"] = "0",
                    ["mode"] = info.mode,
                    ["mac"] = mac
                }
                -- check old cfg
                local rules = parentctl_rules({[mac] = 1})
                if rules and rules[mac] then
                    if rules[mac].enabled > 0 then
                        info["mode"] = "time"
                    end
                end
            end
            status[mac] = info
        end
    end
    return status
end

function get_url_info(path)
    if XQFunction.isStrNil(path) then
        return nil
    end
    if not fs.access(path) then
        return nil
    end
    local f = io.open(path, "r")
    local urls = {}
    if f then
        for line in f:lines() do
            if not XQFunction.isStrNil(line) then
                local url = line:match("(%S+)%s%S+")
                table.insert(urls, url)
            end
        end
    end
    return urls
end

function set_url_info(path, data)
    if XQFunction.isStrNil(path) then
        return false
    end
    if data and type(data) == "table" then
        local f = io.open(path, "w")
        for _, line in ipairs(data) do
            if not XQFunction.isStrNil(line) then
                local url = line:gsub("http://", "")
                url = url:gsub("^www.", "")
                if not datatypes.ipaddr(url) then
                    if not url:match("^%.") then
                        url = "."..url
                    end
                end
                f:write(line.." "..url.."\n")
            end
        end
        f:close()
    end
    return true
end

-- 网址黑白名单功能
function get_parentctl_url_filter(mac)
    if XQFunction.isStrNil(mac) or not datatypes.macaddr(mac) then
        return nil
    else
        mac = XQFunction.macFormat(mac)
    end
    local info = {
        ["mode"] = "none",
        ["count"] = 0
    }
    local key = mac:gsub(":", "").."_RULE"
    local rule = uci:get_all("parentalctl", key)
    if rule then
        info.mode = rule.mode or "none"
        if tonumber(rule.disabled) == 0 then
            local hostfile = rule.hostfile
            if hostfile and type(hostfile) == "table" and #hostfile > 0 then
                local path = hostfile[1]
                local urls = get_url_info(path) or {}
                info.count = #urls
                info.urls = urls
            end
        end
    end
    return info
end

function get_parentctl_url_list(mac, mode)
    local hostfile
    if mode == "white" then
        hostfile = "/etc/parentalctl/"..mac:gsub(":", "").."_WHITE.url"
    elseif mode == "black" then
        hostfile = "/etc/parentalctl/"..mac:gsub(":", "").."_BLACK.url"
    end
    if hostfile then
        return get_url_info(hostfile) or {}
    end
    return {}
end

-- mode: none/black/white
function set_parentctl_url_filter(mac, mode)
    local XQSync = require("xiaoqiang.util.XQSynchrodata")
    if XQFunction.isStrNil(mac) or not datatypes.macaddr(mac) or XQFunction.isStrNil(mode) then
        return nil
    else
        mac = XQFunction.macFormat(mac)
    end
    local key = mac:gsub(":", "").."_RULE"
    local rule = uci:get_all("parentalctl", key)
    if not rule then
        rule = {}
    end
    rule.mac = mac
    local hostfile
    if mode == "white" then
        hostfile = "/etc/parentalctl/"..mac:gsub(":", "").."_WHITE.url"
    elseif mode == "black" then
        hostfile = "/etc/parentalctl/"..mac:gsub(":", "").."_BLACK.url"
    end
    rule.disabled = mode ~= "none" and "0" or "1"
    if hostfile then
        rule.hostfile = {hostfile}
    end
    rule.mode = mode
    uci:section("parentalctl", "rule", key, rule)
    uci:commit("parentalctl")
    XQSync.syncDeviceInfo({["mac"] = mac})
end

--
-- opt:  0/1/2 增加/删除/更新
-- mode: black/white 黑名单/白名单
-- url:  域名 opt==2时需要传旧的url作为key
-- newurl: opt==2时需要传新的url
--
function edit_parentctl_url_list(mac, opt, mode, url, newurl)
    local XQSync = require("xiaoqiang.util.XQSynchrodata")
    if XQFunction.isStrNil(mac) or not datatypes.macaddr(mac) or not opt or not mode or not url then
        return false
    else
        mac = XQFunction.macFormat(mac)
    end
    -- 新增了none模式
    if mode == "none" then
        return false
    end
    local hostfile = "/etc/parentalctl/"..mac:gsub(":", "").."_BLACK.url"
    if mode == "white" then
        hostfile = "/etc/parentalctl/"..mac:gsub(":", "").."_WHITE.url"
    end
    local urls = get_url_info(hostfile)
    if url and type(url) == "table" and #url > 1 and opt == 1 then
        local dict = {}
        local rms = {}
        for _, v in ipairs(url) do
            if not XQFunction.isStrNil(v) then
                dict[v] = true
            end
        end
        if urls then
            for i=#urls, 1, -1 do
                if dict[urls[i]] then
                    table.remove(urls, i)
                end
            end
            set_url_info(hostfile, urls)
            return true
        end
    end
    if urls then
        local exist
        for index, line in ipairs(urls) do
            if line == url then
                exist = index
            end
        end
        if opt == 0 then
            if not exist then
                table.insert(urls, url)
            end
        elseif opt == 1 then
            if exist then
                table.remove(urls, exist)
            end
        elseif opt == 2 and newurl then
            if exist then
                urls[exist] = newurl
            else
                table.insert(urls, newurl)
            end
        end
    else
        urls = {}
        if opt == 0 then
            urls = {url}
        end
        if opt == 2 and newurl then
            urls = {newurl}
        end
    end
    set_url_info(hostfile, urls)
    XQSync.syncDeviceInfo({["mac"] = mac})
    return true
end

-- for XQSynchrodata module
function _get_file_line_count(path)
    if XQFunction.isStrNil(path) then
        return 0
    end
    if not fs.access(path) then
        return 0
    end
    local cmd = "wc -l \""..XQFunction._cmdformat(path).."\" | awk '{print $1}'"
    return tonumber(lutil.trim(lutil.exec(cmd)))
end

-- macs: {["XX:XX:XX:XX:XX:XX"] = 1,...}
function get_urlfilter_info(macs)
    local info = {}
    local rules = {}
    if macs and type(macs) == "table" then
        uci:foreach("parentalctl", "rule",
            function(s)
                if s.mac then
                    local mode = s.mode
                    local hostfile = s.hostfile
                    if hostfile and type(hostfile) == "table" and #hostfile == 1 then
                        hostfile = hostfile[1]
                    else
                        hostfile = nil
                    end
                    if s.disabled and tonumber(s.disabled) == 1 then
                        mode = "none"
                    end
                    rules[s.mac] = {
                        ["count"] = _get_file_line_count(hostfile),
                        ["mode"] = mode
                    }
                end
            end
        )
        for mac, v in pairs(macs) do
            info[mac] = rules[mac] or {
                ["count"] = 0,
                ["mode"] = "none"
            }
        end
    end
    return info
end
