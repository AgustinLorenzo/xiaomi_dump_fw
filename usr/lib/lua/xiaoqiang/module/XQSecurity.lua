module ("xiaoqiang.module.XQSecurity", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local vas = require("xiaoqiang.module.XQVASModule")
--
-- "wifi_arn"               防蹭网开关
-- "anti_hijack"            上网防劫持
-- "privacy_protection"     隐私泄漏防火墙
-- "virus_file_firewall"    病毒文件防火墙
-- "malicious_url_firewall" 恶意网址防火墙  (这个功能属于增值服务)
-- "app_security_v2"        app安全下载    (这个功能属于增值服务)
--
function security_status()
    local uci = require("luci.model.uci").cursor()
    local XQPushUtil = require("xiaoqiang.util.XQPushUtil")

    -- 恶意网址防火墙
    local sec_vas = tonumber(uci:get("vas", "services", "security_page") or 0)
    local sec_vas_user = tonumber(uci:get("vas_user", "services", "security_page") or 0)
    local sec = tonumber(uci:get("security", "common", "malicious_url_firewall") or 0)
    if sec_vas_user ~= sec and sec_vas ~= -6 then
        uci:set("security", "common", "malicious_url_firewall", sec_vas_user)
        uci:commit("security")
        XQFunction.forkExec("touch /etc/config/securitypage/enable.tag;/etc/init.d/securitypage restart")
    end
    local status = {
        ["wifi_arn"] = 0,
        ["privacy_protection"] = tonumber(uci:get("security", "common", "privacy_protection") or 0),
        ["virus_file_firewall"] = tonumber(uci:get("security", "common", "virus_file_firewall") or 0),
        ["malicious_url_firewall"] = sec_vas_user,
    }

    -- app安全下载,如果vas没同步到该项那么不应该展示
    local vas_settings = vas.get_vas()
    if vas_settings["app_security_v2"] then
        status["app_security_v2"] = vas_settings["app_security_v2"]
    end

    local conf = XQPushUtil.pushSettings()
    status.wifi_arn = conf.auth and 1 or 0
    local open = 1
    for key, value in pairs(status) do
        if value == 0 then
            open = 0
            break
        end
    end
    status["open"] = open
    status["count"] = conf.count
    return status
end

-- wifi_arn 不在这里处理，涉及到另外的模块，封装到api里面
-- malicious_url_firewall 是增值服务里的 security_page ，需要特殊处理
-- app_security_v2 属于增值服务，需要特殊处理
function security_switch(values)
    local uci = require("luci.model.uci").cursor()
    if values and type(values) == "table" then
        for key, value in pairs(values) do
            if key == "privacy_protection" then
                uci:set("security", "common", "privacy_protection", value)
            elseif key == "virus_file_firewall" then
                uci:set("security", "common", "virus_file_firewall", value)
            elseif key == "malicious_url_firewall" then
                vas.set_vas({["security_page"] = value})
            elseif key == "app_security_v2" then
                vas.set_vas({["app_security_v2"] = value})
            end
        end
        uci:commit("security")
        XQFunction.forkExec("touch /etc/config/securitypage/enable.tag;/etc/init.d/securitypage restart")
    end
end
