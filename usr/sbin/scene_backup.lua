#!/usr/bin/lua

local file_r1d = "/userdisk/smartcontroller/data/SmartTask.db"
local file_r1c = "/data/smartcontroller/SmartTask.db"

local XQSysUtil = require("xiaoqiang.util.XQSysUtil")
local XQHttpUtil = require("xiaoqiang.util.XQHttpUtil")
local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
local XQPreference  = require("xiaoqiang.XQPreference")
local LuciFs  = require("luci.fs")
local LuciUtil = require("luci.util")
local LuciJson = require("json")

function getFile()
    if LuciFs.access(file_r1d) then
      return file_r1d
    else
      return file_r1c
    end
end

function getSmartTaskDB()
    if LuciFs.access(file_r1d) then
        return LuciUtil.exec("/bin/cat ".. file_r1d)
    elseif LuciFs.access(file_r1c) then
        return LuciUtil.exec("/bin/cat ".. file_r1c)
    else
        return ""
    end
end

function trim(s)
  return s:match "^%s*(.-)%s*$"
end

require "luci.model.uci"
local cursor = luci.model.uci.cursor()
local did =  cursor:get("messaging","deviceInfo","DEVICE_ID")
local sec =  cursor:get("messaging","deviceInfo","CHANNEL_SECRET")
local uuid = XQSysUtil.getBindUUID()
local db = getSmartTaskDB()
local stamp = trim(LuciUtil.exec("/bin/date +%s"))

if did and sec and uuid and db then
  local k = XQCryptoUtil.binaryBase64Dec(sec)
  local k1 = string.sub(k,17)
  local sha1 = XQCryptoUtil.sha1(uuid .. did .. stamp .. k1 .. db)
  
  local url = "http://api.io.mi.com/router/scene/upload?did=".. did ..  "&uuid=".. uuid.. "&stamp=".. stamp .."&sha1=" .. sha1
  local ufile = getFile()
  -- http://10.101.11.216:8080/
  -- http://api.io.mi.com/
  print(string.len(db) .. " bytes to backup")
  local CURL_CMD = "/usr/bin/curl --connect-timeout 3 -s -F\"scene=@%s\" \"%s\""
  -- local res = XQHttpUtil.httpPostRequest(url ,db,nil)
  local res = LuciUtil.exec(string.format(CURL_CMD,ufile,url))
  print(res)
  local jres = LuciJson.decode(trim(res))
  if jres and jres.code == 0 then
    print("success")
    os.exit(0)
  end
end
print("fail")
os.exit(1)
