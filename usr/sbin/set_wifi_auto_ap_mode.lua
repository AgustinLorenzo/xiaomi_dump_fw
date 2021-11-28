
    local XQErrorUtil = require("xiaoqiang.util.XQErrorUtil")
    local XQLog = require("xiaoqiang.XQLog")
    local XQFunction = require("xiaoqiang.common.XQFunction")
    local XQAPModule = require("xiaoqiang.module.XQAPModule")
    local XQSysUtil = require("xiaoqiang.util.XQSysUtil")
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local uci = require("luci.model.uci").cursor()
    local result = {
        ["code"] = 0
    }

    local ssid = arg[1]
    local password = arg[2]
    local admin_password = arg[4]
    local band = arg[3]
    local ap
    local i = 0

    XQLog.log(1,"recv ssid:"..ssid.." password"..password.." band"..band)

    XQLog.check(0, XQLog.KEY_FUNC_WIFI_RELAY, 1)
    os.execute("echo  aaa > /tmp/set_wifi_auto_ap_mode_try_result")

    for i = 0,10 do
    if ssid then
        ap = XQAPModule.setWifiAPMode(ssid, password, "", "", band,"" , "", ssid, "mixed-psk", password, ssid.."_5G")
        if not ap.scan then
            result.code = 1617
        elseif ap.connected then
            if XQFunction.isStrNil(ap.ip) then
                result.code = 1615
            else
		result.code = 0
                result.ip = ap.ip
                result.ssid = ap.ssid
                result.ssid5G = ap.ssid5G
		break
            end
        else
            result.code = 1616
            --result["msg"] = XQErrorUtil.getErrorMessage(result.code).."("..tostring(ap.conerrmsg)..")"
        end
    else
        result.code = 1523
    end
       	--result["msg"] = XQErrorUtil.getErrorMessage(result.code)
	local cmd ="echo \""..i.." code:"..result.code.."\" >> /tmp/set_wifi_auto_ap_mode_try_result"
--	local cmd ="echo \""..i.." code:"..result.code.." msg:"..result.msg.."\" >> /tmp/set_wifi_auto_ap_mode_try_result"
	os.execute(cmd)
    end
	--local cmd ="echo \"final  code:"..result.code.." msg:"..result.msg.."\" >> /tmp/set_wifi_auto_ap_mode_try_result"
	local cmd ="echo \"final  code:"..result.code.."\" >> /tmp/set_wifi_auto_ap_mode_try_result"
    os.execute(cmd)
 
    if result.code == 0 then
        uci:set("account",   "common", "admin", admin_password) 
	uci:commit("account")
        XQSysUtil.setInited()
        XQAPModule.actionForEnableWifiAP()
    end

