module("luci.controller.service.cachecenter", package.seeall)

function index()
    local page   = node("service","cachecenter")
    page.target  = firstchild()
    page.title   = ("")
    page.order   = nil
    page.sysauth = "admin"
    page.sysauth_authenticator = "jsonauth"
    page.index = true
    entry({"service", "cachecenter", "report_key"}, call("reportKey"), _(""), nil, 0x01)
end

local LuciHttp = require("luci.http")
local XQConfigs = require("xiaoqiang.common.XQConfigs")
local ServiceErrorUtil = require("service.util.ServiceErrorUtil")

function tunnelRequestCachecenter(payload)
    local LuciJson = require("cjson")
    local LuciUtil = require("luci.util")
    local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
    payload = LuciJson.encode(payload)
    payload = XQCryptoUtil.binaryBase64Enc(payload)
    local cmd = XQConfigs.THRIFT_TUNNEL_TO_CACHECENTER % payload
    LuciHttp.write(LuciUtil.exec(cmd))
end

function requestCachecenter(payload)
    local LuciJson = require("cjson")
    local LuciUtil = require("luci.util")
    local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
    payload = LuciJson.encode(payload)
    payload = XQCryptoUtil.binaryBase64Enc(payload)
    local cmd = XQConfigs.THRIFT_TUNNEL_TO_CACHECENTER % payload
    return LuciUtil.exec(cmd)
end

function reportKey()
    local payload = {}
    payload["api"] = 1
    payload["key"] = LuciHttp.formvalue("key")
    tunnelRequestCachecenter(payload)
end
