module("luci.controller.web.index", package.seeall)

function index()
    local root = node()
    if not root.target then
        root.target = alias("web")
        root.index = true
    end
    local page   = node("web")
    page.target  = firstchild()
    page.title   = _("")
    page.order   = 10
    page.sysauth = "admin"
    page.mediaurlbase = "/xiaoqiang/web"
    page.sysauth_authenticator = "htmlauth"
    page.index = true

    local LuciUtil = require "luci.util"
    local XQSysUtil = require "xiaoqiang.util.XQSysUtil"
    local misc = XQSysUtil.getMiscHardwareInfo()

    local XQFunction = require("xiaoqiang.common.XQFunction")
    local netMode = XQFunction.getNetModeType()

    entry({"web"}, alias("web", "home"), _("路由器状态"), 10, 0x08)
    entry({"web", "logout"}, call("action_logout"), 11, 0x09)

    if misc.recovery == 1 then
        entry({"web", "home"}, template("web/recovery"), _("路由器状态"), 12)
    else
        if netMode == 0 then
            entry({"web", "home"}, template("web/index"), _("路由器状态"), 12)
        elseif netMode == 1 then
            entry({"web", "home"}, template("web/apindex"), _("路由器状态"), 12)
        elseif netMode == 3 then
            entry({"web", "home"}, template("web/apindex_d01"), _("路由器状态"), 12)
        else
            entry({"web", "home"}, template("web/apindex"), _("路由器状态"), 12)
        end
    end

    entry({"web", "init"}, alias("web", "init", "guidetoapp"), _("初始化引导"), 13)
    entry({"web", "init", "hello"}, call("action_hello"), _("欢迎界面"), 14, 0x09)   --不需要登录
    entry({"web", "init", "agreement"}, template("web/init/agreement"), _("用户协议"), 14, 0x09)   --不需要登录
    entry({"web", "init", "privacy"}, template("web/init/privacy"), _("用户体验改进计划"), 14, 0x09)   --不需要登录
    entry({"web", "init", "guide"}, template("web/init/guide"), _("引导模式"), 15, 0x08)
    entry({"web", "init", "guidetoapp"}, template("web/init/guidetoapp"), _("引导app"), 15, 0x09)
    entry({"web", "init", "guideuninit"}, template("web/init/guidetoapp_uninit"), _("引导app"), 15, 0x09)
    entry({"web", "init", "bind"}, template("web/init/bind"), _("引导app"), 15, 0x09)

    entry({"web", "setting"}, alias("web", "setting", "upgrade"), _("路由设置"), 20)
    entry({"web", "setting", "upgrade"}, template("web/setting/upgrade"), _("路由手动升级"), 21)
    -- entry({"web", "setting", "upgrade_manual"}, template("web/setting/upgrade_manual", _("路由器手动升级"), 18))
    entry({"web", "setting", "wifi"}, template("web/setting/wifi"), _("Wi-Fi设置"), 22)
    entry({"web", "setting", "wan"}, template("web/setting/wan"), _("外网设置"), 23)
    entry({"web", "setting", "proset"}, template("web/setting/proset"), _("高级设置"), 24)
    entry({"web", "setting", "lannetset"}, template("web/setting/lannetset"), _("局域网设置"), 25)
    entry({"web", "setting", "safe"}, template("web/setting/safe"), _("安全中心"), 26)

    entry({"web", "prosetting"}, alias("web", "prosetting", "qos"), _("路由设置"), 40)
    entry({"web", "prosetting", "dhcpipmacband"}, template("web/setting/dhcp_ip_mac"), _("DHCP静态IP分配"), 41)
    entry({"web", "prosetting", "dmz"}, template("web/setting/dmz"), _("DMZ"), 42)
    entry({"web", "prosetting", "nat"}, template("web/setting/nat_dmz"), _("端口转发"), 43)
    entry({"web", "prosetting", "upnp"}, template("web/setting/upnp"), _("upnp"), 44)
    entry({"web", "prosetting", "ddns"}, template("web/setting/ddns"), _("DDNS"), 45)
    entry({"web", "prosetting", "vpn"}, template("web/setting/vpn"), _("VPN"), 46)
    entry({"web", "prosetting", "qos"}, call('action_qos'), _("智能限速QoS"), 47)


    entry({"web", "apsetting"}, alias("web", "apsetting", "upgrade"), _("中继设置"), 60)
    entry({"web", "apsetting", "upgrade"}, template("web/apsetting/upgrade"), _("中继系统信息"), 61)
    entry({"web", "apsetting", "wan"}, template("web/apsetting/wan"), _("中继模式切换"), 62)
    entry({"web", "apsetting", "safe"}, template("web/apsetting/safe"), _("中继密码设置"), 63)
    entry({"web", "apsetting", "wifi"}, call("action_apwifi"), _("中继Wi-Fi设置"), 64)
    entry({"web", "apsetting", "roam"}, template("web/apsetting/roam"), _("roam"), 65)

    entry({"web", "store"}, template("web/store"), _("存储状态"), 90)

    entry({"web", "syslock"}, template("web/syslock"), _("路由升级"), 100)
    entry({"web", "upgrading"}, template("web/syslock"), _("路由升级"), 101, 0x0d)

    entry({"web", "webinitrdr"}, call("action_webinitrdr"), _(""), 110, 0x09)
    entry({"web", "login"}, template("web/sysauth"), _(""), 111)

    entry({"web", "ieblock"}, template("web/ieblock"), _(""), 120, 0x09)

    entry({"web", "topo"}, template("web/topograph"), _(""), 130, 0x0d)
end

function action_apwifi()
    local tpl = require("luci.template")
    local tplData = {}
    local XQFunction = require("xiaoqiang.common.XQFunction")
    local netMode = XQFunction.getNetModeType()
    if netMode == 1 then
        tpl.render("web/apsetting/wifi", tplData)
    else
        tpl.render("web/setting/wifi", tplData)
    end
end

function action_qos()
    local tpl = require("luci.template")
    local features = require("xiaoqiang.XQFeatures").FEATURES
    local qosIsSupport = features["apps"]["qos"]
    if qosIsSupport == "1" then
        tpl.render("web/setting/qos", {})
    else
        tpl.render("web/setting/qos_lite", {})
    end
end

function action_logout()
    local dsp = require "luci.dispatcher"
    local sauth = require "luci.sauth"
    if dsp.context.authsession then
        sauth.kill(dsp.context.authsession)
        dsp.context.urltoken.stok = nil
    end
    luci.http.redirect(luci.dispatcher.build_url())
end

function action_hello()
    local XQSysUtil = require("xiaoqiang.util.XQSysUtil")
    if XQSysUtil.getInitInfo() then
        luci.http.redirect(luci.dispatcher.build_url())
    else
        XQSysUtil.setSysPasswordDefault()
    end
    local tpl = require("luci.template")
    tpl.render("web/init/hello")
end

function action_webinitrdr()
    local result = {}
    result["code"] = 0
    result["data"] = {
        ["s1"] = _("你连接的路由器还未初始化"),
        ["s2"] = _("请稍候，会自动为你跳转到引导页面..."),
        ["s3"] = _("如果未能跳转，请直接访问"),
        ["s4"] = _("欢迎使用小米路由器")
    }
    luci.http.write_json(result)
end
