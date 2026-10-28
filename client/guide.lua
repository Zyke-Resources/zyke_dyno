-- Lining a vehicle up on a dyno and starting the run. The server checks the start again in server/dynos.lua

local settings = Config.Settings.dyno
local geometry = DynoGeometry

-- Between looks for a dyno under the player's vehicle
local lookMs = 500
-- Between looks at how it stands on one
local lineUpMs = 100

-- Metres a second a vehicle may still roll at
local stillSpeed = 0.3

-- CTaskExitVehicle
local exitTask = 2

-- The start key works again after this long without the server's answer
local startTimeoutMs = 15000

-- RGBA of the strip under the front wheels, before and once they are on it
local stripOff = {255, 170, 40, 120}
local stripOn = {60, 220, 110, 150}
-- Metres, either side along the dyno and up off the deck
local stripDepth = 0.05
local stripLift = 0.02

---@type integer?
local startingDynoId

-- The player sits in the vehicle and is not getting out, as the engine stops while they climb out
---@return integer vehicle @ 0 for none
local function getSeatedVehicle()
    local ped = PlayerPedId()
    if (GetIsTaskActive(ped, exitTask)) then return 0 end

    return GetVehiclePedIsIn(ped, false)
end

-- Metres along the dyno the vehicle's front wheel centre stands where it goes
---@param dyno ZykeDyno
---@param axles DynoAxles
---@return number seat
local function getFrontSeat(dyno, axles)
    local layout = geometry.get(dyno.kind)

    return (geometry.getSeat(layout, layout.front, axles.frontRadius))
end

---@param dynoId integer
---@param dyno ZykeDyno
---@param vehicle integer
---@param axles? DynoAxles @ Read from the vehicle when left out
---@return string? reason @ Locale key of why a run can not start, nil when it can
---@return string? detail @ How far off the vehicle stands, while it is not lined up
local function getBlocker(dynoId, dyno, vehicle, axles)
    if (dyno.run) then return "reason:dynoBusy" end
    if (GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId()) then return "reason:notDriver" end

    local jobs = dyno.jobs or settings.jobs
    if (jobs and not Z.isJob(jobs)) then return "reason:wrongJob" end

    local kindRefusal = geometry.getKindRefusal(dyno.kind, geometry.getKindFor(GetVehicleClass(vehicle), DynoInputs.getType(vehicle)))
    if (kindRefusal) then return kindRefusal end
    if (GetVehicleEngineHealth(vehicle) < settings.minEngineHealth) then return "reason:tooDamaged" end
    if (not GetIsVehicleEngineRunning(vehicle)) then return "reason:engineOff" end

    axles = axles or DynoInputs.getAxles(vehicle)
    if (not axles) then return "reason:classNotAllowed" end

    local layout = geometry.get(dyno.kind)
    local locale = layout.locale
    local _, reaches = geometry.getRearCradle(layout, axles.front - axles.rear, axles.frontRadius)
    if (not reaches) then return locale.wheelbaseOff end

    -- Measured where the front tyre meets the ground, as a motorcycle stands leaning onto its rider's foot and a point
    -- higher up moves aside with the lean
    local front = geometry.toLocal(dyno, GetOffsetFromEntityInWorldCoords(vehicle, 0.0, axles.front, -axles.height + axles.tilt / 2.0 - axles.frontRadius))
    local along = front.y - getFrontSeat(dyno, axles)
    local angle = (GetEntityHeading(vehicle) - dyno.heading + 540.0) % 360.0 - 180.0
    local lineUp = settings.kinds[dyno.kind].lineUp
    if (math.abs(along) > lineUp.along) then return locale.notLinedUp, T(along > 0.0 and locale.back or locale.forward, ("%.2f"):format(math.abs(along))) end
    if (math.abs(front.x) > lineUp.across or math.abs(angle) > lineUp.angle) then return locale.notStraight, T("guide:straight", {("%.2f"):format(math.abs(front.x)), ("%.0f"):format(math.abs(angle))}) end
    if (GetEntitySpeed(vehicle) > stillSpeed) then return "reason:vehicleMoving" end

    local canRun, reason = CanRunDyno(dynoId, vehicle)
    if (not canRun) then return reason or "reason:actionUnavailable" end

    return nil
end

-- The strip under where the front wheels go: across the front rollers, or on the chock's base under the front
-- wheel's centre
---@param dyno ZykeDyno
---@param seat number @ See getFrontSeat
---@return vector3[] corners @ Round the strip in the world
local function getStripCorners(dyno, seat)
    local layout = geometry.get(dyno.kind)
    local half = layout.strip
    local z = layout.deckHeight + (layout.chock and layout.chock.base or 0.0) + stripLift

    return {
        geometry.toWorld(dyno, vec3(-half, seat - stripDepth, z)),
        geometry.toWorld(dyno, vec3(half, seat - stripDepth, z)),
        geometry.toWorld(dyno, vec3(half, seat + stripDepth, z)),
        geometry.toWorld(dyno, vec3(-half, seat + stripDepth, z)),
    }
end

---@param corners vector3[] @ See getStripCorners
---@param colour DynoColour
local function drawStrip(corners, colour)
    local a, b, c, d = corners[1], corners[2], corners[3], corners[4]

    DrawPoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, colour[1], colour[2], colour[3], colour[4])
    DrawPoly(a.x, a.y, a.z, c.x, c.y, c.z, d.x, d.y, d.z, colour[1], colour[2], colour[3], colour[4])
end

-- A reason is a locale key, or text another resource's check returned as it is, which has a space in it
---@param reason string
---@return boolean isText
local function isText(reason)
    return reason:find(" ", 1, true) ~= nil
end

---@param reason? string
local function notifyReason(reason)
    reason = reason or "reason:actionUnavailable"
    if (isText(reason)) then Z.notify(reason, nil, nil, true, "error") return end

    Z.notify(reason)
end

---@param dynoId integer
---@param vehicle integer
local function requestRun(dynoId, vehicle)
    if (startingDynoId) then return end
    if (not NetworkGetEntityIsNetworked(vehicle)) then Z.notify("reason:classNotAllowed") return end

    -- Read before the dyno counts as starting, so a power modifier that errors does not hold the start key off for good
    local inputs = DynoInputs.read(vehicle)

    startingDynoId = dynoId

    local started, reason = Z.callback.request("zyke_dyno:StartRun", {timeout = startTimeoutMs}, dynoId, NetworkGetNetworkIdFromEntity(vehicle), inputs, Z.getModelLabel(GetEntityModel(vehicle)))

    startingDynoId = nil

    if (not started) then notifyReason(reason) end
end

-- Starts a run on a dyno for the vehicle the player drives, as the start key does. Returns the reason it can not
-- start, a locale key or a check's own text
---@param dynoId? integer @ The dyno under the player's vehicle when left out
---@return boolean requested
---@return string? reason
local function startRun(dynoId)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if (vehicle == 0) then return false, "reason:notInVehicle" end

    local dyno

    if (dynoId) then
        dyno = GetDynos()[dynoId]
    else
        dynoId, dyno = GetDynoAt(GetEntityCoords(vehicle))
    end

    if (not dyno or not dynoId) then return false, "reason:noDyno" end

    local reason = getBlocker(dynoId, dyno, vehicle)
    if (reason) then return false, reason end

    CreateThread(function()
        requestRun(dynoId, vehicle)
    end)

    return true
end

exports("StartRun", startRun)

-- Another resource asked the server to start a run for this player, see the RequestRun export
---@param dynoId? integer
RegisterNetEvent("zyke_dyno:RequestRun", function(dynoId)
    local requested, reason = startRun(dynoId)
    if (not requested) then notifyReason(reason) end
end)

Z.keybinds.addKeyMapping("zyke_dyno_startRun", T("keymap:startRun"), settings.keys.startRun)

-- Runs while the player's vehicle stands on a dyno's deck with no run of its own on. How it stands is checked every
-- lineUpMs and the panel only sent again when what it says changed; between checks only the start key and the strip
-- take a frame
---@param dynoId integer
---@param vehicle integer
local function guide(dynoId, vehicle)
    -- The start key stays on the panel while the run can not start, and says why when pressed
    local items, shown = {{label = T("control:startRun"), command = "zyke_dyno_startRun", func = function()
        if (startingDynoId) then return end

        local requested, reason = startRun(dynoId)
        if (not requested) then notifyReason(reason) end
    end}}, nil

    -- Read once, as the wheels keep their place on the vehicle; the start key reads them again
    local axles = DynoInputs.getAxles(vehicle)
    -- The strip, placed again only for a changed dyno, as it stands where this vehicle's front wheels go
    ---@type vector3[]?
    local corners
    ---@type ZykeDyno?
    local cornersDyno

    while (getSeatedVehicle() == vehicle) do
        local dyno = GetDynos()[dynoId]
        if (not dyno or GetDynoAt(GetEntityCoords(vehicle), 0.5) ~= dynoId) then break end

        if ((dyno.run and dyno.run.netId == NetworkGetNetworkIdFromEntity(vehicle)) or DynoSheet.isOpen()) then
            Z.keybinds.hide(items)

            shown = nil

            Wait(lineUpMs)
        else
            local reason, detail = getBlocker(dynoId, dyno, vehicle, axles)
            local panel = ("%s|%s"):format(reason, detail)

            if (panel ~= shown) then
                shown = panel

                Z.keybinds.show(items, {title = T("title:dyno"), detail = detail, warning = reason and (isText(reason) and reason or T(reason)) or nil})
            end

            if (axles and cornersDyno ~= dyno) then corners, cornersDyno = getStripCorners(dyno, getFrontSeat(dyno, axles)), dyno end

            local locale = geometry.get(dyno.kind).locale
            local colour = (reason ~= locale.notLinedUp and reason ~= locale.notStraight) and stripOn or stripOff

            -- A changed dyno, such as a run starting on it, or the sheet opening cuts the wait short
            local checkAt = GetGameTimer() + lineUpMs
            while (GetGameTimer() < checkAt and GetDynos()[dynoId] == dyno and not DynoSheet.isOpen()) do
                Z.keybinds.handle(items)

                if (corners) then drawStrip(corners, colour) end

                Wait(0)
            end
        end
    end

    Z.keybinds.hide(items)
end

CreateThread(function()
    while (true) do
        local vehicle = getSeatedVehicle()
        local dynoId = vehicle ~= 0 and GetDynoAt(GetEntityCoords(vehicle), 0.5)
        if (dynoId) then guide(dynoId, vehicle) end

        Wait(lookMs)
    end
end)