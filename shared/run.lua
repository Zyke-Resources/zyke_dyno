-- The pull's road model, run by the driver's client: the formula's torque through the gear against the car's mass
-- and drag, so the rollers spin up about as fast as the car would pick up speed on the road
DynoRun = {}

local settings = Config.Settings.dyno

local gravity = 9.81
local rollingResistance = 0.012
-- Share of torque that holds the rollers back with the throttle closed
local engineBraking = 0.12

-- Metres a second squared, from the pedal or the dyno braking after a pull
local brakeDecel = 6.0

-- Milliseconds the limiter cuts the engine each time it touches the redline
local limiterCutMs = 70

-- Share of idle to curve start the slipping clutch holds, under 1
local clutchSlip = 0.6

-- Metres a second squared the rollers run down by after a run
local runDownDecel = 3.0
-- Share of their speed they lose each second on top
local runDownDrag = 0.15

-- Milliseconds the rear rollers take to slide under the car, the throttle does nothing until then
DynoRun.settleMs = 500
-- Milliseconds before the car is let go however fast the rollers still turn
DynoRun.runDownMs = 10000

-- Throttle at and above which a pull counts as flat out
DynoRun.fullThrottle = 0.95

---@alias DynoPhase "ready" | "pull" | "limiter" | "coast"

---@class DynoSim
---@field curve DynoCurve
---@field idle number
---@field mass number @ Kilograms the rollers feel
---@field drag number @ Newtons of air drag per (m/s)^2
---@field rolling number @ Newtons of rolling drag
---@field gear integer
---@field speedPerRpm number @ Metres a second at the rollers per engine rpm in the pull's gear
---@field speed number @ Metres a second at the rollers
---@field rpm number
---@field throttle number
---@field power number @ Wheel kW the engine makes this moment
---@field torque number @ Wheel Nm the engine makes this moment
---@field revealed number @ Points of the curve drawn so far, 0 while no pull is on
---@field pulling boolean @ Flat out since below the start of the curve
---@field pulled boolean @ Reached the redline flat out
---@field lifted boolean @ Came off the throttle during a pull, which then has to start again
---@field cutUntil number
---@field elapsed number @ Milliseconds since the run started
---@field phase DynoPhase

-- Wheel torque at engine revs, from the curve. Under the curve's start it falls off toward idle
---@param sim DynoSim
---@param rpm number
---@return number torque
local function getTorque(sim, rpm)
    local curve = sim.curve
    local count = #curve.torque

    if (rpm <= curve.startRpm) then
        local share = math.max(0.0, (rpm - sim.idle) / (curve.startRpm - sim.idle))

        return curve.torque[1] * (0.75 + 0.25 * share)
    end

    local at = math.min((rpm - curve.startRpm) / (curve.redline - curve.startRpm), 1.0) * (count - 1) + 1
    local point = math.min(count - 1, math.floor(at))

    return curve.torque[point] + (curve.torque[point + 1] - curve.torque[point]) * (at - point)
end

-- Points of the curve the revs stand at, 1 at the curve's start, fractional between two points
---@param curve DynoCurve
---@param rpm number
---@return number points
function DynoRun.getRevealed(curve, rpm)
    return math.max(1.0, math.min((rpm - curve.startRpm) / (curve.redline - curve.startRpm), 1.0) * (#curve.torque - 1) + 1)
end

---@param inputs DynoInputs
---@param curve DynoCurve
---@param inertia number @ How heavy the rollers feel as a share of the vehicle's mass, see Config.Settings.dyno.kinds
---@return DynoSim sim
function DynoRun.newSim(inputs, curve, inertia)
    local topSpeed = DynoFormula.getTopSpeed(inputs)
    local rolling = rollingResistance * inputs.mass * gravity
    -- Drag that holds the car at its top speed on the road with its peak wheel power
    local drag = math.max(0.0, (curve.wheelKw * 1000.0 / topSpeed - rolling) / (topSpeed * topSpeed))
    local idle = settings.rpm.idle

    return {
        curve = curve,
        idle = idle,
        mass = math.max(inputs.mass * inertia, 100.0),
        drag = drag,
        rolling = rolling,
        gear = DynoFormula.getGear(inputs),
        speedPerRpm = DynoFormula.getRedlineSpeed(inputs) / curve.redline,
        -- The rollers stand still with the engine at idle until the driver gives it throttle
        speed = 0.0,
        rpm = idle,
        throttle = 0.0,
        power = 0.0,
        torque = 0.0,
        revealed = 0,
        pulling = false,
        pulled = false,
        lifted = false,
        cutUntil = 0,
        elapsed = 0,
        phase = "ready",
    }
end

-- Keeps track of the pull: it starts flat out from under the curve's start, draws as the revs climb, counts once
-- it reaches the redline and has to start again if the throttle comes off before then
---@param sim DynoSim
local function trackPull(sim)
    local curve = sim.curve
    local flat = sim.throttle >= DynoRun.fullThrottle

    if (sim.pulled) then
        sim.phase = flat and sim.rpm >= curve.redline * 0.98 and "limiter" or "coast"

        return
    end

    if (flat and sim.rpm <= curve.startRpm) then sim.pulling, sim.lifted = true, false end

    if (sim.pulling and not flat) then
        sim.pulling, sim.lifted, sim.revealed = false, true, 0
    end

    if (sim.pulling) then
        sim.revealed = math.max(sim.revealed, DynoRun.getRevealed(curve, sim.rpm))

        if (sim.rpm >= curve.redline * 0.995) then sim.pulled, sim.revealed = true, #curve.torque end
    end

    sim.phase = sim.pulled and "limiter" or sim.pulling and "pull" or "ready"
end

-- Moves the pull on by one frame
---@param sim DynoSim
---@param throttle number @ 0 to 1
---@param brake number @ 0 to 1
---@param delta number @ Seconds since the last step
function DynoRun.step(sim, throttle, brake, delta)
    sim.elapsed += delta * 1000.0

    if (sim.elapsed < DynoRun.settleMs) then throttle = 0.0 end
    if (sim.pulled and throttle < 0.05) then brake = 1.0 end
    if (sim.lifted and throttle < 0.05 and sim.rpm > sim.curve.startRpm) then brake = math.max(brake, 0.6) end

    local curve = sim.curve
    local cut = sim.elapsed < sim.cutUntil
    local full = getTorque(sim, sim.rpm)
    local torque = cut and 0.0 or full * throttle
    local omegaPerSpeed = math.pi / 30.0 / sim.speedPerRpm
    local resist = sim.speed > 0.0 and sim.drag * sim.speed * sim.speed + sim.rolling or 0.0
    local held = (1.0 - throttle) * full * engineBraking * omegaPerSpeed
    local accel = (torque * omegaPerSpeed - resist - held) / sim.mass - brake * brakeDecel

    sim.speed = math.max(0.0, sim.speed + accel * delta)
    sim.throttle = throttle

    local slipRpm = sim.idle + (curve.startRpm - sim.idle) * clutchSlip * throttle

    sim.rpm = math.min(math.max(sim.speed / sim.speedPerRpm, slipRpm), curve.redline * 1.005)

    -- The limiter cuts the engine each time the revs touch the redline
    if (sim.rpm >= curve.redline and throttle > 0.05 and not cut) then sim.cutUntil = sim.elapsed + limiterCutMs end

    sim.torque = torque
    sim.power = torque * sim.rpm / 9549.297

    trackPull(sim)
end

-- The pull is over once it reached the redline, the throttle is off and the rollers have nearly stopped
---@param sim DynoSim
---@return boolean finished
function DynoRun.isFinished(sim)
    return sim.pulled and sim.throttle < 0.05 and sim.speed < 1.5
end

-- The rollers' speed a step later as they run down after a run, see runDownDecel
---@param speed number @ Metres a second at the rollers
---@param delta number @ Seconds since the last step
---@return number speed
function DynoRun.runDown(speed, delta)
    return math.max(0.0, speed - (runDownDecel + runDownDrag * speed) * delta)
end