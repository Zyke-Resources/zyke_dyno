-- The player's own NUI, which shows result sheets. The dyno screen's DUI is the same page, see client/screen.lua

DynoNui = {}

-- Every word the page shows, sent once it has loaded
---@return table<string, string> labels
function DynoNui.getLabels()
    local labels = {}

    for _, key in ipairs({"nui:power", "nui:torque", "nui:wheel", "nui:engine", "nui:rpm", "nui:drivetrain", "nui:loss", "nui:gain", "nui:previous", "nui:first", "nui:thisRun", "nui:standby", "nui:standbyHint", "nui:lastRun", "nui:peakPower", "nui:peakTorque", "nui:redlineSpeed", "nui:sheetTitle", "nui:gear", "nui:at", "nui:noGain", "nui:speed", "nui:printTitle", "nui:vehicle", "nui:plate", "nui:date", "nui:run", "nui:engineSpeed", "nui:maxPower", "nui:maxTorque", "nui:footnote", "title:dyno", "unit:hp", "unit:ps", "unit:kw", "unit:nm", "unit:lbft", "unit:kmh", "unit:mph"}) do
        labels[key:gsub("^%a+:", "", 1)] = T(key)
    end

    return labels
end

---@param sheet? DynoSheet @ nil hides it
function DynoNui.showSheet(sheet)
    SendNUIMessage({event = "Sheet", data = sheet or {}})
end

---@param _ table
---@param cb fun(result: table)
RegisterNUICallback("Ready", function(_, cb)
    SendNUIMessage({event = "Labels", data = {labels = DynoNui.getLabels(), units = Config.Settings.dyno.units}})
    cb({})
end)