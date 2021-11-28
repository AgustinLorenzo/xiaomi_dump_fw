module ("xiaoqiang.util.XQController", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")

local Json = require("json")

function _ubusSend(payload)
    local jsonstr = Json.encode(payload)
    local cmd = "ubus send trafficd \""..XQFunction._cmdformat(jsonstr).."\""
    os.execute(cmd)
end

function permission(mac, lan, wan, admin, pridisk)
    if XQFunction.isStrNil(mac) then
        return
    end
    local payload = {
        ["api"] = 1,
        ["mac"] = mac,
        ["lan"] = lan,
        ["wan"] = wan,
        ["admin"] = admin,
        ["pridisk"] = pridisk
    }
    _ubusSend(payload)
end

function wifimacfilter(mac, enable, model, option)
    local payload = {
        ["api"] = 2,
        ["mac"] = "",
        ["enable"] = "",
        ["model"] = "",
        ["option"] = ""
    }
    if mac then
        payload.mac = mac
        payload.model = model
        payload.option = option
    else
        payload.mac = nil
        if enable then
            payload.enable = 1
        else
            payload.enable = nil
        end
        payload.model = model
    end
    -- _ubusSend(payload)
end