module ("xiaoqiang.module.XQKVStore", package.seeall)

function getRouterKV()
    local XQFunction    = require("xiaoqiang.common.XQFunction")
    local XQPushUtil    = require("xiaoqiang.util.XQPushUtil")
    local XQSysUtil     = require("xiaoqiang.util.XQSysUtil")
    local XQWifiUtil    = require("xiaoqiang.util.XQWifiUtil")
    local XQDeviceUtil  = require("xiaoqiang.util.XQDeviceUtil")
    local XQLanWanUtil  = require("xiaoqiang.util.XQLanWanUtil")
    local XQQoSUtil     = require("xiaoqiang.util.XQQoSUtil")
    local XQVASModule   = require("xiaoqiang.module.XQVASModule")
    local XQPredownload = require("xiaoqiang.module.XQPredownload")
    local workmode = XQFunction.getNetModeType()
    local activeapcli = XQWifiUtil.apcli_get_active_type()
    local qosInfo = workmode == 0 and XQQoSUtil.qosHistory(XQDeviceUtil.getDeviceMacsFromDB()) or {}
    local settings = XQPushUtil.pushSettings()
    local info = XQDeviceUtil.devicesInfo()
    local bssid2, bssid5 = XQWifiUtil.getWifiBssid()
    local bssidguest = XQWifiUtil.getGuestWifiBssid()
    local ssid2, ssid5 = XQWifiUtil.getWifissid()
    local pmode = XQWifiUtil.getWiFiMacfilterModel() - 1
    local vasinfo = XQVASModule.get_vas_kv_info()
    -- local confinfo = XQSysUtil.doConfUpload(false)
    -- if confinfo then
    --     for key, value in pairs(confinfo) do
    --         info[key] = value
    --     end
    -- end
    if vasinfo then
        for key, value in pairs(vasinfo) do
            info[key] = value
        end
    end
    qosInfo["guest"] = XQQoSUtil.guestQoSInfo()
    if pmode < 0 then
        pmode = 0
    end
    local laninfo = XQLanWanUtil.getLanWanInfo("lan")
    local otainfo = XQPredownload.predownloadInfo()
    info["router_name"]         = XQSysUtil.getRouterName()
    info["plugin_id_list"]      = XQSysUtil.getPluginIdList()
    info["router_locale"]       = tostring(XQSysUtil.getRouterLocale())
    info["work_mode"]           = tostring(workmode)
    info["active_apcli_mode"]   = tostring(activeapcli)
    info["ap_lan_ip"]           = XQLanWanUtil.getLanIp()
    info["bssid_24G"]           = bssid2 or ""
    info["bssid_5G"]            = bssid5 or ""
    info["bssid_guest"]         = bssidguest or ""
    info["ssid_24G"]            = ssid2 or ""
    info["ssid_5G"]             = ssid5 or ""
    info["bssid_lan"]           = laninfo.mac
    info["protection_enabled"]  = settings.auth and "1" or "0"
    info["protection_mode"]     = tostring(pmode)
    info["qos_info"]            = qosInfo
    info["auto_ota_rom"]        = tostring(otainfo.auto)
    info["auto_ota_plugin"]     = tostring(otainfo.plugin)
    return info
end
