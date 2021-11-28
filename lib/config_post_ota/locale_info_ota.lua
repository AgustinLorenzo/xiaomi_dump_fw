#!/usr/bin/lua

local uci = require("luci.model.uci").cursor()


-- this patch is ugly but should be
-- fix the config migration failed problem, which occurred when "ROUTER_LOCALE" does not exsit

function locale_info_set()
    local locale = uci.get("xiaoqiang", "common", "ROUTER_LOCALE")

    if locale then
        --print("locale already exist: " .. locale)
        return
    end

    locale = "somewhere"
    uci.set("xiaoqiang", "common", "ROUTER_LOCALE", locale)
    uci.commit("xiaoqiang")

    --print("locale set: " .. locale)

    return
end

locale_info_set()
