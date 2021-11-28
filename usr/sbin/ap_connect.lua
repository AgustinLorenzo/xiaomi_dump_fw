
local ap        = require("xiaoqiang.module.XQAPModule")
local func	= require("xiaoqiang.common.XQFunction")
local nixio     = require("nixio")
local posix     = require("posix")
local util      = require("luci.util")
local crypto    = require("xiaoqiang.util.XQCryptoUtil")
local uci       = require("luci.model.uci").cursor()

function log(...)
    posix.openlog("ap-connect", LOG_NDELAY, LOG_USER)
    for i, v in ipairs({...}) do
        posix.syslog(4, util.serialize_data(v))
    end
    posix.closelog()
end

function main()
    local pid = util.exec("cat /tmp/ap_connect_pid 2>/dev/null")
    if pid and pid ~= "" then
        local code = os.execute("kill -0 "..tostring(pid))
        if code == 0 then
            log("Already running")
            return
        end
    end

    pid = nixio.getpid()
    os.execute("echo "..pid.." > /tmp/ap_connect_pid")

    local ssid = uci:get("xiaoqiang", "common", "BEUSED_SSID")
    local passwd = uci:get("xiaoqiang", "common", "BEUSED_PASSWD")
    local ssid_5g = uci:get("xiaoqiang", "common", "BEUSED_SSID_5G")
    local passwd_5g = uci:get("xiaoqiang", "common", "BEUSED_PASSWD_5G")
    local ssid_set
    local pwd_set

    local active_apcli = func.get_active_apcli()

    local apcli_2g_ifname = uci:get("misc", "wireless", "apcli_2g_ifname")
    if (active_apcli == apcli_2g_ifname) then
        band = "2g"
        ssid_set = ssid
        pwd_set = passwd
    else
        band = "5g"
        ssid_set = ssid_5g
        pwd_set = passwd_5g
    end
    if ssid_set then
        uci:set("xiaoqiang", "common", "AP_STATUS", "CONNECTING")
        local result = ap.setWifiAPMode(ssid_set, pwd_set, nil, nil, band, nil, nil, nil, nil, nil, nil)
        if result.ip and result.ip ~= "" then
            -- succeed
            uci:set("xiaoqiang", "common", "AP_STATUS", "SUCCEED")
            ap.actionForEnableWifiAP(true)
        else
            -- failed
            uci:set("xiaoqiang", "common", "AP_STATUS", "FAILED")
        end
        uci:commit("xiaoqiang")
        log(result)
    else
        log("Param error")
    end
end

main()
