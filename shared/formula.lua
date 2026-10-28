-- The open formula behind every number on the dyno. Engine hp is scale * fInitialDriveForce * fMass^1.5 *
-- (fInitialDriveMaxFlatVel / 100)^4, times the class, model, engine upgrade, turbo, torque multiplier and other
-- resources' factors, see getPower; the wheels get it less the drivetrain loss of the wheels that drive, or of
-- the vehicle's class where it has its own, as a motorcycle's chain does. It is plain maths on the inputs the
-- driver's client reads from the vehicle, so the server and every client watching work out the same curve from
-- the same inputs and seed
DynoFormula = {}

local settings = Config.Settings.dyno

-- Points on a curve, evenly spread from the start of the pull to the redline
local pointCount = 48

local kwPerHp = 0.745700
local kwPerPs = 0.735499
-- Torque in Nm is this times kW over rpm
local nmPerKwRpm = 9549.297
local nmPerLbft = 1.355818

-- GTA's real top speed stands about a third over fInitialDriveMaxFlatVel
local flatVelToTopSpeed = 1.33

-- Torque share the turbo adds once spooled, as at full throttle on the rollers
local turboGain = 0.10

-- Engine mod stat points per percent of drive force, measured in game
local engineModifierPerPercent = 5.0

---@alias DynoDrive "FWD" | "RWD" | "AWD"

---@class DynoInputs
---@field model string @ Model name, for the factors in the config
---@field class integer
---@field force number @ fInitialDriveForce as the vehicle has it now, with any damage a script took off
---@field mass number @ fMass
---@field topSpeed number @ fInitialDriveMaxFlatVel
---@field gears integer
---@field drive DynoDrive
---@field engineModifier number @ The stat of the fitted engine mod, 0 when stock
---@field turbo boolean
---@field cheat number @ GetVehicleCheatPowerIncrease, which SetVehicleEngineTorqueMultiplier sets
---@field extra number @ Every RegisterPowerModifier multiplied together
---@field wheelRadius number @ A driven wheel's
---@field frontRadius number
---@field wheelbase number

---@class DynoCurve
---@field startRpm number
---@field redline number
---@field power number[] @ Wheel kW at each point
---@field torque number[] @ Wheel Nm at each point
---@field engineKw number @ Peak before drivetrain loss
---@field wheelKw number
---@field wheelNm number
---@field powerRpm number
---@field torqueRpm number
---@field loss number

---@class DynoPowerBreakdown
---@field base number @ hp from the handling alone
---@field class number
---@field model number
---@field engine number
---@field turbo number
---@field cheat number
---@field extra number
---@field engineKw number

---@param value number
---@return number eased @ 0 to 1 over 0 to 1, flat at both ends
local function smooth(value)
    local clamped = math.min(1.0, math.max(0.0, value))

    return clamped * clamped * (3.0 - 2.0 * clamped)
end

-- A small number generator of its own, so every client draws the same trace from one seed
---@param seed integer
---@return fun(): number nextValue @ 0 to 1
local function getRandom(seed)
    local state = math.floor(seed) % 2147483647
    if (state == 0) then state = 1 end

    return function()
        state = (state * 48271) % 2147483647

        return state / 2147483647
    end
end

---@param inputs DynoInputs
---@return DynoPowerBreakdown breakdown
function DynoFormula.getPower(inputs)
    local formula = settings.formula
    local base = formula.scale * inputs.force * inputs.mass ^ formula.massExponent * (inputs.topSpeed / 100.0) ^ formula.speedExponent
    local breakdown = {
        base = base,
        class = formula.classScale[inputs.class] or 1.0,
        model = formula.models[inputs.model] or 1.0,
        engine = 1.0 + inputs.engineModifier / engineModifierPerPercent / 100.0,
        turbo = inputs.turbo and 1.0 + turboGain or 1.0,
        cheat = inputs.cheat,
        extra = inputs.extra,
    }

    breakdown.engineKw = base * breakdown.class * breakdown.model * breakdown.engine * breakdown.turbo * breakdown.cheat * breakdown.extra * kwPerHp

    return breakdown
end

---@param inputs DynoInputs
---@return number idle
---@return number redline
function DynoFormula.getRpmRange(inputs)
    local rpm = settings.rpm

    return rpm.idle, rpm.models[inputs.model] or rpm.classes[inputs.class] or rpm.redline
end

-- Metres a second the car tops out at on the road
---@param inputs DynoInputs
---@return number speed
function DynoFormula.getTopSpeed(inputs)
    return inputs.topSpeed / 3.6 * flatVelToTopSpeed
end

-- The gear the pull runs in: the configured one, or one under the top gear when the vehicle has no more gears than
-- that. In its top gear the road model's drag takes all the power before the redline, so the pull would never end
---@param inputs DynoInputs
---@return integer gear
function DynoFormula.getGear(inputs)
    if (inputs.gears <= 1) then return 1 end

    return math.min(settings.gear, inputs.gears - 1)
end

-- Metres a second the rollers turn at under the wheels when the engine is at its redline in the pull's gear
---@param inputs DynoInputs
---@return number speed
function DynoFormula.getRedlineSpeed(inputs)
    return DynoFormula.getTopSpeed(inputs) * DynoFormula.getGear(inputs) / math.max(1, inputs.gears)
end

-- The torque a car's engine makes over its rev range, as a share of its peak. It climbs from idle to a peak
-- and falls toward the redline, so power peaks late as on a real sheet. Where the peak sits and how far it
-- falls comes from the model's name, so each car has a shape of its own that stays the same run after run
---@param inputs DynoInputs
---@return fun(share: number): number shape @ share is 0 at idle and 1 at the redline
local function getTorqueShape(inputs)
    local character = getRandom(joaat(inputs.model) & 0x7fffffff)
    local peakAt = 0.42 + 0.22 * character()
    local low = 0.60 + 0.14 * character()
    local high = 0.70 + 0.12 * character()

    return function(share)
        local torque

        if (share < peakAt) then
            torque = low + (1.0 - low) * math.sin(share / peakAt * math.pi / 2.0)
        else
            torque = 1.0 - (1.0 - high) * ((share - peakAt) / (1.0 - peakAt)) ^ 1.6
        end

        -- The turbo builds boost through the low revs and holds it to the redline
        if (inputs.turbo) then torque = torque * (1.0 + turboGain * smooth((share - 0.18) / 0.30)) / (1.0 + turboGain) end

        return torque
    end
end

---@param inputs DynoInputs
---@param seed integer @ Draws the small wobble every real trace has, the same on every client
---@return DynoCurve curve
function DynoFormula.getCurve(inputs, seed)
    local idle, redline = DynoFormula.getRpmRange(inputs)
    local startRpm = math.floor(math.max(idle * 2.5, redline * 0.32) / 50.0 + 0.5) * 50.0
    local shape = getTorqueShape(inputs)
    local random = getRandom(seed)
    local phaseA, phaseB = random() * math.pi * 2.0, random() * math.pi * 2.0
    local loss = settings.drivetrainLoss.classes[inputs.class] or settings.drivetrainLoss[inputs.drive] or 0.0
    local raw, peak = {}, 0.0

    for i = 1, pointCount do
        local rpm = startRpm + (redline - startRpm) * (i - 1) / (pointCount - 1)
        -- Slow waves several hundred rpm long and a little noise, as a real trace has after the dyno's smoothing
        local wobble = 1.0 + 0.006 * math.sin(i * 0.9 + phaseA) + 0.003 * math.sin(i * 0.37 + phaseB) + 0.0015 * (random() - 0.5)
        local torque = shape((rpm - idle) / (redline - idle)) * wobble

        raw[i] = torque
        peak = math.max(peak, torque * rpm)
    end

    local engineKw = DynoFormula.getPower(inputs).engineKw
    local wheelKw = engineKw * (1.0 - loss)
    -- Torque the shape stands for at 1.0, so the highest power on the curve is the wheel power
    local scale = wheelKw * nmPerKwRpm / peak
    local curve = {startRpm = startRpm, redline = redline, power = {}, torque = {}, engineKw = engineKw, wheelKw = 0.0, wheelNm = 0.0, powerRpm = startRpm, torqueRpm = startRpm, loss = loss}

    for i = 1, pointCount do
        local rpm = startRpm + (redline - startRpm) * (i - 1) / (pointCount - 1)
        local torque = raw[i] * scale
        local power = torque * rpm / nmPerKwRpm

        curve.torque[i], curve.power[i] = torque, power

        if (power > curve.wheelKw) then curve.wheelKw, curve.powerRpm = power, rpm end
        if (torque > curve.wheelNm) then curve.wheelNm, curve.torqueRpm = torque, rpm end
    end

    return curve
end

---@param kw number
---@param unit? string
---@return number power @ In the configured unit
function DynoFormula.toPowerUnit(kw, unit)
    unit = unit or settings.units.power
    if (unit == "kw") then return kw end
    if (unit == "ps") then return kw / kwPerPs end

    return kw / kwPerHp
end

---@param nm number
---@param unit? string
---@return number torque @ In the configured unit
function DynoFormula.toTorqueUnit(nm, unit)
    if ((unit or settings.units.torque) == "lbft") then return nm / nmPerLbft end

    return nm
end

---@param metres number @ Metres a second
---@param unit? string
---@return number speed @ In the configured unit
function DynoFormula.toSpeedUnit(metres, unit)
    if ((unit or settings.units.speed) == "mph") then return metres * 2.236936 end

    return metres * 3.6
end