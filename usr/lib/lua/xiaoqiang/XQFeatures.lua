module "xiaoqiang.XQFeatures"


FEATURES = {
    ["system"] = {
        ["shutdown"] = "0",
        ["downloadlogs"] = "0",
        ["i18n"] = "0",
        ["infileupload"] = "1",        
        ["task"] = "0"
    },
    ["wifi"] = {
        ["wifi24"] = "1",
        ["wifi50"] = "1",
        ["wifiguest"] = "1",
        ["wifimerge"] = "1"
    },
    ["apmode"] = {
        ["wifiapmode"] = "1",
        ["lanapmode"] = "1"
    },
    ["netmode"] = {
        ["elink"] = "1"
    },
    ["apps"] = {
        ["apptc"] = "0",
        ["qos"] = "1"
    },
    ["hardware"] = {
        ["usb"] = "0",
        ["usb_deploy"] = "0",
        ["disk"] = "0"
    }
}