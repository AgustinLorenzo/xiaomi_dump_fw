module ("xiaoqiang.module.XQVASModule", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")

local bit = require("bit")
local uci = require("luci.model.uci").cursor()
local lutil = require("luci.util")
local json = require("json")

local DEFAULTS = {
    ["auto_upgrade"] = {
        ["title"] = "系统自动升级",
        ["desc"] = "在闲暇时自动为您升级路由器系统"
    },
    ["security_page"] = {
        ["title"] = "恶意网址提醒",
        ["desc"] = "防欺诈防盗号防木马，为安全上网保驾护航"
    },
    ["shopping_bar"] = {
        ["title"] = "比价助手",
        ["desc"] = "为您找到最便宜的同类产品，直达所需"
    },
    ["baidu_video_bar"] = {
        ["title"] = "看片助手",
        ["desc"] = "帮你搜罗最热相关视频，支持跨平台收藏"
    }
}

function _rule_merge(t1, t2)
    local t = {}
    for k, v in pairs(t1) do
        if t2[k] then
            t[k] = bit.band(v, t2[k])
        else
            t[k] = v
        end
    end
    return t
end

function _country_code_rule()
    local cc = require("xiaoqiang.XQCountryCode")
    local ccrules = uci:get_all("vas", "countrycode")
    local currentcc = cc.getBDataCountryCode()
    local info = {}
    if ccrules then
        for k, v in pairs(ccrules) do
            if not k:match("^%.") then
                if not info[k] and v:match(currentcc) then
                    info[k] = 1
                else
                    info[k] = 0
                end
            end
        end
    end
    return info
end

FUNCTIONS = {
    ["countrycode"] = _country_code_rule
}

--  1 引导开关为开
--  0 引导开关为关
-- -1 引导开关读取路由本身状态
-- -2 隐藏引导，设置里不显示
-- -3 隐藏引导，设置里不显示，并且在同步时关闭服务
-- -4 隐藏引导，设置里显示
-- -6 隐藏引导，设置里显示，同步时强制开启服务，并且用户无法关闭(虽然开关显示关闭)，同步为其他状态时恢复用户设置状态
function vas_info(conf, settings)
    local info = {}
    if conf ~= "vas" and conf ~= "vas_user" then
        return info
    end
    local services = uci:get_all(conf, "services")
    if services then
        for k, v in pairs(services) do
            if not k:match("^%.") then
                v = tonumber(v)
                if v and v == -1 then
                    local cmd = uci:get("vas", k, "status")
                    if XQFunction.isStrNil(cmd) then
                        v = 1
                    else
                        local va = lutil.exec(cmd)
                        if va then
                            va = lutil.trim(va)
                            v = tonumber(va) or 1
                        else
                            v = 0
                        end
                    end
                end
                if v and v ~= -2 and v ~= -3 and v ~= -4 and v ~= -6 then
                    info[k] = v
                end
                if settings and (v == -4 or v == -6) then
                    info[k] = 0
                end
            end
        end
    end
    return info
end

-- Security center and value added service compatibility issues
function _hot_fix()
    local vas = uci:get("vas", "services", "security_page")
    local vas_user = uci:get("vas_user", "services", "security_page")
    local security = uci:get("security", "common", "malicious_url_firewall")
    local cmd_on = uci:get("vas", "security_page", "on") or ""
    local cmd_off = uci:get("vas", "security_page", "off") or ""
    if vas and vas_user and security then
        vas = tonumber(vas)
        vas_user = tonumber(vas_user)
        security = tonumber(security)
        if vas == -6 and security ~= 1 then
            XQFunction.forkExec(cmd_on)
        elseif vas ~= -6 and security ~= vas_user then
            XQFunction.forkExec(vas_user == 1 and cmd_on or cmd_off)
        end
    end
end

function get_new_vas()
    local info = {}
    local vas = vas_info("vas")
    local vas_user = vas_info("vas_user")
    _hot_fix()
    if not vas then
        return info
    end
    local show
    uci:foreach("vas", "rule",
        function(s)
            local f = FUNCTIONS[s[".name"]]
            if f and type(f) == "function" then
                if show then
                    show = _rule_merge(show, f())
                else
                    show = f()
                end
            end
        end
    )
    for k, v in pairs(vas) do
        if v and not vas_user[k] and (not show or (show and show[k] == 1)) then
            info[k] = v
        end
    end
    return info
end

function get_vas()
    local info = {}
    local vas = vas_info("vas", true)
    local vas_user = vas_info("vas_user")
    if not vas then
        return info
    end
    local show
    uci:foreach("vas", "rule",
        function(s)
            local f = FUNCTIONS[s[".name"]]
            if f and type(f) == "function" then
                if show then
                    show = _rule_merge(show, f())
                else
                    show = f()
                end
            end
        end
    )
    for k, v in pairs(vas) do
        if not show or (show and show[k] == 1) then
            if v and not vas_user[k] then
                info[k] = v
            else
                info[k] = vas_user[k]
            end
        end
    end
    local invalid_page = tonumber(uci:get("vas", "services", "invalid_page") or 0)
    if invalid_page and invalid_page ~= -3 and not info["invalid_page"] and (not show or not show["invalid_page"] or (show["invalid_page"] and show["invalid_page"] == 1)) then
        local enabled = uci:get("http_status_stat", "settings", "enabled") or 0
        info["invalid_page"] = tonumber(enabled)
    end
    return info
end

function get_vas_kv_info()
    local info = {
        ["invalid_page_status"]     = "off",
        ["security_page_status"]    = "off",
        ["gouwudang_status"]        = "off",
        ["baidu_video_bar"]         = "off"
    }
    --local vas = vas_info("vas")
    local vasinfo = vas_info("vas_user")
    for key, value in pairs(vasinfo) do
        if key == "invalid_page" then
            if tonumber(vasinfo.invalid_page) == 1 then
                info.invalid_page_status = "on"
            end
        elseif key == "security_page" then
            if tonumber(vasinfo.security_page) == 1 then
                info.security_page_status = "on"
            end
        elseif key == "shopping_bar" then
            if tonumber(vasinfo.shopping_bar) == 1 then
                info.gouwudang_status = "on"
            end
        elseif key == "baidu_video_bar" then
            if tonumber(vasinfo.baidu_video_bar) == 1 then
                info.baidu_video_bar = "on"
            end
        else
            if tonumber(vasinfo[key]) == 1 then
                info[key] = "on"
            else
                info[key] = "off"
            end
        end
    end
    return info
end

function set_vas(info)
    if not info or type(info) ~= "table" then
        return false
    end
    local cmds = {}
    local vas_user = vas_info("vas_user")
    for k, v in pairs(info) do
        vas_user[k] = v
        local cmd
        local status = uci:get("vas", "services", k) or 0
        if status and tonumber(status) ~= -6 then
            if v == 1 then
                cmd = uci:get("vas", k, "on")
            else
                cmd = uci:get("vas", k, "off")
            end
            if cmd then
                table.insert(cmds, cmd)
            end
        end
    end
    uci:section("vas_user", "settings", "services", vas_user)
    uci:commit("vas_user")
    for _, cmd in ipairs(cmds) do
        XQFunction.forkExec(cmd)
    end
end

--
-- for messagingagent
--
function updateVasConf(info)
    if not info or type(info) ~= "table" then
        return false
    end
    for key, value in pairs(info) do
        if value and type(value) == "table" then
            if value.status then
                local ostatus = tonumber(uci:get("vas", "services", key) or 0)
                -- 如果之前置过-6状态，在恢复正常状态时需要按照用户之前设置的模式生效
                if ostatus == -6 and tonumber(value.status) ~= -6 then
                    local ustatus = uci:get("vas_user", "services", key)
                    if ustatus then
                        if tonumber(ustatus) == 0 then
                            XQFunction.forkExec(value.service.off)
                        elseif tonumber(ustatus) == 1 then
                            XQFunction.forkExec(value.service.on)
                        end
                    end
                -- 之前不是-6状态，现在被强制设置为-6状态时，需要开启该服务
                elseif ostatus ~= -6 and tonumber(value.status) == -6 then
                    XQFunction.forkExec(value.service.on)
                end
                uci:set("vas", "services", key, value.status)
                if tonumber(value.status) == -3 then
                    if value.service and value.service.off then
                        XQFunction.forkExec(value.service.off)
                    end
                end
                -- 从－3状态恢复到正常状态,需要按照用户之前设置生效服务(@PM yy)
                if ostatus == -3 and tonumber(value.status) ~= -3 and tonumber(value.status) ~= -6 then
                    local ustatus = tonumber(uci:get("vas_user", "services", key) or 0)
                    if ustatus then
                        if ustatus == 1 then
                            XQFunction.forkExec(value.service.on)
                        else
                            XQFunction.forkExec(value.service.off)
                        end
                    end
                end
            end
            if value.rules and type(value.rules) == "table" then
                for rkey, rvalue in pairs(value.rules) do
                    if not uci:get_all("vas", rkey) then
                        uci:section("vas", "rule", rkey, {[key] = rvalue})
                    else
                        uci:set("vas", rkey, key, rvalue)
                    end
                end
            end
            if value.service and type(value.service) == "table" then
                uci:section("vas", "service", key, value.service)
            end
        end
    end
    uci:commit("vas")
    return true
end

--- only upload user configrations
function get_vas_info()
    -- local vas = vas_info("vas")
    -- local vas_user = vas_info("vas_user")
    -- for k, v in pairs(vas_user) do
    --     vas[k] = v
    -- end
    return vas_info("vas_user")
end

-- for web
function do_query(lan)
    if not lan then
        return nil
    end
    local httpclient = require("xiaoqiang.util.XQHttpUtil")
    local apiServerDomain = lutil.trim(lutil.exec(XQConfigs.SERVER_CONFIG_ONLINE_URL))
    local URL = "http://"..apiServerDomain.."/data/new_feature_switch/"..lan
    local response = httpclient.httpGetRequest(URL)
    if tonumber(response.code) == 200 and response.res then
        local suc, info = pcall(json.decode, response.res)
        if suc and info then
            return info
        end
    end
    return nil
end

function get_server_vas_details()
    local FILE = "/tmp/vas_details"
    local fs = require("nixio.fs")
    local cc = require("xiaoqiang.XQCountryCode")
    local lan = cc.getCurrentJLan()
    local timestamp = os.time()
    if fs.access(FILE) then
        local content = fs.readfile(FILE)
        local suc, info = pcall(json.decode, content)
        if suc and info and info.res then
            if info.lan == lan and info.timestamp and (tonumber(timestamp) - tonumber(info.timestamp) < 300) then
                return info.res
            end
        end
    end
    local qres = do_query(lan)
    if qres then
        local result = {
            ["res"] = qres,
            ["lan"] = lan,
            ["timestamp"] = timestamp
        }
        fs.writefile(FILE, json.encode(result))
        return qres
    end
    return nil
end

function get_vas_details(keys)
    local fs = require("nixio.fs")
    local details = {}
    if keys and type(keys) == "table" then
        local sdetails = get_server_vas_details()
        for _, key in ipairs(keys) do
            local item = {}
            if fs.access("/www/vas/"..key..".png") then
                item["icon"] = key..".png"
            else
                item["icon"] = "vas_default.png"
            end
            if sdetails and sdetails[key] then
                item["title"] = sdetails[key]["title"]
                item["desc"] = sdetails[key]["desc"]
            else
                if DEFAULTS[key] then
                    item["title"] = DEFAULTS[key]["title"]
                    item["desc"] = DEFAULTS[key]["desc"]
                end
            end
            if item.title and item.desc then
                details[key] = item
            end
        end
    end
    return details
end
