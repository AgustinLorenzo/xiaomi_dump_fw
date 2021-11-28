
local DIR_INFO = "/tmp/dir_info"

function execl(command)
    local pp   = io.popen(command)
    local line = ""
    local data = {}

    while true do
        line = pp:read()
        if (line == nil) then break end
        data[#data+1] = line
    end
    pp:close()

    return data
end

function dir(path)
    local json = require("json")
    local result = {
        ["total"] = "",
        ["info"] = {}
    }
    local dpath = dpath or "/tmp/userdisk/data/"
    if not dpath:match("/$") then
        dpath = dpath.."/"
    end
    local info = execl("du -h -d 1 "..dpath)
    local count = #info
    for index, line in ipairs(info) do
        if line then
            local size, path = line:match("(%S+)%s+(%S+)")
            if path and index ~= count then
                local item = {
                    ["name"] = path:gsub(dpath, ""),
                    ["size"] = size,
                    ["path"] = path,
                    ["type"] = "folder"
                }
                table.insert(result.info, item)
            elseif path and index == count then
                result.total = size
            end
        end
    end
    local fileinfo = execl("ls -lh "..dpath)
    for _, line in ipairs(fileinfo) do
        if line then
            local mod, size = line:match("(%S+)%s+%S+%s+%S+%s+%S+%s+(%S+)%s+")
            local filename = line:match("%s(%S+)$")
            if mod and not mod:match("^d") then
                local item = {
                    ["name"] = filename,
                    ["size"] = size,
                    ["path"] = dpath..filename,
                    ["type"] = "file"
                }
                table.insert(result.info, item)
            end
        end
    end
    if result.total ~= "" then
        local fp = io.open(DIR_INFO, "w")
        if fp then
            fp:write(json.encode(result))
            fp:close()
        end
    end
end

function check_file()
    local fp = io.open(DIR_INFO, "r")
    if fp then
        fp:close()
        return true
    else
        return false
    end
end

while true do
    dir()
    if check_file() then
        break
    else
        os.execute("sleep 100")
    end
end