module ("xiaoqiang.util.XQMinetUtil", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQLog = require("xiaoqiang.XQLog")


function listFsm()
    local result = {
      ["code"] = 0,
    }
    local LuciUtil = require("luci.util")
    local Json = require("luci.json")
    local cmd = "ubus call minetd fsm_state"
    local ubusinfo = LuciUtil.exec(cmd)
    if XQFunction.isStrNil(ubusinfo) then
        result.code = 1
        return result
    end
    ubusinfo = Json.decode(ubusinfo)
    if XQFunction.isStrNil(ubusinfo) then
        result.code = 2
        return result
    end
    result.code = 0
    result.data = ubusinfo
    return result
end


function ctrlState(ctrl)
  local result = {
    ["code"] = 0,
  }
  local LuciUtil = require("luci.util")

  XQLog.log(1,"MiNet state ctrl "..ctrl)

  if ctrl == nil then
    result.code = 1
    return result
  end

  if ctrl == "1" then
    LuciUtil.exec("ubus call minetd ctrl \'{ \"cmd\":1, \"push\":0, \"src\":\"luci\"}\'")
  end

  if ctrl == "2" then
    LuciUtil.exec("ubus call minetd ctrl \'{ \"cmd\":2, \"push\":0, \"src\":\"luci\"}\'")
  end

  return result
end



function listDevice()
    local result = {
      ["code"] = 0,
    }
    local LuciUtil = require("luci.util")
    local Json = require("luci.json")
    local cmd = "ubus call minetd list"
    local ubusinfo = LuciUtil.exec(cmd)
    if XQFunction.isStrNil(ubusinfo) then
        result.code = 1
        return result
    end
    ubusinfo = Json.decode(ubusinfo)
    if XQFunction.isStrNil(ubusinfo) then
        result.code = 1
        return result
    end
    result.code = 0
    result.data = ubusinfo
    return result
end


function grantDevice(devid,ctrl)
    local result = {
      ["code"] = 0,
    }
    local param = {
      ["mac"]  = XQFunction._strformat(devid),
      ["ctrl"] = tonumber(ctrl)
    }
    local LuciUtil = require("luci.util")
    local Json = require("luci.json")
    local cmd = "ubus call minetd grant "
    local uparam = "'"..Json.encode(param).."'"
    local ubusinfo = LuciUtil.exec(cmd .. uparam)
    XQLog.log(1,"MiNet grant Device "..ctrl)
    if XQFunction.isStrNil(ubusinfo) then
        result.code = 1
        return result
    end
    ubusinfo = Json.decode(ubusinfo)
    if XQFunction.isStrNil(ubusinfo) then
        result.code = 1
        return result
    end

    result.code = ubusinfo.code
    return result
end


function getConfig()
    local result = {
        ["code"] = 0,
        ["data"] = {
          ["enable"] = 0,
          ["express"] = 0
        }
    }

    local uci = require("luci.model.uci").cursor()
    -- Minet doesn't exist
    if posix.stat("/usr/sbin/minetd") == nil then
        result.code = 1
        return result
    end

    result.data.enable = tonumber(uci:get("minet", "setting", "enabled")) or 0
    result.data.express = tonumber(uci:get("minet", "setting", "express_connect")) or 0
    result.code = 0
    return result
end

function setConfig(enable,express)
    local uci = require("luci.model.uci").cursor()
    local cmd_restart = [[
      /etc/init.d/minet restart
    ]]
    -- Minet doesn't exist
    if posix.stat("/usr/sbin/minetd") == nil then
        return
    end

    if enable ~= nil then
      uci:set("minet", "setting", "enabled", enable)
    end

    if express ~= nil then
      uci:set("minet", "setting", "express_connect", express)
    end

    uci:commit("minet")

    XQFunction.forkExec(cmd_restart)
    return
end
