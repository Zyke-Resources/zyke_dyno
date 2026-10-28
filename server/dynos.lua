-- Every dyno, its run and the exports. The server checks the start, watches the run and builds the result itself

local settings = Config.Settings.dyno

local watchMs = 500

-- Metres from the dyno's middle
local startReach = 6.0

local sampleMinMs = 50
-- Counted after the rear rollers have slid under the car
local minPullMs = 2000

-- See shared/run.lua
local phases = {ready = true, pull = true, limiter = true, coast = true}

-- Game timer by dyno ID
---@type table<integer, integer>
local sampledAt = {}

-- Highest values a client may send
local inputLimits = {force = 2.0, mass = 30000.0, topSpeed = 500.0, gears = 10, engineModifier = 2000.0, cheat = 10.0, extra = 10.0, wheelRadius = 2.0, frontRadius = 2.0, wheelbase = 8.0}

---@type table<integer, ZykeDyno>
local dynos = {}
local lastDynoId = 0

---@class DynoRunCheck
---@field canRun fun(data: DynoRunCheckData): boolean, string?
---@field resource string

---@type table<string, DynoRunCheck>
local runChecks = {}

local function publish()
    GlobalState.zykeDynos = dynos
end

---@return table<integer, ZykeDyno> dynos
function GetDynos()
    return dynos
end

---@param plate string
---@return string trimmed
function TrimPlate(plate)
    return (plate:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A screen another resource gave, kept only in the shape every client reads it in
---@param screen any
---@return {offset: vector3, heading: number}? screen
local function readScreen(screen)
    if (type(screen) ~= "table" or type(screen.offset) ~= "vector3") then return nil end

    local heading = tonumber(screen.heading) or 0.0
    if (heading ~= heading) then return nil end

    return {offset = screen.offset, heading = heading % 360.0}
end

---@param options {coords: vector3, heading?: number, kind?: DynoKind, screen?: {offset: vector3, heading: number}, jobs?: string[] | string, label?: string}
---@param resource string @ The resource that stands it; its dynos go when it stops
---@param placed? boolean @ Placed with the admin tool, see server/admin.lua
---@return integer? dynoId
function CreateDyno(options, resource, placed)
    if (type(options) ~= "table" or type(options.coords) ~= "vector3") then return nil end
    if (options.kind ~= nil and not DynoGeometry.kinds[options.kind]) then return nil end

    for dynoId, dyno in pairs(dynos) do
        if (#(dyno.coords - options.coords) < 0.5) then return dynoId end
    end

    local label = type(options.label) == "string" and options.label:sub(1, 48) or nil

    lastDynoId += 1
    dynos[lastDynoId] = {coords = options.coords, heading = (tonumber(options.heading) or 0.0) % 360.0, kind = options.kind or "car", screen = readScreen(options.screen), jobs = options.jobs, label = label, resource = resource, placed = placed}

    publish()

    return lastDynoId
end

-- Takes a dyno away, stopping the run on it
---@param dynoId integer
---@return boolean removed
function RemoveDyno(dynoId)
    if (not dynos[dynoId]) then return false end

    AbortDynoRun(dynoId, "reason:stopped")

    dynos[dynoId] = nil

    publish()

    return true
end

-- The inputs a client sent, kept to what a vehicle can have
---@param payload any
---@return DynoInputs? inputs
local function readInputs(payload)
    if (type(payload) ~= "table" or type(payload.model) ~= "string") then return nil end
    if (payload.drive ~= "FWD" and payload.drive ~= "RWD" and payload.drive ~= "AWD") then return nil end

    local inputs = {model = payload.model:sub(1, 32), drive = payload.drive, turbo = payload.turbo == true, class = math.floor(tonumber(payload.class) or -1)}

    for field, limit in pairs(inputLimits) do
        local value = tonumber(payload[field])
        if (not value or value ~= value or value < 0.0 or value > limit) then return nil end

        inputs[field] = value
    end

    if (inputs.gears < 1 or inputs.wheelRadius < 0.1 or inputs.frontRadius < 0.1) then return nil end

    return inputs
end

---@param data DynoRunCheckData
---@return boolean allowed
---@return string? reason
local function passesRunChecks(data)
    local allowed, reason = CanRunDyno(data.plyId, data.dynoId, data.vehicle)
    if (not allowed) then return false, reason end

    for _, check in pairs(runChecks) do
        local passed, refusal = check.canRun(data)
        if (not passed) then return false, refusal end
    end

    return true
end

---@param netId integer
---@return boolean running @ The car is on a run on any dyno
local function isCarRunning(netId)
    for _, dyno in pairs(dynos) do
        if (dyno.run and dyno.run.netId == netId) then return true end
    end

    return false
end

-- The client that owns the car lets it down once its rollers have run down, see runDown in client/run.lua. This
-- is for a car whose owner has gone: it is unfrozen once they would have stopped. A car that started its next run
-- meanwhile stays held
---@param netId integer
local function letGoLater(netId)
    SetTimeout(DynoRun.runDownMs + 1500, function()
        if (isCarRunning(netId)) then return end

        local vehicle = NetworkGetEntityFromNetworkId(netId)
        if (vehicle ~= 0 and DoesEntityExist(vehicle)) then FreezeEntityPosition(vehicle, false) end
    end)
end

-- Ends a run early: the car is let go of once its rollers have run down and the driver is told why
---@param dynoId integer
---@param reason string @ Locale key
function AbortDynoRun(dynoId, reason)
    local dyno = dynos[dynoId]
    local run = dyno and dyno.run
    if (not run) then return end

    dyno.run = nil

    publish()
    letGoLater(run.netId)

    if (GetPlayerName(run.driver)) then Z.notify(run.driver, reason) end

    TriggerEvent("zyke_dyno:OnRunAborted", {dynoId = dynoId, runId = run.id, plate = run.plate, plyId = run.driver, reason = reason})
end

---@param dynoId integer
---@param run ZykeDynoRun
local function finishRun(dynoId, run)
    local dyno = dynos[dynoId]
    if (not dyno or not dyno.run or dyno.run.id ~= run.id) then return end

    local result = DynoResults.build(dynoId, run)

    dyno.run = nil
    dyno.last = DynoResults.getSummary(result)

    publish()
    letGoLater(run.netId)

    DynoResults.finish(result)
end

-- Watches a running car and its driver, and stops the run as soon as either can not go on, or when the driver
-- has not finished a pull in time
---@param dynoId integer
---@param run ZykeDynoRun
local function watchRun(dynoId, run)
    local endsAt = run.startAt + settings.pull.maxMs

    while (dynos[dynoId] and dynos[dynoId].run == run) do
        local vehicle = NetworkGetEntityFromNetworkId(run.netId)
        local ped = GetPlayerPed(run.driver)
        if (vehicle == 0 or not DoesEntityExist(vehicle)) then return AbortDynoRun(dynoId, "reason:vehicleGone") end
        if (ped == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped) then return AbortDynoRun(dynoId, "reason:driverLeft") end
        if (GetVehicleEngineHealth(vehicle) < settings.minEngineHealth) then return AbortDynoRun(dynoId, "reason:tooDamaged") end
        if (not GetIsVehicleEngineRunning(vehicle)) then return AbortDynoRun(dynoId, "reason:engineStopped") end
        if (GetGameTimer() >= endsAt) then return AbortDynoRun(dynoId, "reason:pullTimeout") end

        Wait(watchMs)
    end
end

---@param plyId PlayerId
---@param dynoId integer
---@param netId any @ The car's network id as the client sent it
---@param payload table @ The inputs the driver's client read from the car
---@param label string @ The car's name as the client shows it
---@return boolean started
---@return string? reason
Z.callback.register("zyke_dyno:StartRun", function(plyId, dynoId, netId, payload, label)
    local dyno = dynos[dynoId]
    if (not dyno) then return false, "reason:noDyno" end
    if (dyno.run or dyno.starting) then return false, "reason:dynoBusy" end

    local carNetId = math.tointeger(tonumber(netId))
    if (not carNetId) then return false, "reason:vehicleGone" end

    local vehicle = NetworkGetEntityFromNetworkId(carNetId)
    if (vehicle == 0 or not DoesEntityExist(vehicle)) then return false, "reason:vehicleGone" end
    if (isCarRunning(carNetId)) then return false, "reason:dynoBusy" end
    if (GetPedInVehicleSeat(vehicle, -1) ~= GetPlayerPed(plyId)) then return false, "reason:notDriver" end
    if (#(GetEntityCoords(vehicle) - dyno.coords) > startReach) then return false, "reason:notLinedUp" end
    if (GetVehicleEngineHealth(vehicle) < settings.minEngineHealth) then return false, "reason:tooDamaged" end
    if (not GetIsVehicleEngineRunning(vehicle)) then return false, "reason:engineOff" end

    local jobs = dyno.jobs or settings.jobs
    if (jobs and not Z.isJob(plyId, jobs)) then return false, "reason:wrongJob" end

    local inputs = readInputs(payload)
    if (not inputs) then return false, "reason:classNotAllowed" end

    local kindRefusal = DynoGeometry.getKindRefusal(dyno.kind, DynoGeometry.getKindFor(inputs.class, GetVehicleType(vehicle)))
    if (kindRefusal) then return false, kindRefusal end

    local plate = TrimPlate(GetVehicleNumberPlateText(vehicle))
    local allowed, reason = passesRunChecks({plyId = plyId, dynoId = dynoId, vehicle = vehicle, plate = plate, inputs = inputs})
    if (not allowed) then return false, reason or "reason:actionUnavailable" end

    -- The history lookup waits on the database, and the dyno must not be taken meanwhile. A failed query would
    -- leave it taken until a restart
    dyno.starting = true

    local looked, compare = pcall(DynoDatabase.getCompare, plate)

    dyno.starting = nil

    if (not looked) then return false, "reason:actionUnavailable" end
    if (dyno.run or not dynos[dynoId] or isCarRunning(carNetId)) then return false, "reason:dynoBusy" end

    local run = {
        id = Z.createUniqueId(),
        netId = carNetId,
        plate = plate,
        label = type(label) == "string" and label:sub(1, 48) or inputs.model,
        driver = plyId,
        startAt = GetGameTimer(),
        seed = math.random(1, 2147483646),
        inputs = inputs,
        compare = compare,
    }

    dyno.run = run

    publish()
    FreezeEntityPosition(vehicle, true)

    CreateThread(function()
        watchRun(dynoId, run)
    end)

    TriggerEvent("zyke_dyno:OnRunStarted", {dynoId = dynoId, runId = run.id, plate = plate, plyId = plyId, netId = carNetId})

    return true
end)

---@param dynoId integer
RegisterNetEvent("zyke_dyno:StopRun", function(dynoId)
    local dyno = dynos[dynoId]
    if (not dyno or not dyno.run or dyno.run.driver ~= source) then return end

    AbortDynoRun(dynoId, "reason:stopped")
end)

-- Players a sample of a pull is passed on to: those close enough to see the dyno and those following it in the
-- laptop app, other than its driver
---@param dynoId integer
---@param dyno ZykeDyno
---@param driver PlayerId
---@return PlayerId[] targets
local function getWatchers(dynoId, dyno, driver)
    local targets = {}

    for _, player in ipairs(GetPlayers()) do
        local plyId = tonumber(player) --[[@as PlayerId]]
        local ped = GetPlayerPed(plyId)
        local near = ped ~= 0 and #(GetEntityCoords(ped) - dyno.coords) <= settings.streamDistance
        local following = DynoLaptop and DynoLaptop.isConnected(plyId, dynoId)

        if (plyId ~= driver and (near or following)) then targets[#targets + 1] = plyId end
    end

    return targets
end

---@param value any
---@param low number
---@param high number
---@return number clamped @ low for anything that is not a number
local function clampNumber(value, low, high)
    local number = tonumber(value)
    if (not number or number ~= number) then return low end

    return math.min(high, math.max(low, number))
end

-- Where the driver's pull stands, passed on to everyone watching. It only moves the rollers, the revs and the
-- graph's head; the result is the server's own, see server/results.lua
---@param dynoId integer
---@param runId string
---@param sample table @ Rpm, speed, throttle, phase, revealed, power and torque as the driver's client sent them
RegisterNetEvent("zyke_dyno:RunSample", function(dynoId, runId, sample)
    local dyno = dynos[dynoId]
    if (not dyno or not dyno.run or dyno.run.id ~= runId or dyno.run.driver ~= source or type(sample) ~= "table") then return end

    local now = GetGameTimer()
    if (now - (sampledAt[dynoId] or 0) < sampleMinMs) then return end

    sampledAt[dynoId] = now

    local clean = {
        rpm = clampNumber(sample.rpm, 0.0, 20000.0),
        speed = clampNumber(sample.speed, 0.0, 200.0),
        throttle = clampNumber(sample.throttle, 0.0, 1.0),
        phase = phases[sample.phase] and sample.phase or "ready",
        revealed = clampNumber(sample.revealed, 0.0, 1000.0),
        power = clampNumber(sample.power, 0.0, 10000.0),
        torque = clampNumber(sample.torque, 0.0, 50000.0),
    }

    for _, target in ipairs(getWatchers(dynoId, dyno, source)) do
        TriggerClientEvent("zyke_dyno:RunSample", target, dynoId, runId, clean)
    end
end)

-- The driver's client says the pull reached the limiter and the rollers have run down
---@param dynoId integer
---@param runId string
RegisterNetEvent("zyke_dyno:FinishRun", function(dynoId, runId)
    local dyno = dynos[dynoId]
    if (not dyno or not dyno.run or dyno.run.id ~= runId or dyno.run.driver ~= source) then return end
    if (GetGameTimer() - dyno.run.startAt < DynoRun.settleMs + minPullMs) then return end

    finishRun(dynoId, dyno.run)
end)

AddEventHandler("playerDropped", function()
    for dynoId, dyno in pairs(dynos) do
        if (dyno.run and dyno.run.driver == source) then AbortDynoRun(dynoId, "reason:driverLeft") end
    end
end)

---@param resource string
AddEventHandler("onResourceStop", function(resource)
    if (resource == ResName) then
        for dynoId in pairs(dynos) do
            AbortDynoRun(dynoId, "reason:stopped")
        end

        GlobalState.zykeDynos = nil

        return
    end

    local removed = false

    for dynoId, dyno in pairs(dynos) do
        if (dyno.resource == resource) then
            AbortDynoRun(dynoId, "reason:stopped")

            dynos[dynoId] = nil
            removed = true
        end
    end

    if (removed) then publish() end
end)

for i = 1, #Config.Dynos do
    CreateDyno(Config.Dynos[i], ResName)
end

publish()

-- Exports, see the documentation

---@param options {coords: vector3, heading?: number, kind?: DynoKind, screen?: {offset: vector3, heading: number}, jobs?: string[] | string, label?: string}
---@return integer? dynoId
exports("CreateDyno", function(options)
    return CreateDyno(options, GetInvokingResource() or ResName)
end)

---@param dynoId integer
---@return boolean removed
exports("RemoveDyno", function(dynoId)
    local dyno = dynos[dynoId]
    if (not dyno or dyno.resource ~= GetInvokingResource()) then return false end

    return RemoveDyno(dynoId)
end)

exports("GetDynos", GetDynos)

---@param dynoId integer
---@return ZykeDyno? dyno
exports("GetDyno", function(dynoId)
    return dynos[dynoId]
end)

---@param dynoId integer
---@return ZykeDynoRun? run
exports("GetActiveRun", function(dynoId)
    return dynos[dynoId] and dynos[dynoId].run
end)

---@param dynoId integer
---@return boolean aborted
exports("AbortRun", function(dynoId)
    if (not dynos[dynoId] or not dynos[dynoId].run) then return false end

    AbortDynoRun(dynoId, "reason:stopped")

    return true
end)

-- Starts a run for a player who sits in a car on a dyno, as if they pressed E there
---@param plyId PlayerId
---@param dynoId? integer
exports("RequestRun", function(plyId, dynoId)
    TriggerClientEvent("zyke_dyno:RequestRun", plyId, dynoId)
end)

---@param name string
---@param canRun fun(data: DynoRunCheckData): boolean, string?
exports("RegisterRunCheck", function(name, canRun)
    runChecks[name] = {canRun = canRun, resource = GetInvokingResource() or ResName}
end)

---@param name string
exports("RemoveRunCheck", function(name)
    runChecks[name] = nil
end)

---@param resource string
AddEventHandler("onResourceStop", function(resource)
    for name, check in pairs(runChecks) do
        if (check.resource == resource) then runChecks[name] = nil end
    end
end)