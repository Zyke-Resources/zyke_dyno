-- Plays each run within reach. The driver's client runs the pull, see shared/run.lua, and sends it to the server,
-- which passes it on to the other clients close by

local settings = Config.Settings.dyno
local geometry = DynoGeometry

-- Between the screen graph's updates
local progressMs = 66
-- Between the driver's samples to the server
local sampleMs = 100
-- Between looks at the run's vehicle and whether this client drives it
local vehicleCheckMs = 100
-- Per second, how fast a watcher catches up with the driver's sample
local followRate = 10.0
-- For the rear cradle to slide back once the vehicle has gone
local parkMs = 1500

---@class DynoSample
---@field rpm number
---@field speed number
---@field throttle number
---@field phase DynoPhase
---@field revealed number
---@field power number
---@field torque number

---@class DynoPlayback
---@field dyno ZykeDyno @ The dyno as the run started on it, to let the vehicle down by once the dyno is gone
---@field layout DynoKindGeometry
---@field run ZykeDynoRun
---@field curve DynoCurve
---@field sim? DynoSim @ The pull itself, on the driver's client
---@field sample? DynoSample @ The driver's last sample, on every other client
---@field state DynoLiveState
---@field driveFront boolean
---@field driveRear boolean
---@field rearFrom number
---@field rearTo number
---@field startedAt integer
---@field posed boolean
---@field wheels? {front: integer[], rear: integer[]} @ The vehicle's wheel indices, see DynoInputs.getWheels

---@type table<integer, DynoPlayback>
local playing = {}
-- By dyno, runs that are over with their rollers still running down
---@type table<integer, DynoPlayback>
local rolling = {}
-- Run IDs by dyno a thread is starting for, so a run never plays twice
---@type table<integer, string>
local pending = {}

-- Afloat before the freeze, since rims frozen with gravity on never turn
local floatMs = 50
-- How long a ridden motorcycle is held straight after a run, while it leans onto its rider's foot
local settleMs = 1500

-- Sets the vehicle square into both cradles at its own ride height and freezes it there, with its gravity off
-- first so its wheels still turn. A motorcycle stands upright, its front wheel in the chock
---@param dyno ZykeDyno
---@param vehicle integer
---@return boolean posed
local function poseVehicle(dyno, vehicle)
    local axles = DynoInputs.getAxles(vehicle)
    if (not axles) then return false end

    local layout = geometry.get(dyno.kind)
    local frontY, frontHeight = geometry.getSeat(layout, layout.front, axles.frontRadius)
    local _, rearHeight = geometry.getSeat(layout, layout.rear, axles.rearRadius)
    local coords = geometry.toWorld(dyno, vec3(0.0, frontY - axles.front, (frontHeight + rearHeight) / 2.0 + axles.height))
    local wheelbase = axles.front - axles.rear
    -- Turned so both wheel centres meet their seats, less the slope they already have in the vehicle's frame
    local pitch = math.deg(math.atan(frontHeight - rearHeight, wheelbase) - math.atan(axles.tilt, wheelbase))

    FreezeEntityPosition(vehicle, false)
    SetVehicleGravity(vehicle, false)
    SetEntityCoordsNoOffset(vehicle, coords.x, coords.y, coords.z, false, false, false)
    SetEntityRotation(vehicle, pitch, 0.0, dyno.heading, 2, false)
    SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)

    Wait(floatMs)

    FreezeEntityPosition(vehicle, true)

    -- A motorcycle starts to lean onto its rider's foot while it floats
    SetEntityRotation(vehicle, pitch, 0.0, dyno.heading, 2, false)

    return true
end

-- A ridden motorcycle let go leans onto its rider's foot, and twists on the way unless held: its rear swung about 12 cm
-- aside and it stood 4.6 degrees off straight, past what lining up allows. Holds its heading while it leans and lands,
-- with the throttle and brake kept off so the tyre is not driven into the chock's face
---@param dyno ZykeDyno
---@param vehicle integer
---@param axles DynoAxles
local function settleBike(dyno, vehicle, axles)
    CreateThread(function()
        local settleUntil = GetGameTimer() + settleMs

        while (GetGameTimer() < settleUntil and DoesEntityExist(vehicle) and NetworkHasControlOfEntity(vehicle)) do
            DisableControlAction(0, 71, true)
            DisableControlAction(0, 72, true)

            local rotation = GetEntityRotation(vehicle, 2)
            SetEntityRotation(vehicle, rotation.x, rotation.y, dyno.heading, 2, false)

            Wait(0)
        end
    end)
end

-- Lets the vehicle go just over the deck, so it settles onto it. A motorcycle nobody sits on goes onto its stand
-- instead of falling over, and one ridden is held straight while it leans onto its rider's foot
---@param dyno ZykeDyno
---@param vehicle integer
local function releaseVehicle(dyno, vehicle)
    local axles = DynoInputs.getAxles(vehicle)
    local coords = GetEntityCoords(vehicle)

    if (axles) then
        local offset = geometry.toLocal(dyno, coords)
        local at = geometry.toWorld(dyno, vec3(offset.x, offset.y, geometry.get(dyno.kind).deckHeight + axles.height + axles.frontRadius + 0.03))

        SetEntityCoordsNoOffset(vehicle, at.x, at.y, at.z, false, false, false)
    end

    SetEntityRotation(vehicle, 0.0, 0.0, dyno.heading, 2, false)
    FreezeEntityPosition(vehicle, false)
    SetVehicleGravity(vehicle, true)
    SetVehicleCurrentRpm(vehicle, 0.2)

    if (not IsThisModelABike(GetEntityModel(vehicle))) then return end
    if (IsVehicleSeatFree(vehicle, -1)) then SetBikeOnStand(vehicle, 0.0, 0.0) return end
    if (not axles) then return end

    settleBike(dyno, vehicle, axles)
end

-- Turns the wheels on driven rollers with them and holds the others still. On the frozen vehicle a negative
-- rotation speed rolls a wheel forward
---@param vehicle integer
---@param playback DynoPlayback
---@param speed number @ Metres a second at the rollers
local function spinWheels(vehicle, playback, speed)
    local spin = speed / math.max(playback.run.inputs.wheelRadius, 0.1)

    if (not playback.wheels) then
        local front, rear = DynoInputs.getWheels(vehicle)

        playback.wheels = {front = front, rear = rear}
    end

    for _, wheel in ipairs(playback.wheels.front) do
        SetVehicleWheelRotationSpeed(vehicle, wheel, playback.driveFront and -spin or 0.0)
    end

    for _, wheel in ipairs(playback.wheels.rear) do
        SetVehicleWheelRotationSpeed(vehicle, wheel, playback.driveRear and -spin or 0.0)
    end
end

---@param dynoId integer
---@param playback DynoPlayback
---@return table message @ What the screens draw the run from
local function getRunMessage(dynoId, playback)
    local run = playback.run

    return {
        dynoId = dynoId,
        label = run.label,
        plate = run.plate,
        drive = run.inputs.drive,
        curve = {startRpm = playback.curve.startRpm, redline = playback.curve.redline, power = playback.curve.power, torque = playback.curve.torque},
        compare = run.compare,
        units = settings.units,
    }
end

-- What the driver is told to do next, nil while the pull goes as it should
---@param playback DynoPlayback
---@return string? hint
local function getHint(playback)
    local sim = playback.sim --[[@as DynoSim]]
    if (sim.elapsed < DynoRun.settleMs) then return nil end
    if (sim.pulled) then return T("hint:coast") end
    if (sim.lifted) then return T("hint:lifted") end
    if (not sim.pulling) then return T(playback.layout.locale.pull, sim.gear) end

    return nil
end

-- Moves the driver's pull on by a frame from their throttle and brake
---@param playback DynoPlayback
---@param frame number
local function stepDriver(playback, frame)
    local sim = playback.sim --[[@as DynoSim]]

    DisableControlAction(0, 72, true)
    DisableControlAction(0, 76, true)
    DynoRun.step(sim, GetControlNormal(0, 71), GetDisabledControlNormal(0, 72), frame)

    local state = playback.state

    state.rpm, state.speed, state.throttle, state.phase = sim.rpm, sim.speed, sim.throttle, sim.phase
    state.revealed, state.power, state.torque = sim.revealed, sim.power, sim.torque
end

-- Follows the driver's last sample on a client that only watches
---@param playback DynoPlayback
---@param frame number
local function stepWatcher(playback, frame)
    local sample = playback.sample
    if (not sample) then return end

    local state = playback.state
    local share = math.min(1.0, followRate * frame)

    state.rpm += (sample.rpm - state.rpm) * share
    state.speed += (sample.speed - state.speed) * share
    state.throttle, state.phase, state.revealed, state.power, state.torque = sample.throttle, sample.phase, sample.revealed, sample.power, sample.torque
end

---@param dynoId integer
---@param dyno ZykeDyno
---@return DynoPlayback? playback @ The run once it is over, for runDown
local function play(dynoId, dyno)
    pending[dynoId] = nil

    local run = dyno.run
    if (not run) then return nil end

    local curve = DynoFormula.getCurve(run.inputs, run.seed)
    local driverNet = run.driver == GetPlayerServerId(PlayerId())
    local layout = geometry.get(dyno.kind)
    local playback = {
        dyno = dyno,
        layout = layout,
        run = run,
        curve = curve,
        sim = driverNet and DynoRun.newSim(run.inputs, curve, settings.kinds[dyno.kind].inertia) or nil,
        state = {
            runId = run.id,
            plate = run.plate,
            label = run.label,
            drive = run.inputs.drive,
            phase = "ready",
            rpm = settings.rpm.idle,
            speed = 0.0,
            throttle = 0.0,
            gear = DynoFormula.getGear(run.inputs),
            redline = curve.redline,
            startRpm = curve.startRpm,
            revealed = 0,
            power = 0.0,
            torque = 0.0,
            curve = curve,
            compare = run.compare,
        },
        driveFront = run.inputs.drive ~= "RWD",
        driveRear = run.inputs.drive ~= "FWD",
        rearTo = (geometry.getRearCradle(layout, run.inputs.wheelbase, run.inputs.frontRadius)),
        startedAt = GetGameTimer(),
        posed = false,
    }

    local set = DynoProps.get(dynoId)
    playback.rearFrom = set and set.rearY or layout.rearFurthest
    playing[dynoId] = playback

    DynoLive.set(dynoId, playback.state)

    local frontAngle, rearAngle = set and set.frontAngle or 0.0, set and set.rearAngle or 0.0
    local lastProgress, lastSample, screenToken, hint, finishing = 0, 0, nil, nil, false
    local vehicle, ownsCar, driving, checkedAt = nil, false, false, 0
    local message = getRunMessage(dynoId, playback)
    local stopItems = {{label = T("control:stopRun"), key = "BACKSPACE", func = function()
        TriggerServerEvent("zyke_dyno:StopRun", dynoId)
    end}}

    if (driverNet) then
        DynoSheet.close()
        Z.keybinds.show(stopItems, {title = T("title:dyno"), detail = run.plate})
    end

    while (playing[dynoId] == playback) do
        local current = GetDynos()[dynoId]
        if (not current or not current.run or current.run.id ~= run.id) then break end

        local now, frame = GetGameTimer(), GetFrameTime()

        if (now - checkedAt >= vehicleCheckMs) then
            checkedAt = now
            vehicle = Z.network.getEntity(run.netId)
            ownsCar = vehicle ~= nil and NetworkHasControlOfEntity(vehicle)
            driving = driverNet and ownsCar and GetPedInVehicleSeat(vehicle --[[@as Entity]], -1) == PlayerPedId()
        end

        if (playback.sim and driving) then
            stepDriver(playback, frame)
            Z.keybinds.handle(stopItems)
        else
            stepWatcher(playback, frame)
        end

        local state = playback.state

        if (playback.driveFront) then frontAngle += state.speed / layout.rollerRadius * frame end
        if (playback.driveRear) then rearAngle += state.speed / layout.rollerRadius * frame end

        local slide = math.min(1.0, (now - playback.startedAt) / DynoRun.settleMs)

        DynoProps.pose(dynoId, frontAngle % (math.pi * 2.0), rearAngle % (math.pi * 2.0), playback.rearFrom + (playback.rearTo - playback.rearFrom) * slide * slide * (3.0 - 2.0 * slide))

        if (vehicle and DoesEntityExist(vehicle)) then
            if (ownsCar and not playback.posed) then playback.posed = poseVehicle(dyno, vehicle) end

            spinWheels(vehicle, playback, state.speed)
            SetVehicleCurrentRpm(vehicle, 0.2 + 0.8 * math.max(0.0, state.rpm - settings.rpm.idle) / (curve.redline - settings.rpm.idle))
        end

        if (driving and now - lastSample >= sampleMs) then
            lastSample = now

            TriggerServerEvent("zyke_dyno:RunSample", dynoId, run.id, {rpm = state.rpm, speed = state.speed, throttle = state.throttle, phase = state.phase, revealed = state.revealed, power = state.power, torque = state.torque})

            local nextHint = getHint(playback)

            if (nextHint ~= hint) then
                hint = nextHint

                Z.keybinds.show(stopItems, {title = T("title:dyno"), detail = run.plate, hint = hint})
            end
        end

        if (driving and not finishing and DynoRun.isFinished(playback.sim --[[@as DynoSim]])) then
            finishing = true

            TriggerServerEvent("zyke_dyno:FinishRun", dynoId, run.id)
        end

        if (now - lastProgress >= progressMs) then
            lastProgress = now

            local token = DynoScreen.getToken(dynoId)

            if (token and token ~= screenToken) then
                screenToken = token

                DynoScreen.send(dynoId, {event = "Run", data = message})
            end

            -- A screen out of view catches up with the first update once it is seen again
            if (DynoScreen.isSeen(dynoId)) then
                local progress = {dynoId = dynoId, revealed = state.revealed, rpm = state.rpm, phase = state.phase, speed = DynoFormula.toSpeedUnit(state.speed), power = state.power, torque = state.torque, throttle = state.throttle, gear = state.gear}

                DynoScreen.send(dynoId, {event = "Progress", data = progress})
            end
        end

        Wait(0)
    end

    if (playing[dynoId] == playback) then
        playing[dynoId] = nil

        DynoLive.clear(dynoId)
    end

    if (driverNet) then Z.keybinds.hide(stopItems) end

    return playback
end

-- Lets the rollers and the driven wheels on them run down once a run is over, however it ended, as they would
-- with nobody on the throttle. The client that owns the vehicle keeps it held over the rollers until they stop
-- and then lets it down, as wheels on a vehicle that falls onto the deck stop dead. Cut short when the next run
-- starts
---@param dynoId integer
---@param playback DynoPlayback
local function runDown(dynoId, playback)
    local run, state = playback.run, playback.state
    local speed = state.speed
    local rpmPerSpeed = speed > 1.0 and state.rpm / speed or 0.0
    local idle, redline = settings.rpm.idle, playback.curve.redline
    local endsAt = GetGameTimer() + DynoRun.runDownMs

    rolling[dynoId] = playback

    while (speed > 0.0 and GetGameTimer() < endsAt) do
        local current = GetDynos()[dynoId]
        if (not current or current.run) then break end

        local frame = GetFrameTime()
        local set = DynoProps.get(dynoId)

        speed = DynoRun.runDown(speed, frame)

        if (set) then
            local turn = speed / playback.layout.rollerRadius * frame
            local front = set.frontAngle + (playback.driveFront and turn or 0.0)
            local rear = set.rearAngle + (playback.driveRear and turn or 0.0)

            DynoProps.pose(dynoId, front % (math.pi * 2.0), rear % (math.pi * 2.0), set.rearY)
        end

        local vehicle = Z.network.getEntity(run.netId)

        if (vehicle and DoesEntityExist(vehicle)) then
            spinWheels(vehicle, playback, speed)

            if (GetIsVehicleEngineRunning(vehicle)) then SetVehicleCurrentRpm(vehicle, 0.2 + 0.8 * math.max(0.0, speed * rpmPerSpeed - idle) / (redline - idle)) end
        end

        Wait(0)
    end

    if (rolling[dynoId] == playback) then rolling[dynoId] = nil end

    -- A vehicle that starts its next run here stays held for it
    local current = GetDynos()[dynoId]
    if (current and current.run and current.run.netId == run.netId) then return end

    local vehicle = Z.network.getEntity(run.netId)
    if (playback.posed and vehicle and DoesEntityExist(vehicle) and NetworkHasControlOfEntity(vehicle)) then releaseVehicle(playback.dyno, vehicle) end
end

-- The driver's pull as the server passes it on, for the clients that watch it
---@param dynoId integer
---@param runId string
---@param sample DynoSample
RegisterNetEvent("zyke_dyno:RunSample", function(dynoId, runId, sample)
    local playback = playing[dynoId]
    if (not playback or playback.run.id ~= runId or type(sample) ~= "table") then return end

    playback.sample = sample
end)

-- Slides the rear cradle back to where it waits once its vehicle is gone, so the next one finds the dyno as it was
---@param dynoId integer
local function park(dynoId)
    local set = DynoProps.get(dynoId)
    local rearPark = set and geometry.get(set.kind).rearFurthest
    if (not set or set.rearY == rearPark) then return end

    local from, startedAt = set.rearY, GetGameTimer()
    while (not playing[dynoId] and GetGameTimer() - startedAt < parkMs) do
        local share = (GetGameTimer() - startedAt) / parkMs

        DynoProps.pose(dynoId, set.frontAngle, set.rearAngle, from + (rearPark - from) * share)

        Wait(0)
    end

    if (not playing[dynoId]) then DynoProps.pose(dynoId, set.frontAngle, set.rearAngle, rearPark) end
end

-- Looks for runs to play whenever a dyno changes, and plays those within reach of this client and the one its
-- laptop app follows
local function refresh()
    local coords = GetEntityCoords(PlayerPedId())
    local followed = DynoLaptop and DynoLaptop.getConnected()

    for dynoId, dyno in pairs(GetDynos()) do
        local near = #(dyno.coords - coords) <= settings.streamDistance or dynoId == followed

        if (dyno.run and near and pending[dynoId] ~= dyno.run.id and (not playing[dynoId] or playing[dynoId].run.id ~= dyno.run.id)) then
            pending[dynoId] = dyno.run.id

            CreateThread(function()
                local playback = play(dynoId, dyno)
                if (playback) then runDown(dynoId, playback) end

                park(dynoId)
            end)
        end
    end
end

OnDynosChange(refresh)

-- A player who walks up to a dyno with a run going sees the rest of it
CreateThread(function()
    while (true) do
        refresh()

        Wait(1000)
    end
end)

---@param resource string
AddEventHandler("onResourceStop", function(resource)
    if (resource ~= ResName) then return end

    for _, list in ipairs({playing, rolling}) do
        for _, playback in pairs(list) do
            local vehicle = Z.network.getEntity(playback.run.netId)
            if (playback.posed and vehicle and DoesEntityExist(vehicle) and NetworkHasControlOfEntity(vehicle)) then releaseVehicle(playback.dyno, vehicle) end
        end
    end
end)