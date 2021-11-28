#!/usr/bin/lua
local px =  require "posix"
local uci=  require 'luci.model.uci'

function update_section(curs, conf, type, network, device, ifname)
    local id = nil
    curs:foreach(
        conf, type,
        function(s)
            if s['network'] == network and s['device'] == device and not s["ifname"] then
                id = s['.name']
            end
        end)
    if id then
        curs:set(conf, id, 'ifname', ifname)
    end
end


function update_wifi_disabled_section(curs, conf, type)
	local hardwaremodel = curs:get('misc','hardware','model')
	if hardwaremodel ~= 'R1D' then
		return
	end
	curs:foreach(
		conf,type,
		function(s)
			local enabled = curs:get(conf, s['.name'], 'enabled')
			local open = curs:get(conf, s['.name'], 'open')
			if open ~= nil then
				if open == '0' then
					curs:set(conf, s['.name'], 'disabled', '1')
				end
				curs:delete(conf, s['.name'],'open')
			end

			if enabled ~= nil then
				if enabled == '0' then
					curs:set(conf, s['.name'], 'disabled', '1')
				end
				curs:delete(conf, s['.name'], 'enabled')
			end
	end)

end

function update_wifi_aregion_section(curs, conf, type)
	local hardwaremodel = curs:get('misc','hardware','model')
	local country = curs:get('wireless','mt7615e5','country')
	if hardwaremodel ~= 'R3P' and hardwaremodel ~= 'R2600' then
		return
	elseif country ~= 'CN' then
		return
	end
	curs:foreach(
		conf,type,
		function(s)
			local aregion = curs:get(conf, s['.name'], 'aregion')
			if aregion ~= nil then
				if aregion ~= '0' then
					curs:set(conf, s['.name'], 'aregion', '0')
				end
			end
	end)

end

function add_miwifiready_section(curs, conf, type, name, network, device, ifname, mode, ssid, encryption, hidden, key, disabled, dynbcn)
    local exist = false
    local dynbcn_exist = false
    curs:foreach(
	conf,type,
	function(s)
		if s['.name'] == name then
			exist = true
		end
        if s['dynbcn'] == dynbcn then
            dynbcn_exist = true
        end
	end)
    if dynbcn_exist == false then
        curs:set(conf, name,'dynbcn', dynbcn)
    end
    if exist == false then
	curs:set(conf, name,'wifi-iface')
	curs:set(conf, name,'device', device)
	curs:set(conf, name,'network', network)
	curs:set(conf, name,'mode', mode)
	curs:set(conf, name,'ifname', ifname)
	curs:set(conf, name,'encryption', encryption)
	curs:set(conf, name,'key', key)
	curs:set(conf, name,'ssid', ssid)
	curs:set(conf, name,'disabled', disabled)
	curs:set(conf, name,'hidden', hidden)
    end
end

function delete_miwifiready_section(curs, conf, type, name)
    local exist = false

    curs:foreach(
        conf,type,
        function(s)
                if s['.name'] == name then
                        exist = true
                end
        end)

       if exist == true then
               curs:delete(conf, name)
       end
end

function add_minetready_section(curs, conf, type, name, network, device, ifname, mode, ssid, encryption, hidden, key, disabled, dynbcn, order)
    local exist = false

    curs:foreach(
	conf,type,
	function(s)
		if s['.name'] == name then
			exist = true
		end
    end)

    if exist == false then
	curs:set(conf, name,'wifi-iface')
	curs:set(conf, name,'device', device)
	curs:set(conf, name,'network', network)
	curs:set(conf, name,'mode', mode)
	curs:set(conf, name,'ifname', ifname)
	curs:set(conf, name,'encryption', encryption)
	curs:set(conf, name,'key', key)
	curs:set(conf, name,'ssid', ssid)
	curs:set(conf, name,'disabled', disabled)
	curs:set(conf, name,'hidden', hidden)
        curs:set(conf, name,'dynbcn', dynbcn)
        curs:reorder(conf, name, order)
    end
end

function add_guestwifi_section(curs, conf, type, name, network, device, ifname, mode, ssid, encryption, hidden, key, disabled)
    local exist = false
    curs:foreach(
    conf,type,
    function(s)
        if s['.name'] == name then
            exist = true
        end
    end)
    if exist == false then
        curs:set(conf, name,'wifi-iface')
        curs:set(conf, name,'device', device)
        curs:set(conf, name,'network', network)
        curs:set(conf, name,'mode', mode)
        curs:set(conf, name,'ifname', ifname)
        curs:set(conf, name,'disabled', disabled)
    end
end

function r3p_remove_nouse_section_option(curs, conf, type, name, hwband, hwmode)
    local hwband_exist = false
    local hwmode_exist = false

     curs:foreach(
         conf,type,
         function(s)
               if s['.name'] == name then
                    curs:delete(conf, s['.name'], 'bgprotect')
                    curs:delete(conf, s['.name'], 'beacon')
                    curs:delete(conf, s['.name'], 'dtim')
                    curs:delete(conf, s['.name'], 'fragthres')
                    curs:delete(conf, s['.name'], 'rtsthres')
                    curs:delete(conf, s['.name'], 'txpreamble')
                    curs:delete(conf, s['.name'], 'shortslot')
                    curs:delete(conf, s['.name'], 'txburst')
                    curs:delete(conf, s['.name'], 'pktaggre')
                    curs:delete(conf, s['.name'], 'igmpsnoop')
                    curs:delete(conf, s['.name'], 'ht_extcha')
                    curs:delete(conf, s['.name'], 'ht_opmode')
                    curs:delete(conf, s['.name'], 'ht_gi')
                    curs:delete(conf, s['.name'], 'ht_rdg')
                    curs:delete(conf, s['.name'], 'ht_stbc')
                    curs:delete(conf, s['.name'], 'ht_amsdu')
                    curs:delete(conf, s['.name'], 'ht_autoba')
                    curs:delete(conf, s['.name'], 'ht_badec')
                    curs:delete(conf, s['.name'], 'ht_ldpc')
                    curs:delete(conf, s['.name'], 'ht_txstream')
                    curs:delete(conf, s['.name'], 'ht_rxstream')
                    curs:delete(conf, s['.name'], 'ht_bsscoexist')
                    curs:delete(conf, s['.name'], 'g256qam')
                    curs:delete(conf, s['.name'], 'vht_stbc')
                    curs:delete(conf, s['.name'], 'vht_sgi')
                    curs:delete(conf, s['.name'], 'vht_bw_sig')
                    curs:delete(conf, s['.name'], 'vht_ldpc')
                    curs:delete(conf, s['.name'], 'mutxrxenable')
                    curs:delete(conf, s['.name'], 'rdregion')
                    curs:delete(conf, s['.name'], 'band')
                    curs:delete(conf, s['.name'], 'wifimode')
               end

               if s['hwband'] == hwband then
                       hwband_exist = true
               end

               if s['hwmode'] == hwmode then
                       hwmode_exist = true
               end

       end)

       if hwband_exist == false then
               curs:set(conf, name,'hwband', hwband)
       end

       if hwmode_exist == false then
               curs:set(conf, name,'hwmode', hwmode)
       end
end

function update_wifi_txbf_section(curs, conf, type)
	local hardwaremodel = curs:get('misc','hardware','model')
	local country = curs:get('wireless','wifi1','country')
	if hardwaremodel ~= 'D01' or country ~= 'CN' then
		return
	end
	curs:foreach(
		conf,type,
		function(s)
			local txbf = curs:get(conf, s['.name'], 'txbf')
			if txbf ~= nil then
				if txbf ~= '0' then
					curs:set(conf, s['.name'], 'txbf', '0')
				end
			end
	end)

end

function main()

    local curs = uci.cursor()
    local hardwaremodel = curs:get('misc','hardware','model')

    -- r1d
    update_section(curs, 'wireless', 'wifi-iface', 'lan', 'wl0', 'wl0')
    update_section(curs, 'wireless', 'wifi-iface', 'lan', 'wl1', 'wl1')
    update_section(curs, 'wireless', 'wifi-iface', 'guest', 'wl1', 'wl1.2')
    if hardwaremodel == 'R1D' or hardwaremodel == 'R2D' then
        miwifiready_section(curs, 'wireless', 'wifi-iface', 'miwifi_ready', 'ready', 'wl1', 'wl1.3', 'ap', 'miwifi_ready', 'none', '1', '', '', '1')
    end
    update_wifi_disabled_section(curs, 'wireless', 'wifi-iface')
    -- r1cm
    update_section(curs, 'wireless', 'wifi-iface', 'lan', 'mt7612', 'wl0')
    update_section(curs, 'wireless', 'wifi-iface', 'lan', 'mt7620', 'wl1')
    if hardwaremodel == 'R1CM' or hardwaremodel == 'R3' then
        -- add_miwifiready_section(curs, 'wireless', 'wifi-iface', 'miwifi_ready', 'ready', 'mt7620', 'wl2', 'ap', 'miwifi_ready', 'none', '1', '', '', '1')
        delete_miwifiready_section(curs, 'wireless', 'wifi-iface', 'miwifi_ready')
        add_minetready_section(curs, 'wireless', 'wifi-iface', 'minet_ready', 'ready', 'mt7620', 'wl2', 'ap', 'minet_ready', 'none', '1', '', '0', '1', '4')
        add_guestwifi_section(curs, 'wireless', 'wifi-iface', 'guest_2G', 'guest', 'mt7620', 'wl3', 'ap', 'guest_2G', 'none', '1', '', '1')
    end
    -- r1cl
    update_section(curs, 'wireless', 'wifi-iface', 'lan', 'mt7628', 'wl1')
    if hardwaremodel == 'R1CL' or hardwaremodel == 'R3L' then
        -- add_miwifiready_section(curs, 'wireless', 'wifi-iface', 'miwifi_ready', 'ready', 'mt7628', 'wl2', 'ap', 'miwifi_ready', 'none', '1', '', '', '1')
        delete_miwifiready_section(curs, 'wireless', 'wifi-iface', 'miwifi_ready')
        add_minetready_section(curs, 'wireless', 'wifi-iface', 'minet_ready', 'ready', 'mt7628', 'wl2', 'ap', 'minet_ready', 'none', '1', '', '0', '1', '2')
        add_guestwifi_section(curs, 'wireless', 'wifi-iface', 'guest_2G', 'guest', 'mt7628', 'wl3', 'ap', 'guest_2G', 'none', '1', '', '1')
    end
    if hardwaremodel == 'R3P' or hardwaremodel == 'R2600' then
        r3p_remove_nouse_section_option(curs, 'wireless', 'wifi-device', 'mt7615e2', '2_4G', '11ng')
        r3p_remove_nouse_section_option(curs, 'wireless', 'wifi-device', 'mt7615e5', '5G', '11ac')
        update_wifi_aregion_section(curs, 'wireless', 'wifi-device')
    end
    -- R4
    if hardwaremodel == 'R4' or hardwaremodel == 'R3G' or hardwaremodel == 'R4A' or hardwaremodel == 'R3GV2' or hardwaremodel == 'R2100' then
        delete_miwifiready_section(curs, 'wireless', 'wifi-iface', 'miwifi_ready')
        add_minetready_section(curs, 'wireless', 'wifi-iface', 'minet_ready', 'ready', 'mt7603e', 'wl2', 'ap', 'minet_ready', 'none', '1', '', '0', '1', '2')
    end
    -- R4AC and R3A
    if hardwaremodel == 'R4AC' or hardwaremodel == 'R3A' then
        delete_miwifiready_section(curs, 'wireless', 'wifi-iface', 'miwifi_ready')
        add_minetready_section(curs, 'wireless', 'wifi-iface', 'minet_ready', 'ready', 'mt7628', 'wl2', 'ap', 'minet_ready', 'none', '1', '', '0', '1', '4')
    end
    -- R4CM
    if hardwaremodel == 'R4CM' then
        delete_miwifiready_section(curs, 'wireless', 'wifi-iface', 'miwifi_ready')
        add_minetready_section(curs, 'wireless', 'wifi-iface', 'minet_ready', 'ready', 'mt7628', 'wl2', 'ap', 'minet_ready', 'none', '1', '', '0', '1', '2')
    end
    -- D01
    if hardwaremodel == 'D01' then
        update_wifi_txbf_section(curs, 'wireless', 'wifi-device')
    end

    curs:save('wireless')
    curs:commit('wireless')

end

main()




