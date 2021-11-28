local wifi = require("xiaoqiang.util.XQWifiUtil")
local crypto = require("xiaoqiang.util.XQCryptoUtil")

local guest_bssid = wifi.getGuestWifiBssid()

if guest_bssid then
    os.execute("matool --method setKVB64 --params bssid_guest "..crypto.binaryBase64Enc(guest_bssid))
end