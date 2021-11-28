module ("xiaoqiang.module.XQDDNS", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")

--- noip noip.com
--- oray 花生壳
local SERVICES = {
    ["noip"] = {
        ["service_name"] = "no-ip.com",
        ["ip_url"] = "http://[USERNAME]:[PASSWORD]@dynupdate.no-ip.com/nic/update?hostname=[DOMAIN]&myip=[IP]"
    },
    ["oray"] = {
        ["service_name"] = "oray.com",
        ["ip_url"] = "http://[USERNAME]:[PASSWORD]@ddns.oray.com:80/ph/update?hostname=[DOMAIN]&myip=[IP]"
    },
    ["pubyun"] = {
        ["service_name"] = "3322.org",
        ["ip_url"] = "http://[USERNAME]:[PASSWORD]@members.3322.net/dyndns/update?hostname=[DOMAIN]&myip=[IP]"
    },
    ["dyndnsorg"] = {
        ["service_name"] = "dyndns.org",
        ["ip_url"] = "https://[USERNAME]:[PASSWORD]@members.dyndns.org/nic/update?wildcard=ON&hostname=[DOMAIN]&myip=[IP]"
    },
    ["dyndnsfr"] = {
        ["service_name"] = "dyndns.fr",
        ["ip_url"] = "http://[DOMAIN]:[PASSWORD]@dyndns.dyndns.fr/update.php?hostname=[DOMAIN]&myip=[IP]"
    },
    ["dyndnspro"] = {
        ["service_name"] = "dyndnspro.com",
        ["ip_url"] = "http://[DOMAIN]:[PASSWORD]@dyndns.dyndnspro.com/update.php?hostname=[DOMAIN]&myip=[IP]"
    },
    ["dynamicdomain"] = {
        ["service_name"] = "dynamicdomain.net",
        ["ip_url"] = "http://[DOMAIN]:[PASSWORD]@dyndns.dynamicdomain.net/update.php?hostname=[DOMAIN]&myip=[IP]"
    },
    ["dyndnsit"] = {
        ["service_name"] = "dyndns.it",
        ["ip_url"] = "http://[USERNAME]:[PASSWORD]@dyndns.it/nic/update?hostname=[DOMAIN]&myip=[IP]"
    },
    ["duckdns"] = {
        ["service_name"] = "duckdns.org",
        ["ip_url"] = "http://www.duckdns.org/update?domains=[DOMAIN]&token=[PASSWORD]&ip=[IP]"
    },
    ["systemns"] = {
        ["service_name"] = "system-ns.com",
        ["ip_url"] = "http://system-ns.com/api?type=dynamic&domain=[DOMAIN]&command=set&token=[PASSWORD]&ip=[IP]"
    }
}

local ERROR = {
    ["oray"] = {
        ["notfqdn"]     = _("未有激活花生壳的域名"),
        ["badauth"]     = _("身份认证出错，请检查用户名和密码, 或者编码方式出错。"),
        ["nohost"]      = _("域名不存在或未激活花生壳"),
        ["abuse"]       = _("请求失败，频繁请求或验证失败时会出现"),
        ["!donator"]    = _("必须是付费用户才能使用此功能"),
        ["911"]         = _("花生壳系统错误")
    },
    ["pubyun"] = {
        ["badauth"]     = _("身份认证出错，请检查用户名和密码, 或者编码方式出错。"),
        ["badsys"]      = _("该域名不是动态域名，可能是其他类型的域名（智能域名、静态域名、域名转向、子域名）。"),
        ["badagent"]    = _("由于发送大量垃圾数据，客户端名称被系统封杀。"),
        ["notfqdn"]     = _("没有提供域名参数，必须提供一个在公云注册的动态域名域名。"),
        ["nohost"]      = _("域名不存在，请检查域名是否填写正确。"),
        ["!donator"]    = _("必须是收费用户，才能使用 offline 离线功能。"),
        ["!yours"]      = _("该域名存在，但是不是该用户所有。"),
        ["!active"]     = _("该域名被系统关闭，请联系公云客服人员。"),
        ["abuse"]       = _("必须是付费用户才能使用此功能"),
        ["dnserr"]      = _("DNS 服务器更新失败。"),
        ["interror"]    = _("服务器内部严重错误，比如数据库出错或者DNS服务器出错。")
    },
    ["dyndnsorg"] = {
        ["badauth"]     = "The username and password pair do not match a real user.",
        ["numhost"]     = "Too many hosts (more than 20) specified in an update. Also returned if trying to update a round robin (which is not allowed).",
        ["good 127.0.0.1"] = "This answer indicates good update only when 127.0.0.1 address is requested by update. In all other cases it warns user that request was ignored because of agent that does not follow our specifications.",
        ["notfqdn"]     = "The hostname specified is not a fully-qualified domain name (not in the form hostname.dyndns.org or domain.com).",
        ["nohost"]      = "The hostname specified does not exist in this user account (or is not in the service specified in the system parameter).",
        ["abuse"]       = "The hostname specified is blocked for update abuse.",
        ["dnserr"]      = "DNS error encountered",
        ["911"]         = "There is a problem or scheduled maintenance on our side."
    },
    ["noip"] = {
        ["badagent"]    = "Client disabled. Client should exit and not perform any more updates without user intervention.",
        ["badauth"]     = "Invalid username password combination",
        ["nohost"]      = "Hostname supplied does not exist under specified account, client exit and require user to enter new login credentials before performing an additional request.",
        ["abuse"]       = "Username is blocked due to abuse. Either for not following our update specifications or disabled due to violation of the No-IP terms of service. Our terms of service can be viewed here. Client should stop sending updates.",
        ["!donator"]    = "An update request was sent including a feature that is not available to that particular user such as offline options.",
        ["911"]         = "A fatal error on our side such as a database outage. Retry the update no sooner than 30 minutes."
    }
}

--- id
--- 1: noip
--- 2: oray 花生壳
--- 3: 公云
--- ...
local MAP = {
    "noip",
    "oray",
    "pubyun",
    "dyndnsorg",
    "dyndnsfr",
    "dyndnspro",
    "dynamicdomain",
    "dyndnsit",
    "duckdns",
    "systemns"
}

---xiaomi commit
---openwrt 18.06 on/stop call dynamic_dns_updater.sh
---/bin/sh /usr/lib/ddns/dynamic_dns_updater.sh -v 0 -S test --start
---luci_helper = "/usr/lib/ddns/dynamic_dns_lucihelper.sh"

function _serverId(server)
    for id, ser in ipairs(MAP) do
        if ser == server then
            return id
        end
    end
    return false
end

function _ddnsRestart()
    --return os.execute("/usr/sbin/ddnsd reload") == 0
    XQFunction.forkExec("/usr/sbin/ddnsd reload")
    return 0
end

--- server: noip/oray
--- enable: 0/1
function _saveConfig(server, enable, username, password, checkinterval, forceinterval, domain)
    local uci = require("luci.model.uci").cursor()
    local service = SERVICES[server]
    if service and username and password and domain and checkinterval and forceinterval then
        uci:foreach("ddns", "service",
            function(s)
                if s[".name"] ~= server and tonumber(s.enabled) == 1 then
                    uci:set("ddns", s[".name"], "enabled", 0)
                end
            end
        )
        local section = {
            ["enabled"] = enable,
            ["interface"] = "wan",
            ["service_name"] = service.service_name,
            ["force_interval"] = forceinterval,
            ["force_unit"] = "hours",
            ["check_interval"] = checkinterval,
            ["check_unit"] = "minutes",
            ["username"] = username,
            ["password"] = password,
            ["ip_source"] = "network",
            ["ip_url"] = service.ip_url,
            ["lookup_host"] = domain,
            ["domain"] = domain,
	    ["use_https"] = 0
        }
	if service.service_name == "dyndns.org" then
	    section.use_https = 1
	end

        uci:section("ddns", "service", server, section)
        uci:commit("ddns")
        return true
    end
    return false
end

function _ddnsServerSwitch(server, enable)
    local uci = require("luci.model.uci").cursor()
    if XQFunction.isStrNil(server) then
        return false
    end
    uci:foreach("ddns", "service",
        function(s)
            if s[".name"] ~= server then
                if enable == 1 then
                    uci:set("ddns", s[".name"], "enabled", 0)
                    uci:set("ddns", s[".name"], "laststatus", "off")
                end
            else
                uci:set("ddns", s[".name"], "enabled", enable)
                if enable == 1 then
                    uci:set("ddns", s[".name"], "laststatus", "loading")
                else
                    uci:set("ddns", s[".name"], "laststatus", "off")
                end
            end
        end
    )
    uci:commit("ddns")
    if enable == 1 then
        return _ddnsRestart()
    else
        os.execute("/usr/sbin/ddnsd stop")
        return true
    end
end

-- status: 0/1/2 error/ok/loading
function ddnsInfo()
    local LuciJson = require("cjson")
    local LuciUtil = require("luci.util")
    local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
    local wanip = XQLanWanUtil.getLanWanIp("wan")
    if wanip and wanip[1] then
        wanip = wanip[1].ip
    else
        wanip = ""
    end
    local result = {
        ["on"] = 0,
        ["list"] = {}
    }
    local status = LuciUtil.exec("/usr/sbin/ddnsd status")
    if not XQFunction.isStrNil(status) then
        status = LuciJson.decode(status)
        if status.daemon == "on" then
            result.on = 1
        end
        for key, value in pairs(status) do
            if key ~= "deamon" then
                local id = _serverId(key)
                local uci = require("luci.model.uci").cursor()
                local cof = uci:get_all("ddns", key)
                if cof then
                    if cof.laststatus == "ok" then
                        value.status = 1
                    elseif cof.laststatus == "loading" or not cof.laststatus then
                        value.status = 2
                    else
                        value.status = 0
                        local errdic = ERROR[key]
                        if errdic then
                            value["error"] = errdic[cof.lastreturn] or cof.lastreturn
                        end
                    end
                end
                if id then
                    value.enabled = tonumber(value.enabled)
                    value.id = id
                    value.servicename = SERVICES[key].service_name
                    value["wanip"] = wanip
                    table.insert(result.list, value)
                end
            end
        end
    end
    return result
end

function ddnsSwitch(on)
    if on then
        os.execute("/usr/sbin/ddnsd start")
    else
        os.execute("/usr/sbin/ddnsd stop")
    end
end

function getDdns(id)
    if not tonumber(id) then
        return false
    end
    local uci = require("luci.model.uci").cursor()
    local server = MAP[tonumber(id)]
    local result = {}
    local ddns = uci:get_all("ddns", server)
    if ddns then
        result["username"] = ddns.username or ""
        result["password"] = ddns.password or ""
        result["forceinterval"] = tonumber(ddns.force_interval) or 0
        result["checkinterval"] = tonumber(ddns.check_interval) or 0
        result["domain"] = ddns.domain or ""
        result["enabled"] = tonumber(ddns.enabled) or 0
        return result
    end
    return false
end

function setDdns(id, enable, username, password, checkinterval, forceinterval, domain)
    if not tonumber(id) then
        return false
    end
    local server = MAP[tonumber(id)]
    if XQFunction.isStrNil(username)
        or XQFunction.isStrNil(password)
        or XQFunction.isStrNil(domain)
        or XQFunction.isStrNil(server) then
        return false
    end
    checkinterval = tonumber(checkinterval)
    forceinterval = tonumber(forceinterval)
    if not checkinterval or not forceinterval then
        return false
    end
    local denable = enable == 1 and 1 or 0
    if _saveConfig(server, denable, username, password, checkinterval, forceinterval, domain) then
        return _ddnsRestart()
    end
    return false
end

function editDdns(id, enable, username, password, checkinterval, forceinterval, domain)
    if not tonumber(id) then
        return false
    end
    local uci = require("luci.model.uci").cursor()
    local server = MAP[tonumber(id)]
    local ddns = uci:get_all("ddns", server)
    if ddns then
        if not XQFunction.isStrNil(username) and username ~= ddns.username then
            uci:set("ddns", server, "username", username)
        end
        if not XQFunction.isStrNil(password) and password ~= ddns.password then
            uci:set("ddns", server, "password", password)
        end
        if not XQFunction.isStrNil(domain) and domain ~= ddns.domain then
            uci:set("ddns", server, "lookup_host", domain)
            uci:set("ddns", server, "domain", domain)
        end
        if tonumber(checkinterval) and tonumber(checkinterval) ~= tonumber(ddns.check_interval) then
            uci:set("ddns", server, "check_interval", checkinterval)
        end
        if tonumber(forceinterval) and tonumber(forceinterval) ~= tonumber(ddns.force_interval) then
            uci:set("ddns", server, "force_interval", forceinterval)
        end
        local enabled = enable == 1 and 1 or 0
        if enabled ~= tonumber(ddns.enabled) then
            uci:set("ddns", server, "enabled", enabled)
        end
        uci:set("ddns", server, "laststatus", "off")
        uci:commit("ddns")
        os.execute("/usr/lib/ddns/dynamic_dns_updater.sh -- reload")

        --if enabled ~= 0 or ddns.enabled ~= 0 then
        --    _ddnsRestart()
        --end
        return true
    end
    return false
end

function deleteDdns(id)
    if not tonumber(id) then
        return false
    end
    local server = MAP[tonumber(id)]
    if XQFunction.isStrNil(server) then
        return false
    end
    local uci = require("luci.model.uci").cursor()
    uci:delete("ddns", server)
    uci:commit("ddns")
    os.execute("/usr/lib/ddns/dynamic_dns_updater.sh -- reload")
    return true
end

--- id (1/2/3...)
--- on (true/false)
function ddnsServerSwitch(id, on)
    if id then
        return _ddnsServerSwitch(MAP[id], on and 1 or 0)
    end
    return false
end

function reload()
    return _ddnsRestart()
end
