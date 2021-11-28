module ("xiaoqiang.module.XQDisk", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local LuciUtil = require("luci.util")

local IOSTATUS_CMD = "iostat -d 1 2 | grep -w sda | tail -1 | awk '{print $3,$4,$5,$6}'"
local DISKINFO_CMD = "hdparm -I /dev/sda"
local SMARTCTL_CMD = "smartctl -A /dev/sda -s on"

function iostatus()
    local result = {
        ["rrate"] = 0, -- Blk_read/s  读速度
        ["wrate"] = 0, -- Blk_wrtn/s  写速度
        ["read"]  = 0, -- Blk_read    当前总读量
        ["write"] = 0  -- Blk_wrtn    当前总写量
    }
    local status = LuciUtil.exec(IOSTATUS_CMD)
    if not XQFunction.isStrNil(status) then
        status = LuciUtil.split(LuciUtil.trim(status), " ")
        result["rrate"] = status[1] * 512
        result["wrate"] = status[2] * 512
        result["read"]  = status[3] * 512
        result["write"] = status[4] * 512
    end
    return result
end

function diskInfo()
    local result = {
        ["model"]   = "", -- Model Number    磁盘版本号、型号
        ["serial"]  = "", -- Serial Number   磁盘序列号
        ["size"]    = "", -- device size with M = 1000*1000 (MBytes)  磁盘的容量
        ["factor"]  = "", -- Form Factor     磁盘的尺寸
        ["rorate"]  = "", -- Nominal Media Rotation Rate  磁盘的转速
        ["filesys"] = "", -- File system     文件系统
        ["sata"]    = ""  -- SATAI/II/III
    }
    local info = LuciUtil.execl(DISKINFO_CMD)
    if info then
        for _, line in ipairs(info) do
            if not XQFunction.isStrNil(line) then
                if line:match("Model Number:") then
                    result["model"] = LuciUtil.trim(line:match("Model Number:%s+(.+)"))
                elseif line:match("Serial Number:") then
                    result["serial"] = LuciUtil.trim(line:match("Serial Number:%s+(.+)"))
                elseif line:match("device size with M = 1000%*1000:") then
                    result["size"] = line:match("device size with M = 1000%*1000:%s+(%d+)")
                elseif line:match("Form Factor:") then
                    result["factor"] = line:match("Form Factor:%s+(%S+)")
                elseif line:match("Nominal Media Rotation Rate:") then
                    result["rorate"] = line:match("Nominal Media Rotation Rate:%s+(%d+)")
                elseif line:match("Gen1 signaling speed") then
                    result["sata"] = "SATAI"
                elseif line:match("Gen2 signaling speed") then
                    result["sata"] = "SATAII"
                elseif line:match("Gen3 signaling speed") then
                    result["sata"] = "SATAIII"
                end
            end
        end
    end
    result.filesys = "EXT4"
    return result
end

function smartctl()
    local result = {
        ["sectorcount"]   = "", -- Reallocated_Sector_Ct   重新映射的扇区数
        ["poweronhours"]  = "", -- Power_On_Hours          开机时间（小时）
        ["spinretry"]     = "", -- Spin_Retry_Count        硬盘主轴运转重试数
        ["temperature"]   = "", -- Temperature_Celsius     磁盘温度
        ["reventcount"]   = "", -- Reallocated_Event_Count 扇区数据转移次数
        ["pendingsector"] = "", -- Current_Pending_Sector  不稳定状态扇区数
        ["uncorrectable"] = "", -- Offline_Uncorrectable   错误状态扇区数
        ["filesystem"]    = ""  -- filesys error           文件系统错误
    }
    local info = LuciUtil.execl(SMARTCTL_CMD)
    local diskstatus = get_diskstatus()
    if diskstatus == 2 or diskstatus == 0 then
        result.filesystem = "0"
    else
        result.filesystem = "1"
    end
    if info then
        for _, line in ipairs(info) do
            if not XQFunction.isStrNil(line) then
                if line:match("Reallocated_Sector_Ct") then
                    result["sectorcount"] = tostring(LuciUtil.trim(line:sub(88, #line)))
                elseif line:match("Power_On_Hours") then
                    result["poweronhours"] = tostring(LuciUtil.trim(line:sub(88, #line)))
                elseif line:match("Spin_Retry_Count") then
                    result["spinretry"] = tostring(LuciUtil.trim(line:sub(88, #line)))
                elseif line:match("Temperature_Celsius") then
                    local tm = LuciUtil.trim(line:sub(88, #line))
                    local tmperature = {
                        ["current"] = "0",
                        ["min"] = "0",
                        ["max"] = "0"
                    }
                    tmperature.current, tmperature.min, tmperature.max = tm:match("(%d+)%s%S+%s+(%d+)/(%d+)")
                    result["temperature"] = tmperature
                elseif line:match("Reallocated_Event_Count") then
                    result["reventcount"] = tostring(LuciUtil.trim(line:sub(88, #line)))
                elseif line:match("Current_Pending_Sector") then
                    result["pendingsector"] = tostring(LuciUtil.trim(line:sub(88, #line)))
                elseif line:match("Offline_Uncorrectable") then
                    result["uncorrectable"] = tostring(LuciUtil.trim(line:sub(88, #line)))
                end
            end
        end
    end
    return result
end

-- get disk status
-- 0:没有检测
-- 1:检测中
-- 2:优
-- 3:良
-- 4:差
-- 5:出错:停止插件服务或umount磁盘失败
-- 6:出错:未知磁盘无法操作
-- 7:出错:未挂载磁盘
-- 8:出错:未知错误
function get_diskstatus()
    local XQPreference = require("xiaoqiang.XQPreference")
    local status = tonumber(XQPreference.get("DISK_STATUS_NEW"))
    if not status then
        local hdd = hdd_status()
        if hdd == 0 then
            status = 2
        elseif hdd == 1 then
            status = 3
        elseif hdd == 2 then
            status = 4
        elseif hdd == 99 then
            status = 6
        elseif hdd == 98 then
            status = 8
        end
    end
    return status
end

-- get disk mount status
-- 0：SATA接口无硬盘
-- 1：SATA接口有硬盘，正常初始化。主磁盘分区状态正常
-- 2：SATA接口有硬盘但是未初始化。主磁盘分区不可用
-- 3：SATA接口有硬盘但是硬盘损坏
function get_diskmstatus()
    local uci = require("luci.model.uci").cursor()
    local status = uci:get("disk", "primary", "status") or 1
    return tonumber(status)
end

-- get disk repair status
-- 0:没有修复
-- 1:修复中
-- 2:修复成功
-- 3:修复失败
-- 4:出错:停止插件服务或umount磁盘失败
function get_repairstatus()
    local XQPreference = require("xiaoqiang.XQPreference")
    local status = tonumber(XQPreference.get("DISK_REPAIR_STATUS")) or 0
    return status
end

-- get disk format status
-- 0:未格式化
-- 1:正在格式化
-- 2:格式化成功
-- 3:格式化失败
function get_formatstatus()
    local XQPreference = require("xiaoqiang.XQPreference")
    local status = tonumber(XQPreference.get("DISK_FORMAT_STATUS")) or 0
    return status
end

function disk_check(notify)
    if notify then
        XQFunction.forkExec("lua /usr/sbin/disk_helper.lua check notify")
    else
        XQFunction.forkExec("lua /usr/sbin/disk_helper.lua check")
    end
    return true
end

function disk_repair(notify)
    if notify then
        XQFunction.forkExec("lua /usr/sbin/disk_helper.lua repair notify")
    else
        XQFunction.forkExec("lua /usr/sbin/disk_helper.lua repair")
    end
    return true
end

-- save disk status
function save_diskstatus(status)
    local XQPreference = require("xiaoqiang.XQPreference")
    XQPreference.set("DISK_STATUS_NEW", tostring(status))
end

-- save disk repair status
function save_diskrstatus(status)
    local XQPreference = require("xiaoqiang.XQPreference")
    XQPreference.set("DISK_REPAIR_STATUS", tostring(status))
end

-- save disk format status
function save_diskfstatus(status)
    local XQPreference = require("xiaoqiang.XQPreference")
    XQPreference.set("DISK_FORMAT_STATUS", tostring(status))
end

-- hdd status
-- @return 0=GOOD 1=FINE 2=CRITICAL 98=UNKNOWN 99=NO_DISK
function hdd_status()
    local code = tonumber(LuciUtil.trim(LuciUtil.exec("/usr/sbin/hddstatus; echo $?") or "")) or 0
    return code
end

-- stop datacenter service and umount userdisk
function diskchk_prepare()
    return os.execute("/usr/sbin/diskchk prepare") == 0
end

-- disk check
function diskchk_probe()
    return os.execute("/usr/sbin/diskchk probe") == 0
end

-- restore datacenter service and mount userdisk
function diskchk_restore()
    return os.execute("/usr/sbin/diskchk restore") == 0
end

function diskchk_fix()
    local code = tonumber(LuciUtil.trim(LuciUtil.exec("/usr/sbin/diskchk fix; echo $?") or "")) or 0
    return code <= 2
end

-- disk init
function disk_init()
    XQFunction.forkExec("/usr/sbin/format_userdisk part >/dev/null 2>/dev/null")
end

-- disk format
function disk_format()
    return tonumber(os.execute("/usr/sbin/format_userdisk fs >/dev/null 2>/dev/null")) == 0
end

function disk_format_async()
    XQFunction.forkExec("lua /usr/sbin/disk_helper.lua format >/dev/null 2>/dev/null")
end

-------------------------------------------------------------------------------------------
----------------------------------------Disk v2--------------------------------------------
-------------------------------------------------------------------------------------------
-- @return 0=GOOD 1=FINE 2=CRITICAL 98=UNKNOWN 99=NO_DISK
function disk_status_v2()
    return hdd_status()
end

function smartctl_info_v2()
    local result = {}
    local info = LuciUtil.execl(SMARTCTL_CMD)
    if info then
        for _, line in ipairs(info) do
            if not XQFunction.isStrNil(line) then
                local id,name,flag,value,worst,thresh,stype,updated,whenfailed,rawvalue = line:match("(%d+)%s(%S+)%s+(%S+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
                if id and name and flag and value and worst and thresh and stype and updated and whenfailed and rawvalue then
                    local key = string.lower(name)
                    if key == "raw_read_error_rate" or key == "temperature_celsius" or key == "airflow_temperature_cel" or key == "spin_up_time" then
                        whenfailed = "-"
                    end
                    if key == "current_pending_sector" then
                        if tonumber(rawvalue) > 10 then
                            whenfailed = "FAILING_NOW"
                        end
                    end
                    table.insert(result, {
                        ["ID"] = id,
                        ["ATTRIBUTE_NAME"] = name,
                        ["FLAG"] = flag,
                        ["VALUE"] = value,
                        ["WORST"] = worst,
                        ["THRESH"] = thresh,
                        ["TYPE"] = stype,
                        ["UPDATED"] = updated,
                        ["WHEN_FAILED"] = whenfailed,
                        ["RAW_VALUE"] = rawvalue
                    })
                end
            end
        end
    end
    return result
end