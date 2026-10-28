-- Reads a vehicle's inputs for shared/formula.lua, and its axles so it can be set into the rollers
DynoInputs = {}

---@class DynoAxles
---@field front number @ Metres from the vehicle's origin to its front axle, along it
---@field rear number
---@field height number @ Metres from its origin down to its wheel centres
---@field tilt number @ Metres its front wheel centre stands over its rear one, in its own frame
---@field frontRadius number
---@field rearRadius number

---@class DynoPowerModifier
---@field getFactor fun(vehicle: integer): number?
---@field resource string

---@type table<string, DynoPowerModifier>
local modifiers = {}

-- Other resources multiply the power the dyno reads, for tunes they keep in their own data. getFactor returns a
-- factor, 1.0 or nil for none
---@param name string
---@param getFactor fun(vehicle: integer): number?
exports("RegisterPowerModifier", function(name, getFactor)
    modifiers[name] = {getFactor = getFactor, resource = GetInvokingResource() or ResName}
end)

---@param name string
exports("RemovePowerModifier", function(name)
    modifiers[name] = nil
end)

---@param resource string
AddEventHandler("onClientResourceStop", function(resource)
    for name, modifier in pairs(modifiers) do
        if (modifier.resource == resource) then modifiers[name] = nil end
    end
end)

-- The wheel indices of the front and the rear axle. A car's front wheels come first, a motorcycle's rear wheel does
---@param vehicle integer
---@return integer[] front
---@return integer[] rear
function DynoInputs.getWheels(vehicle)
    local count = GetVehicleNumberOfWheels(vehicle)
    if (count == 2) then return {1}, {0} end

    local rear = {}

    for wheel = 2, count - 1 do
        rear[#rear + 1] = wheel
    end

    return {0, 1}, rear
end

-- How GetVehicleType on the server names the vehicle, as far as the dynos tell them apart
---@param vehicle integer
---@return string vehicleType
function DynoInputs.getType(vehicle)
    return IsThisModelABike(GetEntityModel(vehicle)) and "bike" or "automobile"
end

---@param vehicle integer
---@param wheels integer[]
---@return boolean powered @ Any of the wheels is
local function isPowered(vehicle, wheels)
    for _, wheel in ipairs(wheels) do
        if (GetVehicleWheelIsPowered(vehicle, wheel)) then return true end
    end

    return false
end

---@param vehicle integer
---@return DynoDrive drive
local function getDrive(vehicle)
    local frontWheels, rearWheels = DynoInputs.getWheels(vehicle)
    local front, rear = isPowered(vehicle, frontWheels), isPowered(vehicle, rearWheels)
    if (front and rear) then return "AWD" end

    return front and "FWD" or "RWD"
end

---@param vehicle integer
---@return number factor
---@return table<string, number> factors @ Each registered modifier's own, by name
local function getExtraFactor(vehicle)
    local factor, factors = 1.0, {}

    for name, modifier in pairs(modifiers) do
        local value = tonumber(modifier.getFactor(vehicle)) or 1.0

        factors[name] = value
        factor *= value
    end

    return factor, factors
end

---@param vehicle integer
---@return DynoAxles? axles @ nil for a vehicle without the wheel bones of a car or a motorcycle
function DynoInputs.getAxles(vehicle)
    local frontBone, rearBone = GetEntityBoneIndexByName(vehicle, "wheel_lf"), GetEntityBoneIndexByName(vehicle, "wheel_lr")
    if (frontBone == -1 or rearBone == -1) then return nil end

    local frontWheels, rearWheels = DynoInputs.getWheels(vehicle)
    if (not rearWheels[1]) then return nil end

    local front = GetOffsetFromEntityGivenWorldCoords(vehicle, GetWorldPositionOfEntityBone(vehicle, frontBone))
    local rear = GetOffsetFromEntityGivenWorldCoords(vehicle, GetWorldPositionOfEntityBone(vehicle, rearBone))

    return {front = front.y, rear = rear.y, height = -(front.z + rear.z) / 2.0, tilt = front.z - rear.z, frontRadius = GetVehicleWheelTireColliderSize(vehicle, frontWheels[1]), rearRadius = GetVehicleWheelTireColliderSize(vehicle, rearWheels[1])}
end

---@param vehicle integer
---@return DynoInputs inputs
---@return table<string, number> factors @ The registered modifiers' factors, for /dynocalibrate
function DynoInputs.read(vehicle)
    local axles = DynoInputs.getAxles(vehicle)
    local engineLevel = GetVehicleMod(vehicle, 11)
    local extra, factors = getExtraFactor(vehicle)
    local drive = getDrive(vehicle)
    local inputs = {
        model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)):lower(),
        class = GetVehicleClass(vehicle),
        force = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDriveForce"),
        mass = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fMass"),
        topSpeed = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDriveMaxFlatVel"),
        gears = GetVehicleHandlingInt(vehicle, "CHandlingData", "nInitialDriveGears"),
        drive = drive,
        engineModifier = engineLevel >= 0 and GetVehicleModModifierValue(vehicle, 11, engineLevel) or 0,
        turbo = IsToggleModOn(vehicle, 18),
        cheat = GetVehicleCheatPowerIncrease(vehicle),
        extra = extra,
        wheelRadius = axles and (drive == "RWD" and axles.rearRadius or axles.frontRadius) or 0.33,
        frontRadius = axles and axles.frontRadius or 0.33,
        wheelbase = axles and axles.front - axles.rear or 2.6,
    }

    return inputs, factors
end

-- Prints every input of the vehicle the player sits in and what the formula makes of it, for tuning the scale
RegisterNetEvent("zyke_dyno:Calibrate", function()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if (vehicle == 0) then Z.notify("reason:notInVehicle") return end

    local inputs, factors = DynoInputs.read(vehicle)
    local power = DynoFormula.getPower(inputs)
    local curve = DynoFormula.getCurve(inputs, 1)
    local hp = DynoFormula.toPowerUnit

    print(("[zyke_dyno] %s class %d %s, %d gears"):format(inputs.model, inputs.class, inputs.drive, inputs.gears))
    print(("  fInitialDriveForce %.4f  fMass %.1f  fInitialDriveMaxFlatVel %.2f"):format(inputs.force, inputs.mass, inputs.topSpeed))
    print(("  base %.1f hp x class %.2f x model %.2f x engine mod %.3f x turbo %.2f x torque multiplier %.3f x modifiers %.3f"):format(power.base, power.class, power.model, power.engine, power.turbo, power.cheat, power.extra))

    for name, factor in pairs(factors) do
        print(("    modifier %s %.3f"):format(name, factor))
    end

    print(("  engine %.1f hp, wheels %.1f hp at %.0f rpm (loss %.0f%%), %.1f Nm at %.0f rpm"):format(hp(power.engineKw, "hp"), hp(curve.wheelKw, "hp"), curve.powerRpm, curve.loss * 100, curve.wheelNm, curve.torqueRpm))

    Z.notify("calibrationPrinted", {inputs.model, math.floor(hp(power.engineKw) + 0.5)})
end)