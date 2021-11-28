local fs    = require("nixio.fs")
local nixio = require("nixio")
local ecos  = require("xiaoqiang.module.XQEcos")

local mac = arg[1]

function wget(link, filepath)
    local xqcrypto = require("xiaoqiang.util.XQCryptoUtil")
    local download = "wget -t3 -T30 '"..link.."' -O "..filepath
    os.execute(download)
    return xqcrypto.md5File(filepath)
end

function echo(mac, status)
    if mac and status then
        local sfile = "/tmp/"..mac
        os.execute("echo "..status.." > "..sfile)
    end
end

-- 1: 正在处理
-- 2: 没有ECOS设备，不能升级
-- 3: 该ECOS设备，没有升级信息
-- 4: ECOS升级包下载失败
-- 5: 刷写ECOS升级包失败
-- 6: 升级成功
-- 7: 签名校验失败
if mac then
    echo(mac, "1")
    local dev = ecos._getEcosDevices()[mac]
    if dev then
        local check = ecos._getEcosUpgrade(dev.version, dev.channel, dev.sn, dev.ctycode)
        if check then
            local tfile = "/tmp/"..check.fullHash..".img"
            if wget(check.downloadUrl, tfile) == check.fullHash then
                local ret = os.execute("cd /tmp && mk_ecos_image -x "..tfile)
                if ret ~= 0 then
                    echo(mac, "7")
                    return
                end

                local code = os.execute("tbus postfile "..dev.ip.." ".."/tmp/eCos.img")
                if code ~= 0 then
                    echo(mac, "5")
                else
                    echo(mac, "6")
                end
            else
                echo(mac, "4")
            end
            os.execute("rm /tmp/eCos.img "..tfile.." 2>/dev/null >/dev/null")
        else
            echo(mac, "3")
        end
    else
        echo(mac, "2")
    end
end
