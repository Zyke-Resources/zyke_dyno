-- Printing result sheets at a dyno's screen, from the runs the server saved on that dyno, never what a client
-- sends. The spot is the one client/printout.lua marks, so change both together

local settings = Config.Settings.dyno
local printout = settings.printout

-- Metres from the floor under the print point, a little over the client's reach
local printReach = 4.0

-- Runs the list at the screen holds at most, newest first
local listLimit = 25

-- Milliseconds between two prints by one player
local printCooldownMs = 2000
---@type table<PlayerId, integer>
local printedAt = {}

-- Starts the player's wait when they may print again
---@param plyId PlayerId
---@return boolean waiting
local function isWaiting(plyId)
    local now = GetGameTimer()
    if (printedAt[plyId] and now - printedAt[plyId] < printCooldownMs) then return true end

    printedAt[plyId] = now

    return false
end

-- The printed sheet's description in the inventory, a labelled line for each figure. ox_inventory reads it as
-- markdown, where two spaces before a line break keep it a line of its own
---@param sheet DynoSheet
---@return string description
local function describeItem(sheet)
    local units = settings.units
    local power, torque = T("unit:" .. units.power), T("unit:" .. units.torque)
    local fields = {
        {"nui:vehicle", sheet.label},
        {"nui:plate", sheet.plate},
        {"nui:peakPower", ("%.0f %s %s %.0f %s"):format(DynoFormula.toPowerUnit(sheet.wheelKw), power, T("nui:at"), sheet.powerRpm, T("nui:rpm"))},
        {"nui:peakTorque", ("%.0f %s %s %.0f %s"):format(DynoFormula.toTorqueUnit(sheet.wheelNm), torque, T("nui:at"), sheet.torqueRpm, T("nui:rpm"))},
        {"nui:engine", ("%.0f %s"):format(DynoFormula.toPowerUnit(sheet.engineKw), power)},
        {"nui:drivetrain", sheet.drive},
        {"nui:date", os.date("%Y-%m-%d %H:%M", sheet.date)},
    }
    local lines = {}

    for i = 1, #fields do
        lines[i] = T("sheet:field", {T(fields[i][1]), fields[i][2]})
    end

    return table.concat(lines, "  \n")
end

-- The dyno stands between runs, the player stands at its screen and their job may use it
---@param plyId PlayerId
---@param dyno ZykeDyno
---@return boolean mayPrint
local function mayPrint(plyId, dyno)
    if (dyno.run) then return false end

    local floor = DynoGeometry.toWorld(dyno, DynoGeometry.getPrintFloor(dyno))
    if (#(GetEntityCoords(GetPlayerPed(plyId)).xy - floor.xy) > printReach) then return false end

    local jobs = dyno.jobs or settings.jobs

    return not jobs or Z.isJob(plyId, jobs)
end

---@param dyno ZykeDyno
---@param rowId integer
---@return DynoSheet? sheet
local function getRun(dyno, rowId)
    if (dyno.last and dyno.last.rowId == rowId) then return dyno.last end

    return DynoDatabase.getDynoRun(DynoDatabase.getKey(dyno), rowId)
end

if (printout.enabled) then
    -- The dyno's last runs as the list at its screen shows them, without their curves
    ---@param plyId PlayerId
    ---@param dynoId integer
    ---@return DynoPrintEntry[]? entries
    Z.callback.register("zyke_dyno:GetPrintList", function(plyId, dynoId)
        local dyno = GetDynos()[tonumber(dynoId) or 0]
        if (not dyno or not mayPrint(plyId, dyno)) then return nil end

        local runs = DynoDatabase.getDynoRuns(DynoDatabase.getKey(dyno), listLimit)
        local entries = {}

        for i = 1, #runs do
            local run = runs[i]

            entries[i] = {
                rowId = run.rowId,
                plate = run.plate,
                label = run.label,
                drive = run.drive,
                engineKw = run.engineKw,
                wheelKw = run.wheelKw,
                wheelNm = run.wheelNm,
                powerRpm = run.powerRpm,
                torqueRpm = run.torqueRpm,
                date = os.date("%Y-%m-%d %H:%M", run.date),
            }
        end

        return entries
    end)

    ---@param dynoId integer
    ---@param rowId integer
    RegisterNetEvent("zyke_dyno:PrintSheet", function(dynoId, rowId)
        local plyId = source
        local dyno = GetDynos()[tonumber(dynoId) or 0]
        if (not dyno or math.type(rowId) ~= "integer" or not mayPrint(plyId, dyno) or isWaiting(plyId)) then return end

        local sheet = getRun(dyno, rowId)
        if (not sheet) then Z.notify(plyId, "sheetGone") return end

        local metadata = Z.table.copy(sheet)

        -- ox_inventory names an item by its metadata's label, which would show the car's name instead of the sheet's
        metadata.car, metadata.label = metadata.label, nil
        metadata.compare = nil
        metadata.description = describeItem(sheet)

        if (not Z.addItem(plyId, printout.item, 1, metadata)) then Z.notify(plyId, "printFailed") return end

        Z.notify(plyId, "sheetPrinted")
    end)

    ---@param plyId PlayerId
    ---@param item? Item
    Z.registerUsableItem(printout.item, function(plyId, item)
        local metadata = item and item.metadata
        if (type(metadata) ~= "table" or not metadata.curve) then Z.notify(plyId, "sheetBlank") return end

        local sheet = Z.table.copy(metadata)

        sheet.label = sheet.car or sheet.label

        TriggerClientEvent("zyke_dyno:ShowSheet", plyId, sheet)
    end)
end

AddEventHandler("playerDropped", function()
    printedAt[source] = nil
end)

-- Prints the inputs of the car the player sits in, for tuning the formula's scale
---@param plyId PlayerId
Z.registerCommand(settings.calibrate.command, function(plyId)
    if (plyId <= 0) then return end

    TriggerClientEvent("zyke_dyno:Calibrate", plyId)
end, T("command:calibrate"), nil, {permission = settings.calibrate.permission, errorMsg = "noPermission"})