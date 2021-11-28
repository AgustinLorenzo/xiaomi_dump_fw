#!/usr/bin/lua
-- it's executed after OTA to upgrade cfg to new version


-- local bit=  require "bit"
local uci=  require 'luci.model.uci'
-- local json= require 'json'
local curs = uci.cursor()

-- only merge named sections, not touch anonmous sections
function merge_tbl(cfg_from, cfg_to, t_type)
        curs:foreach(
            cfg_from, t_type,
            function(s)
                   if not s['.anonymous'] and not curs:get(cfg_to,t_type,s['.name']) then
                           new_name = curs:section(cfg_to,t_type,s['.name'])
                           for k,v in pairs(s) do
                                -- only support flat config structure
                                if type(v) == 'string' then
                                    curs:set(cfg_to,new_name,k,v)
                                elseif type(v) == 'table' then
                                    val = curs:get_list(cfg_from,s['.name'],k)
                                    curs:set_list(cfg_to,s['.name'],k,val)
                                else
                                    -- not supported
                                end
                           end
                   end
            end
        )
end


function main()

    local from_cfg='firewall_default'
    local to_cfg='firewall'
    merge_tbl(from_cfg,to_cfg,'include')
    merge_tbl(from_cfg,to_cfg,'rule')
    merge_tbl(from_cfg,to_cfg,'zone')
    merge_tbl(from_cfg,to_cfg,'redirect')

    -- use this form to set options for anonymous section.
    curs:foreach("firewall", "defaults",
		 function(s)
		    curs:set("firewall",s[".name"],"drop_invalid","1")
		    curs:set("firewall",s[".name"],"disable_ipv6","1")
		 end)
    curs:save(to_cfg)
    curs:commit(to_cfg)

    os.remove('/etc/config/firewall_default')
end

main()





