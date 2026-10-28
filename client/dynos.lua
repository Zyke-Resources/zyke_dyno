-- Every dyno and the run on it as the server keeps them in the zykeDynos global state, see server/dynos.lua.
-- Kept here as it changes, since reading a global state copies it

-- The generational collector's full passes held a single frame for 5 to 12 ms when a run started or ended. The
-- incremental one spreads the same work over many frames
collectgarbage("incremental")

-- The global state turns whole floats such as 240.0 into integers, which natives that take a float read as 0.0
---@param value? table<integer, ZykeDyno>
---@return table<integer, ZykeDyno> dynos
local function readDynos(value)
    value = value or {}

    for _, dyno in pairs(value) do
        dyno.heading += 0.0

        if (dyno.screen) then dyno.screen.heading = (dyno.screen.heading or 0.0) + 0.0 end
    end

    return value
end

---@type table<integer, ZykeDyno>
local dynos = readDynos(GlobalState.zykeDynos)

---@type fun(dynos: table<integer, ZykeDyno>)[]
local listeners = {}

---@return table<integer, ZykeDyno> dynos
function GetDynos()
    return dynos
end

-- The dyno whose deck the coords stand over, if any
---@param coords vector3
---@param reach? number @ Metres around the deck that still count, 0 when left out
---@return integer? dynoId
---@return ZykeDyno? dyno
function GetDynoAt(coords, reach)
    reach = reach or 0.0

    for dynoId, dyno in pairs(dynos) do
        local offset = DynoGeometry.toLocal(dyno, coords)
        local deck = DynoGeometry.get(dyno.kind).deck
        local across = offset.x >= deck.min.x - reach and offset.x <= deck.max.x + reach
        local along = offset.y >= deck.min.y - reach and offset.y <= deck.max.y + reach
        if (across and along and math.abs(offset.z) < 3.0) then return dynoId, dyno end
    end

    return nil
end

-- Runs the listener each time the dynos change, once the cache here holds them. The resource has this one state bag
-- handler, as every handler unpacks its own copy of the whole global state
---@param listener fun(dynos: table<integer, ZykeDyno>)
function OnDynosChange(listener)
    listeners[#listeners + 1] = listener
end

---@param bagName string
---@param key string
---@param value? table<integer, ZykeDyno>
AddStateBagChangeHandler("zykeDynos", "global", function(bagName, key, value)
    dynos = readDynos(value)

    for i = 1, #listeners do
        listeners[i](dynos)
    end
end)

exports("GetDynos", GetDynos)

---@param dynoId integer
---@return ZykeDynoRun? run
exports("GetActiveRun", function(dynoId)
    local dyno = dynos[dynoId]

    return dyno and dyno.run
end)

---@return boolean onDyno @ The player's car stands on a dyno with a run going
exports("IsOnDyno", function()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if (vehicle == 0) then return false end

    local netId = NetworkGetEntityIsNetworked(vehicle) and NetworkGetNetworkIdFromEntity(vehicle)

    for _, dyno in pairs(dynos) do
        if (dyno.run and dyno.run.netId == netId) then return true end
    end

    return false
end)

---@param vehicle integer
---@return DynoInputs inputs
---@return DynoPowerBreakdown power
exports("GetVehiclePower", function(vehicle)
    local inputs = DynoInputs.read(vehicle)

    return inputs, DynoFormula.getPower(inputs)
end)