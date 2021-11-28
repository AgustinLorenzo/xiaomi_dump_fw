
local config = require("xiaoqiang.common.XQConfigs")

local func = require("xiaoqiang.common.XQFunction")

local preference = require("xiaoqiang.XQPreference")

local log = require("xiaoqiang.XQLog")

local net = require("xiaoqiang.util.XQNetUtil")

local sys = require("xiaoqiang.util.XQSysUtil")

local downloader = require("xiaoqiang.util.XQDownloadUtil")

local util = require("luci.util")

local fs = require("luci.fs")

local TIME_LIMIT = 300

function _(text)
    return text
end

sys.updateUpgradeStatus(1)

preference.set(config.PREF_ROM_FULLSIZE, nil)
preference.set(config.PREF_ROM_DOWNLOAD_URL, nil)
preference.set(config.PREF_ROM_DOWNLOAD_ID, nil)

local uci = require("luci.model.uci").cursor()
local flashpermission = tonumber(uci:get("misc", "hardware", "flash_per")) == 1 and 1 or 0
local usbmodecheck = tonumber(uci:get("misc", "hardware", "usbmode")) == 1 and 1 or 0
local check = {}

if #arg == 3 then
    check["needUpdate"] = 1
    check["downloadUrl"] = arg[1]
    check["fullHash"] = arg[2]
    check["fileSize"] = tonumber(arg[3])
else
    check = net.checkUpgrade()
end

log.log(6,"Upgrade:check upgrade",check)

if check and check.needUpdate == 1 then
    sys.updateUpgradeStatus(2)
    local downloadUrl = check.downloadUrl
    local fullhash = check.fullHash

    if downloadUrl and fullhash then
        sys.updateUpgradeStatus(3)
        preference.set(config.PREF_ROM_FULLSIZE,check.fileSize)
        preference.set(config.PREF_ROM_DOWNLOAD_URL,downloadUrl)

        log.log(6,"Upgrade:downloading ...")
        local usbmode
        if usbmodecheck == 1 then
            usbmode = sys.usbMode()
            if usbmode then
                os.execute("/etc/init.d/usb_deploy_init_script.sh stop >/dev/null 2>/dev/null; echo 3 > /proc/sys/vm/drop_caches")
            end
        end
        local hash, path = downloader.syncDownload(downloadUrl)
        log.log(6,"Hash and path:", hash, path)
        if hash == fullhash and path then
            log.log(6,"Upgrade:download success")
            if not sys.verifyImage(path) then
                sys.updateUpgradeStatus(9)
                if path and fs.access(path) then
                    fs.unlink(path)
                end
                if usbmode then
                    os.execute("/etc/init.d/usb_deploy_init_script.sh start >/dev/null 2>/dev/null")
                end
                return
            end
            sys.updateUpgradeStatus(5)
            local limit = 0
            while not sys.getFlashPermission() do
                limit = limit + 2
                if limit >= TIME_LIMIT then
                    break
                end
                os.execute("sleep 2")
            end
            local result = os.execute("flash.sh '"..path.."'")
            if result == 0 then
                if flashpermission == 0 then
                    os.execute(config.NVRAM_SET_UPGRADED)
                end
                sys.updateUpgradeStatus(11)
            else
                sys.updateUpgradeStatus(10)
                if path and fs.access(path) then
                    fs.unlink(path)
                end
                if usbmode then
                    os.execute("/etc/init.d/usb_deploy_init_script.sh start >/dev/null 2>/dev/null")
                end
            end
            log.log(6,"Upgrade:result "..tostring(result))
        else
            if path then
                fs.unlink(path)
            end
            if usbmode then
                os.execute("/etc/init.d/usb_deploy_init_script.sh start >/dev/null 2>/dev/null")
            end
            sys.updateUpgradeStatus(8)
            log.log(3,"Upgrade:download failed")
        end
    else
        sys.updateUpgradeStatus(7)
        log.log(3,"Upgrade:No url or fullhash")
    end
elseif check and check.needUpdate == 0 then
    sys.updateUpgradeStatus(6)
    log.log(6,"Upgrade:No update")
else
    sys.updateUpgradeStatus(6)
    log.log(3,"Upgrade:server unreachable")
end

