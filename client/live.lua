-- Where each dyno's run stands as this client sees it. Only client/run.lua writes it, and other resources read it

DynoLive = {}

---@class DynoLivePoint
---@field rpm number
---@field kw number @ Wheel power
---@field nm number @ Wheel torque

---@class DynoLiveState
---@field runId string
---@field plate string
---@field label string
---@field drive DynoDrive
---@field phase DynoPhase
---@field rpm number
---@field speed number @ Metres a second at the rollers
---@field throttle number
---@field gear integer
---@field redline number
---@field startRpm number
---@field revealed number @ Points of the curve drawn so far
---@field power number @ Wheel kW this moment
---@field torque number @ Wheel Nm this moment
---@field curve DynoCurve
---@field compare {previous?: DynoSheet, first?: DynoSheet}
---@field points? DynoLivePoint[] @ Filled in by DynoLive.get

---@type table<integer, DynoLiveState>
local states = {}

---@param dynoId integer
---@param state DynoLiveState
function DynoLive.set(dynoId, state)
    states[dynoId] = state
end

---@param dynoId integer
function DynoLive.clear(dynoId)
    states[dynoId] = nil
end

-- The run on a dyno with the points of the curve drawn so far, nil while it stands free
---@param dynoId integer
---@return DynoLiveState? state
function DynoLive.get(dynoId)
    local state = states[dynoId]
    if (not state) then return nil end

    local curve, points = state.curve, {}
    local count = #curve.torque

    for i = 1, math.min(math.floor(state.revealed), count) do
        points[i] = {rpm = curve.startRpm + (curve.redline - curve.startRpm) * (i - 1) / (count - 1), kw = curve.power[i], nm = curve.torque[i]}
    end

    state.points = points

    return state
end

exports("GetLiveRun", DynoLive.get)