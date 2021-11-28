module("luci.controller.service.datacenter", package.seeall)

function index()
    local page   = node("service","datacenter")
    page.target  = firstchild()
    page.title   = ("")
    page.order   = nil
    page.sysauth = "admin"
    page.sysauth_authenticator = "jsonauth"
    page.index = true
    entry({"service", "datacenter", "download_file"}, call("downloadFile"), _(""), nil, 0x11)
    entry({"service", "datacenter", "device_id"}, call("getDeviceID"), _(""), nil, 0x11)
    entry({"service", "datacenter", "download_info"}, call("getDownloadInfo"), _(""), nil, 0x11)
    entry({"service", "datacenter", "upload_file"}, call("uploadFile"), _(""), nil, 0x11)
    entry({"service", "datacenter", "batch_download_info"}, call("getBatchDownloadInfo"), _(""), nil, 0x11)
    entry({"service", "datacenter", "config_info"}, call("getConfigInfo"), _(""), nil, 0x11)
    entry({"service", "datacenter", "set_config"}, call("setConfigInfo"), _(""), nil, 0x11)
    entry({"service", "datacenter", "plugin_enable"}, call("enablePlugin"), _(""), nil, 0x11)
    entry({"service", "datacenter", "plugin_download_info"}, call("pluginDownloadInfo"), _(""), nil, 0x11)
    entry({"service", "datacenter", "plugin_disable"}, call("disablePlugin"), _(""), nil, 0x11)
    entry({"service", "datacenter", "plugin_control"}, call("controlPlugin"), _(""), nil, 0x11)
    entry({"service", "datacenter", "feature_plugin_control"}, call("controlFeaturePlugin"), _(""), nil, 0x11)
    entry({"service", "datacenter", "download_delete"}, call("deleteDownload"), _(""), nil, 0x11)
    entry({"service", "datacenter", "get_plugin_status"}, call("pluginStatus"), _(""), nil, 0x11)
    entry({"service", "datacenter", "get_connected_device"}, call("connectedDevice"), _(""), nil, 0x11)
    entry({"service", "datacenter", "get_router_mac"}, call("getMac"), _(""), nil, 0x11)
    entry({"service", "datacenter", "set_wan_access"}, call("setWanAccess"), _(""), nil, 0x11)
    entry({"service", "datacenter", "get_router_info"}, call("getRouterInfo"), _(""), nil, 0x11)
    entry({"service", "datacenter", "xunlei_notify"}, call("xunleiNotify"), _(""), nil, 0x11)
    entry({"service", "datacenter", "get_routerIP"}, call("getRouterIP"), _(""), nil, 0x11)
    entry({"service", "datacenter", "multi_create"}, call("MultiCreate"), _(""), nil, 0x11)
    entry({"service", "datacenter", "run_command"}, call("RunCommand"), _(""), nil, 0x11)
    entry({"service", "datacenter", "idforvendor"}, call("idforvendor"), _(""), nil, 0x11)
    entry({"service", "datacenter", "media_delta"}, call("mediaDelta"), _(""), nil, 0x01)
    entry({"service", "datacenter", "media_metadata"}, call("mediaMetadata"), _(""), nil, 0x01)
    entry({"service", "datacenter", "share_miui_dir"}, call("shareMiuiBackupDir"), _(""), nil, 0x01)
    entry({"service", "datacenter", "get_file_list"}, call("getFileList"), _(""), nil, 0x01)
    entry({"service", "datacenter", "get_storage_info"}, call("getStorageInfo"), _(""), nil, 0x01)
    entry({"service", "datacenter", "get_youku_status"}, call("getYoukuStatus"), _(""), nil, 0x01)
    entry({"service", "datacenter", "get_camera_smbpath"}, call("getCameraSmbPath"), _(""), nil, 0x01)
    entry({"service", "datacenter", "bind_youku_appid"}, call("bindYoukuAppid"), _(""), nil, 0x01)
    entry({"service", "datacenter", "is_has_disk"}, call("isHasDisk"), _(""), nil, 0x08)
    entry({"service", "datacenter", "set_sync_router_file"}, call("setSyncRouterFile"), _(""), nil, 0x08)
end

local LuciHttp = require("luci.http")
local XQConfigs = require("xiaoqiang.common.XQConfigs")
local ServiceErrorUtil = require("service.util.ServiceErrorUtil")
local XQFunction = require("xiaoqiang.common.XQFunction")

function setSyncRouterFile()
   local json = require("cjson")
   local sync_dir = LuciHttp.formvalue("sources")
   local sync_dir_j = json.decode(sync_dir)
   local payload = {}
   payload["api"] = 118
   payload["sources"] = sync_dir_j;
   payload["remote_router_id"] = LuciHttp.formvalue("remote_router_id");
   tunnelRequestDatacenter(payload)
end

function isHasDisk()
   local payload = {}
   payload["api"] = 122
   tunnelRequestDatacenter(payload)
end

function getCameraSmbPath()
   local payload = {}
   payload["api"] = 115
   payload["mac"] = LuciHttp.formvalue("mac");
   tunnelRequestDatacenter(payload)
end

function getStorageInfo()
   local payload = {}
   payload["api"] = 17
   tunnelRequestDatacenter(payload)
end

function getFileList()
   local payload = {}
   payload["api"] = 3
   payload["path"] = LuciHttp.formvalue("path")
   payload["sharedOnly"] = true
   tunnelRequestDatacenter(payload)
end

function idforvendor()
   local payload = {}
   payload["api"] = 629
   payload["appid"] = LuciHttp.formvalue("appId")
   tunnelRequestDatacenter(payload)
end

function mediaMetadata()
    local payload = {}
    payload["api"] = 1202
    payload["path"] = LuciHttp.formvalue("path")
    payload["thumb_size"] = LuciHttp.formvalue("thumb_size")
    tunnelRequestDatacenter(payload)
end

function mediaDelta()
    local payload = {}
    payload["api"] = 1201
    payload["cursor"] = LuciHttp.formvalue("cursor")
    payload["len"] = LuciHttp.formvalue("len")
    tunnelRequestDatacenter(payload)
end

function getRouterIP()
    local payload = {}
    payload["api"] = 1112
    payload["appid"] = LuciHttp.formvalue("appId")
    tunnelRequestDatacenter(payload)
end

function shareMiuiBackupDir()
    local payload = {}
    payload["api"] = 100
    payload["mac"] = LuciHttp.formvalue("mac")
    tunnelRequestDatacenter(payload)
end

function xunleiNotify()
    local payload = {}
    payload["api"] = 519
    payload["info"] = LuciHttp.formvalue("tasks")
    tunnelRequestDatacenter(payload)
end

function RunCommand()
    local payload = {}
    payload["api"] = 625
    payload["appid"] = LuciHttp.formvalue("appId")
    payload["command"] = LuciHttp.formvalue("command")
    tunnelRequestDatacenter(payload)
end

function MultiCreate()
    local payload = {}
    payload["api"] = 520
    payload["urls"] = LuciHttp.formvalue("urls")
    payload["pathForUserData"] = LuciHttp.formvalue("pathForUserData")
    tunnelRequestDatacenter(payload)
end

function tunnelRequestDatacenter(payload)
    local LuciJson = require("cjson")
    local LuciUtil = require("luci.util")
    local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
    payload = LuciJson.encode(payload)
    payload = XQCryptoUtil.binaryBase64Enc(payload)
    local cmd = XQConfigs.THRIFT_TUNNEL_TO_DATACENTER % payload
    LuciHttp.write(LuciUtil.exec(cmd))
end

function requestDatacenter(payload)
    local LuciJson = require("cjson")
    local LuciUtil = require("luci.util")
    local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
    payload = LuciJson.encode(payload)
    payload = XQCryptoUtil.binaryBase64Enc(payload)
    local cmd = XQConfigs.THRIFT_TUNNEL_TO_DATACENTER % payload
    return LuciUtil.exec(cmd)
end

function downloadFile()
    local payload = {}
    payload["api"] = 1101
    payload["appid"] = LuciHttp.formvalue("appId")
    payload["path"] = LuciHttp.formvalue("path")
    payload["url"] = LuciHttp.formvalue("url")
    payload["name"] = LuciHttp.formvalue("downloadName")
    payload["tag"] = LuciHttp.formvalue("tag")
    payload["hidden"] = false
    if LuciHttp.formvalue("hidden") == "true" then
        payload["hidden"] = true
    end

    payload["redownload"] = 0
    if LuciHttp.formvalue("redownload") == "1" then
        payload["redownload"] = 1
    end

    payload["dupId"] = LuciHttp.formvalue("dupId")
    payload["pathForUserData"] = LuciHttp.formvalue("pathForUserData")
    tunnelRequestDatacenter(payload)
end

function setWanAccess()
    local payload = {}
    payload["api"] = 618
    payload["appid"] = LuciHttp.formvalue("appId")
    payload["mac"] = LuciHttp.formvalue("mac")
    payload["enable"] = false
    if LuciHttp.formvalue("enable") == "true" then
        payload["enable"] = true
    end
    tunnelRequestDatacenter(payload)
end

function getDeviceID()
    local payload = {}
    payload["api"] = 1103
    payload["appid"] = LuciHttp.formvalue("appId")
    tunnelRequestDatacenter(payload)
end

function getMac()
    local payload = {}
    payload["api"] = 617
    payload["appid"] = LuciHttp.formvalue("appId")
    tunnelRequestDatacenter(payload)
end

function getRouterInfo()
    local payload = {}
    payload["api"] = 622
    payload["appid"] = LuciHttp.formvalue("appId")
    tunnelRequestDatacenter(payload)
end

function getOperateDeviceID()
    local payload = {}
    payload["api"] = 1103
    payload["appid"] = LuciHttp.formvalue("appId")

    local result = requestDatacenter(payload)
    if result then
        local LuciJson = require("cjson")
        result = LuciJson.decode(result)
        if result then
            if result.code == 0 then
                local deviceid = result["deviceid"]
                if deviceid then
                    return 0, deviceid
                end
            elseif result.code == 5 then
                return 5, nil
            end
        end
    end

    return 1559, nil
end

function urlEncode(url)
    if url then
        url = string.gsub(url, "\n", "\r\n")
        url = string.gsub(url, "([^0-9a-zA-Z/])",
            function(c) return string.format ("%%%02X", string.byte(c)) end)
    end
    return url
end

function generateUrlFromPath(path)
    if path then
        path = urlEncode(path)
        local url, count = string.gsub (path, "^/userdisk/data/", "http://miwifi.com/api-third-party/download/public/")
        if count == 1 then
            return url
        end

        url, count = string.gsub (path, "^/userdisk/appdata/", "http://miwifi.com/api-third-party/download/private/")
        if count == 1 then
            return url
        end

        url, count = string.gsub (path, "^/extdisks/", "http://miwifi.com/api-third-party/download/extdisks/")
        if count == 1 then
            return url
        end
    end

    return nil
end

function generateResponseFromCode(code)
    local response = {}
    response["code"] = code
    response["msg"] = ServiceErrorUtil.getErrorMessage(code)
    return response
end

function getDownloadInfo()
    local LuciJson = require("cjson")
    local payload = {}
    payload["api"] = 1102
    payload["appid"] = LuciHttp.formvalue("appId")
    payload["deviceId"] = LuciHttp.formvalue("deviceId")
    payload["downloadId"] = LuciHttp.formvalue("downloadId")
    payload["hidden"] = false
    if LuciHttp.formvalue("hidden") == "true" then
        payload["hidden"] = true
    end

    local response = {}
    local result = requestDatacenter(payload)
    if result then
        result = LuciJson.decode(result)
        if result and result.code == 0 then
            local url = generateUrlFromPath(result["path"])
            if url then
                response["code"] = result["code"]
                response["msg"] = result["msg"]
                response["url"] = url
            else
                response = generateResponseFromCode(1559)
            end
        else
            response = result
        end
    else
        response = generateResponseFromCode(1559)
    end

    LuciHttp.write_json(response)
    LuciHttp.close()
end

function uploadFile()
    local fp
    local log = require("xiaoqiang.XQLog")
    local fs = require("luci.fs")
    local tmpfile = "/userdisk/data/upload.tmp"
    if fs.isfile(tmpfile) then
        fs.unlink(tmpfile)
    end

    local filename
    LuciHttp.setfilehandler(
        function(meta, chunk, eof)
            if not fp then
                if meta and meta.name == "file" then
                    fp = io.open(tmpfile, "w")
                    filename = meta.file
                    filename = string.gsub(filename, "+", " ")
                    filename = string.gsub(filename, "%%(%x%x)",
                        function(h)
                            return string.char(tonumber(h, 16))
                        end)
                    filename = filename.gsub(filename, "\r\n", "\n")
                end
            end
            if chunk then
                fp:write(chunk)
            end
            if eof then
                fp:close()
            end
        end
    )

    local code, deviceId = getOperateDeviceID()
    if code ~= 0 then
        return LuciHttp.write_json(generateResponseFromCode(code))
    end

    local path
    local appid = LuciHttp.formvalue("appId")
    local saveType = LuciHttp.formvalue("saveType")
        if saveType == "public" then
            path = "/userdisk/data/上传/"
        elseif saveType == "private" then
            local res = string.find(appid,"/")
            if res then
                return LuciHttp.write_json(generateResponseFromCode(3))
            end
            path = "/userdisk/appdata/" .. appid .. "/"
        else
            return LuciHttp.write_json(generateResponseFromCode(3))
        end
    fs.mkdir(path, true)

    local savename = fs.basename(filename)
    if fs.isfile(path .. savename) then
        local basename = savename
        local index = basename:match(".+()%.%w+$")
        if index then
            basename = basename:sub(1, index - 1)
        end

        local extension = savename:match(".+%.(%w+)$")
        for i = 1, 100, 1 do
            local tmpname = basename .. "(" .. i .. ")"
            if extension then
                tmpname = tmpname .. "." .. extension
            end
            if not fs.isfile(path .. tmpname) then
                savename = tmpname
                break
            end
        end
    end
    local dest = path .. savename
    log.log("dest=" .. dest)
    fs.rename(tmpfile, dest)

    local response = {}
    response["code"] = 0
    response["url"] = generateUrlFromPath(dest)
    response["deviceId"] = deviceId
    response["msg"] = ""
    LuciHttp.write_json(response)
    LuciHttp.close()
end

function getBatchDownloadInfo()
    local payload = {}
    payload["api"] = 1105
    payload["appid"] = LuciHttp.formvalue("appId")
    payload["ids"] = LuciHttp.formvalue("ids")
    payload["hidden"] = false
    if LuciHttp.formvalue("hidden") == "true" then
        payload["hidden"] = true
    end
    tunnelRequestDatacenter(payload)
end

function getConfigInfo()
    local payload = {}
    payload["api"] = 1106
    payload["appid"] = LuciHttp.formvalue("appId")
    payload["key"] = LuciHttp.formvalue("key")
    tunnelRequestDatacenter(payload)
end
function connectedDevice()
    local payload = {}
    payload["api"] = 616
    payload["appid"] = LuciHttp.formvalue("appId")
    tunnelRequestDatacenter(payload)
end
function setConfigInfo()
    local payload = {}
    payload["api"] = 1107
    payload["appid"] = LuciHttp.formvalue("appId")
    payload["key"] = LuciHttp.formvalue("key")
    payload["value"] = LuciHttp.formvalue("value")
    tunnelRequestDatacenter(payload)
end
function enablePlugin()
    local payload = {}
    payload["api"] = 1108
    payload["appid"] = LuciHttp.formvalue("appId")
    payload["status"] = 5
    tunnelRequestDatacenter(payload)
end
function disablePlugin ()
    local payload = {}
    payload["api"] = 1108
    payload["appid"] = LuciHttp.formvalue("appId")
    payload["status"] = 6
    tunnelRequestDatacenter(payload)
end
function controlPlugin()
    local payload = {}
    payload["api"] = 600
    payload["pluginID"] = LuciHttp.formvalue("appId")
    payload["info"] = LuciHttp.formvalue("info")
    tunnelRequestDatacenter(payload)
end
function controlFeaturePlugin()
    local payload = {}
    payload["api"] = 634
    payload["pluginID"] = LuciHttp.formvalue("appId")
    payload["info"] = LuciHttp.formvalue("info")
    tunnelRequestDatacenter(payload)
end
function deleteDownload()
    local payload = {}
    payload["api"] = 1110
    payload["appid"] = LuciHttp.formvalue("appId")
    payload["idList"] = LuciHttp.formvalue("idList")
    payload["deletefile"] = false
    if LuciHttp.formvalue("deletefile") == "true" then
        payload["deletefile"] = true
    end
    tunnelRequestDatacenter(payload)
end
function pluginStatus()
    local payload = {}
    payload["api"] = 1111
    payload["appid"] = LuciHttp.formvalue("appId")
    tunnelRequestDatacenter(payload)
end
function pluginDownloadInfo()
    local payload = {}
    payload["api"] = 1109
    payload["appid"] = LuciHttp.formvalue("appId")
    payload["hidden"] = false
    if LuciHttp.formvalue("hidden") == "true" then
        payload["hidden"] = true
    end
    payload["lite"] = false
    if LuciHttp.formvalue("lite") == "true" then
        payload["lite"] = true
    end
    tunnelRequestDatacenter(payload)
end
function getYoukuStatus()
    local payload = {}
    payload["api"] = 634
    payload["pluginID"] = "2882303761517440411"
    local info = {}
    info["api"] = 4
    info["appid"] = LuciHttp.formvalue("appid")
    payload["info"] = info
    tunnelRequestDatacenter(payload)
end
function bindYoukuAppid()
    local payload = {}
    payload["api"] = 634
    payload["pluginID"] = "2882303761517440411"
    local info = {}
    info["api"] = 5
    info["appid"] = LuciHttp.formvalue("appid")
    info["ip"] = LuciHttp.formvalue("ip")
    info["token"] = LuciHttp.formvalue("token")
    payload["info"] = info
    tunnelRequestDatacenter(payload)
end

