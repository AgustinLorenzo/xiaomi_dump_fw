module ("xiaoqiang.XQEvent", package.seeall)

function lanIPChange(ip)
    local DMZ = require("xiaoqiang.module.XQDMZModule")
    local Guest = require("xiaoqiang.module.XQGuestWifi")
    local PortForward = require("xiaoqiang.module.XQPortForward")
    local LanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
    DMZ.hookLanIPChangeEvent(ip)
    Guest.hookLanIPChangeEvent(ip)
    PortForward.hookLanIPChangeEvent(ip)
    LanWanUtil.hookLanIPChangeEvent(ip)
end