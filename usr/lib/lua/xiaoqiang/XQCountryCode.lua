module ("xiaoqiang.XQCountryCode", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local i18n = require("luci.i18n")
function _(text)
    return i18n.translate(text)
end

COUNTRY_CODE = {
    {["c"] = "CN", ["n"] = _("中国大陆"), ["p"] = true},
    {["c"] = "HK", ["n"] = _("香港地区"), ["p"] = true},
    {["c"] = "TW", ["n"] = _("台湾地区"), ["p"] = true},
    {["c"] = "KR", ["n"] = _("韩国"), ["p"] = true},
    {["c"] = "US", ["n"] = _("美国"), ["p"] = false},
    {["c"] = "SG", ["n"] = _("新加坡"), ["p"] = false},
    {["c"] = "MY", ["n"] = _("马来西亚"), ["p"] = false},
    {["c"] = "IN", ["n"] = _("印度"), ["p"] = false},
    {["c"] = "CA", ["n"] = _("加拿大"), ["p"] = false},
    {["c"] = "FR", ["n"] = _("法国"), ["p"] = false},
    {["c"] = "DE", ["n"] = _("德国"), ["p"] = false},
    {["c"] = "IT", ["n"] = _("意大利"), ["p"] = false},
    {["c"] = "ES", ["n"] = _("西班牙"), ["p"] = false},
    {["c"] = "PH", ["n"] = _("菲律宾"), ["p"] = false},
    {["c"] = "ID", ["n"] = _("印度尼西亚"), ["p"] = false},
    {["c"] = "TH", ["n"] = _("泰国"), ["p"] = false},
    {["c"] = "VN", ["n"] = _("越南"), ["p"] = false},
    {["c"] = "BR", ["n"] = _("巴西"), ["p"] = false},
    {["c"] = "RU", ["n"] = _("俄罗斯"), ["p"] = false},
    {["c"] = "MX", ["n"] = _("墨西哥"), ["p"] = false},
    {["c"] = "TR", ["n"] = _("土耳其"), ["p"] = false},
    {["c"] = "EU", ["n"] = _("欧洲"), ["p"] = true}
}

REGION = {
    ["CN"] = {["region"] = 1, ["regionABand"] = 0},
    ["TW"] = {["region"] = 0, ["regionABand"] = 13},
    ["HK"] = {["region"] = 1, ["regionABand"] = 0},
    ["US"] = {["region"] = 0, ["regionABand"] = 10},
    ["EU"] = {["region"] = 1, ["regionABand"] = 6},
    ["KR"] = {["region"] = 1, ["regionABand"] = 23},
    ["ID"] = {["region"] = 1, ["regionABand"] = 5}
}

LANGUAGE = {
    ["CN"] = "zh_cn",
    ["TW"] = "zh_tw",
    ["HK"] = "zh_hk",
    ["US"] = "en",
    ["EU"] = "en",
    ["KR"] = "ko_kr",
    ["ID"] = "en_id"
}

JLANGUAGE = {
    ["zh_cn"] = "zh_CN",
    ["zh_tw"] = "zh_TW",
    ["zh_hk"] = "zh_HK",
    ["en"]    = "en_US",
    ["ko_kr"] = "ko_KR",
    ["en_id"] = "en_ID"
}

function getCountryCodeList()
    local clist = {}
    for _, item in ipairs(COUNTRY_CODE) do
        if item and item.p then
            table.insert(clist, {
                ["name"] = item.n,
                ["code"] = item.c
            })
        end
    end
    return clist
end

function getCurrentCountryCode()
    local XQSysUtil = require("xiaoqiang.util.XQSysUtil")
    local ccode = XQFunction.nvramGet("CountryCode")
    local channel = XQSysUtil.getChannel()
    if XQFunction.isStrNil(ccode) then
        return "CN"
    end
    return ccode
end

function getBDataCountryCode()
    local XQSysUtil = require("xiaoqiang.util.XQSysUtil")
    local ccode = XQFunction.bdataGet("CountryCode")
    local channel = XQSysUtil.getChannel()
    if XQFunction.isStrNil(ccode) then
        return "CN"
    end
    return ccode
end

function setCurrentCountryCode(ccode)
    if XQFunction.isStrNil(ccode) or REGION[ccode] == nil or LANGUAGE[ccode] == nil then
        return false
    end
    local XQSysUtil = require("xiaoqiang.util.XQSysUtil")
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    XQFunction.nvramSet("CountryCode", ccode)
    XQFunction.nvramCommit()
    --XQSysUtil.setLang(LANGUAGE[ccode])
    XQWifiUtil.setWifiRegion(ccode, REGION[ccode].region, REGION[ccode].regionABand)
    return true
end

function getCurrentJLan()
    local XQSysUtil = require("xiaoqiang.util.XQSysUtil")
    local channel = XQSysUtil.getChannel()
    local llan = XQSysUtil.getLang() or "zh_cn"
    -- if channel ~= "release" then
    --     llan = "zh_cn"
    -- end
    return JLANGUAGE[llan]
end
