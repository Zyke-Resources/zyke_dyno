fx_version "cerulean"
game "gta5"
author "https://discord.zykeresources.com"
description "A chassis dyno with an open formula: a live power and torque graph on a screen beside it, history by plate, printed sheets and an export surface for integrations"
lua54 "yes"
version "1.0.0"

shared_scripts {
    "@zyke_lib/imports.lua",
    "shared/config.lua",
    "shared/dynos.lua",
    "shared/geometry.lua",
    "shared/formula.lua",
    "shared/run.lua",
}

client_scripts {
    "client/can_checks.lua",
    "client/dynos.lua",
    "client/draw.lua",
    "client/inputs.lua",
    "client/nui.lua",
    "client/props.lua",
    "client/screen.lua",
    "client/sheet.lua",
    "client/printout.lua",
    "client/live.lua",
    "client/run.lua",
    "client/guide.lua",
    "client/laptop.lua",
    "client/admin.lua",
}

server_scripts {
    "@oxmysql/lib/MySQL.lua",
    "server/can_checks.lua",
    "server/hooks.lua",
    "server/database.lua",
    "server/results.lua",
    "server/dynos.lua",
    "server/share.lua",
    "server/saved.lua",
    "server/laptop.lua",
    "server/placed.lua",
    "server/admin.lua",
}

ui_page "nui/index.html"

files {
    "nui/**/*",
    "web/**/*",
    "stream/zyke_dyno.ytyp",
    "stream/zyke_dyno_screen.ytyp",
    "stream/zyke_dyno_bike.ytyp",
    "locales/*.lua",
}

data_file "DLC_ITYP_REQUEST" "stream/zyke_dyno.ytyp"
data_file "DLC_ITYP_REQUEST" "stream/zyke_dyno_screen.ytyp"
data_file "DLC_ITYP_REQUEST" "stream/zyke_dyno_bike.ytyp"

dependencies {
    "zyke_lib",
    "oxmysql",
}