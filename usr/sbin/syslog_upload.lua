local net = require("xiaoqiang.util.XQNetUtil")
local XQLog = require("xiaoqiang.XQLog")
local uci = require("luci.model.uci").cursor()
local HARDWARE = uci:get("misc", "hardware", "model") or ""
if HARDWARE then
    HARDWARE = string.lower(HARDWARE)
end
local mode = uci:get("xiaoqiang", "common", "NETMODE") or ""

local key = arg[1]

if key then
    -- send log upload cmd to RE for D01
    --XQLog.log(6,"log upload hardware:" ..HARDWARE)
    --XQLog.log(6,"log upload mode:" ..mode)
    if HARDWARE:match("^d01") and mode:match("^whc_cap") then
        XQLog.log(6,"D01 CAP call RE upload log, CAP key:" ..key)
        os.execute("/sbin/whc_to_re_common_api.sh log_upload "..key)
    end
    os.execute("/usr/sbin/log_collection.sh")
    net.uploadLogV2(key)
end
