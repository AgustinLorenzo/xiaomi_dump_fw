local suc, json = pcall(require, "cjson")

if not suc then
    json = require("json")
end

local kvStore = require("xiaoqiang.module.XQKVStore")

local kv = kvStore.getRouterKV()

print(json.encode(kv))