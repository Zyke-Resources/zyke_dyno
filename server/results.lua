-- A finished run's result, worked out on the server from the same inputs and seed the clients drew the run from

DynoResults = {}

local settings = Config.Settings.dyno

---@param values number[]
---@return number[] rounded @ To a tenth, to keep the history and state small
local function roundAll(values)
    local rounded = {}

    for i = 1, #values do
        rounded[i] = math.floor(values[i] * 10.0 + 0.5) / 10.0
    end

    return rounded
end

---@param dynoId integer
---@param run ZykeDynoRun
---@return DynoSheet sheet
function DynoResults.build(dynoId, run)
    local curve = DynoFormula.getCurve(run.inputs, run.seed)
    local previous = run.compare and run.compare.previous

    return {
        runId = run.id,
        dynoId = dynoId,
        plate = run.plate,
        label = run.label,
        model = run.inputs.model,
        drive = run.inputs.drive,
        driver = run.driver,
        date = os.time(),
        engineKw = curve.engineKw,
        wheelKw = curve.wheelKw,
        wheelNm = curve.wheelNm,
        powerRpm = curve.powerRpm,
        torqueRpm = curve.torqueRpm,
        loss = curve.loss,
        redlineSpeed = DynoFormula.getRedlineSpeed(run.inputs),
        gear = DynoFormula.getGear(run.inputs),
        curve = {startRpm = curve.startRpm, redline = curve.redline, power = roundAll(curve.power), torque = roundAll(curve.torque)},
        compare = run.compare,
        gain = previous and {wheelKw = curve.wheelKw - previous.wheelKw, wheelNm = curve.wheelNm - previous.wheelNm} or nil,
    }
end

-- The sheet without the driver, as other players and the screen get it
---@param sheet DynoSheet
---@return DynoSheet summary
function DynoResults.getSummary(sheet)
    local summary = Z.table.copy(sheet)

    summary.driver = nil

    return summary
end

---@param sheet DynoSheet
---@return string text @ The run in one line, as a printed sheet's description and in the log
function DynoResults.describe(sheet)
    local units = settings.units

    return T("sheet:line", {
        ("%.0f"):format(DynoFormula.toPowerUnit(sheet.wheelKw)), T("unit:" .. units.power),
        ("%.0f"):format(DynoFormula.toTorqueUnit(sheet.wheelNm)), T("unit:" .. units.torque),
        ("%.0f"):format(DynoFormula.toPowerUnit(sheet.engineKw)), T("unit:" .. units.power),
        sheet.drive,
    })
end

---@param sheet DynoSheet
function DynoResults.finish(sheet)
    sheet.rowId = DynoDatabase.save(sheet)

    OnDynoRunFinished(sheet)
    TriggerEvent("zyke_dyno:OnRunFinished", DynoResults.getSummary(sheet))
end

-- Exports, see the documentation

---@param plate string
---@return DynoSheet? sheet @ The car's last saved run
exports("GetLastResult", function(plate)
    return DynoDatabase.getLast(TrimPlate(plate))
end)

---@param plate string
---@param limit? integer
---@return DynoSheet[] sheets @ Newest first
exports("GetResults", function(plate, limit)
    return DynoDatabase.getRuns(TrimPlate(plate), limit)
end)