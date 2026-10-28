-- Editable reactions to runs; other resources can listen to the zyke_dyno:OnRunStarted,
-- zyke_dyno:OnRunFinished and zyke_dyno:OnRunAborted server events instead of editing this file
-- For Discord webhooks, set a URL per action in zyke_lib/webhooks/dyno.lua

-- Runs once a run has finished and its result is saved. sheet.driver is the player who drove it
---@param sheet DynoSheet
function OnDynoRunFinished(sheet)
    Z.log({
        action = "RunFinished",
        handler = sheet.driver and Z.getIdentifier(sheet.driver) or "server",
        message = ("%s (%s): %s"):format(sheet.label, sheet.plate, DynoResults.describe(sheet)),
        rawData = {dynoId = sheet.dynoId, plate = sheet.plate, model = sheet.model, wheelKw = sheet.wheelKw, wheelNm = sheet.wheelNm, engineKw = sheet.engineKw, gain = sheet.gain},
    })
end