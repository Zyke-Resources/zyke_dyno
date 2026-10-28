-- Each dyno kind's prop measurements, matching the models in stream/, and the dyno frame: x right, y toward the nose,
-- z up, from the floor under the front wheels (the middle of the front rollers, or the chock on a bike dyno)
DynoGeometry = {}

---@alias DynoKind "car" | "bike"

---@class DynoKindGeometry
---@field models {bed: string, roller: string, carriage: string}
---@field vehicleType string @ GetVehicleType of the vehicles that go on it
---@field deckHeight number @ Metres from the floor to the deck the wheels stand on
---@field rollerRadius number
---@field rollerHeight number @ Metres from the floor to the rollers' axes
---@field front number[] @ The front cradle's rollers, metres along the dyno from its middle, none where a chock holds the wheel
---@field rear number[] @ The rear cradle's rollers, from where it stands
---@field chock? {y: number, angle: number, base: number, gap: number} @ Where its stop meets its base plate, the stop's rise in degrees, the plate's thickness and how far the tyre is posed off the stop
---@field rearNearest number @ Where the rear cradle may stand along the dyno, so it reaches every wheelbase
---@field rearFurthest number @ Where the rear cradle waits, so its cover plate closes the slot a vehicle drives in over
---@field footprint {min: vector2, max: vector2} @ The floor the bed covers with its ramps, from its rear left corner to its front right one
---@field deck {min: vector2, max: vector2} @ Where a vehicle counts as standing on it
---@field strip number @ Half the width of the guide strip where the front wheels go
---@field locale table<string, string> @ Locale keys of what it tells the player, see client/guide.lua and client/admin.lua

-- The kinds in the order the placing tool goes through them
---@type DynoKind[]
DynoGeometry.order = {"car", "bike"}

---@type table<DynoKind, DynoKindGeometry>
DynoGeometry.kinds = {
    car = {
        models = {bed = "zyke_dyno_bed", roller = "zyke_dyno_roller", carriage = "zyke_dyno_carriage"},
        vehicleType = "automobile",
        deckHeight = 0.24,
        rollerRadius = 0.09,
        rollerHeight = 0.155,
        -- Each axle sits in a cradle of two rollers, this far in front of and behind the cradle's middle
        front = {0.17, -0.17},
        rear = {0.17, -0.17},
        rearNearest = -2.05,
        rearFurthest = -3.45,
        footprint = {min = vec2(-1.3, -5.2), max = vec2(1.3, 2.0)},
        deck = {min = vec2(-1.3, -4.6), max = vec2(1.3, 1.0)},
        strip = 1.1,
        locale = {
            notLinedUp = "reason:notLinedUp",
            notStraight = "reason:notStraight",
            wheelbaseOff = "reason:wheelbaseOff",
            forward = "guide:forward",
            back = "guide:back",
            pull = "hint:pull",
            standby = "nui:standbyHint",
            -- Said on a dyno of another kind to a vehicle that goes on this one
            goesHere = "reason:needsCarDyno",
            -- The placing tool's title while it places this kind, and its key's label that switches to it
            place = "title:placeDyno",
            switchTo = "control:kindCar",
        },
    },
    bike = {
        models = {bed = "zyke_dyno_bike_bed", roller = "zyke_dyno_bike_drum", carriage = "zyke_dyno_bike_carriage"},
        vehicleType = "bike",
        deckHeight = 0.32,
        rollerRadius = 0.145,
        rollerHeight = 0.18,
        -- The front wheel stands in a chock and the rear one on a single drum. The tyre is posed just off the chock's
        -- stop: touching it, the fork pushes the wheel up the stop as the bike settles
        front = {},
        rear = {0.0},
        chock = {y = 0.204, angle = 65.0, base = 0.006, gap = 0.02},
        rearNearest = -1.1,
        rearFurthest = -2.1,
        footprint = {min = vec2(-0.48, -4.1), max = vec2(0.48, 0.42)},
        deck = {min = vec2(-0.48, -3.4), max = vec2(0.48, 0.6)},
        strip = 0.12,
        locale = {
            notLinedUp = "reason:notInChock",
            notStraight = "reason:bikeNotStraight",
            wheelbaseOff = "reason:bikeWheelbaseOff",
            forward = "guide:chockForward",
            back = "guide:chockBack",
            pull = "hint:pullBike",
            standby = "nui:standbyHintBike",
            goesHere = "reason:needsBikeDyno",
            place = "title:placeBikeDyno",
            switchTo = "control:kindBike",
        },
    },
}

-- Metres two beds may overlap and still count as apart
local overlapSlack = 0.01
-- Metres apart in height that put two dynos on different floors
local overlapHeight = 3.0

---@param kind? string
---@return DynoKindGeometry geometry @ The car dyno's for a kind there is none of
function DynoGeometry.get(kind)
    return DynoGeometry.kinds[kind] or DynoGeometry.kinds.car
end

-- The kind of dyno a vehicle goes on, by its class and type, see Config.Settings.dyno.kinds
---@param class integer
---@param vehicleType string @ As GetVehicleType names it
---@return DynoKind? kind @ nil for a vehicle no dyno takes
function DynoGeometry.getKindFor(class, vehicleType)
    for kind, settings in pairs(Config.Settings.dyno.kinds) do
        local geometry = DynoGeometry.kinds[kind]

        if (geometry and geometry.vehicleType == vehicleType) then
            for i = 1, #settings.allowedClasses do
                if (settings.allowedClasses[i] == class) then return kind end
            end
        end
    end

    return nil
end

-- Why a vehicle that goes on another kind of dyno, or on none, can not go on this one
---@param kind DynoKind @ The dyno's
---@param vehicleKind? DynoKind @ The vehicle's, see getKindFor
---@return string? reason @ Locale key, nil when it goes on this one
function DynoGeometry.getKindRefusal(kind, vehicleKind)
    if (vehicleKind == kind) then return nil end
    if (not vehicleKind) then return "reason:classNotAllowed" end

    return DynoGeometry.get(vehicleKind).locale.goesHere
end

---@param dyno {coords: vector3, heading: number}
---@param offset vector3
---@return vector3 world
function DynoGeometry.toWorld(dyno, offset)
    local turn = math.rad(dyno.heading)
    local cos, sin = math.cos(turn), math.sin(turn)

    return dyno.coords + vec3(offset.x * cos - offset.y * sin, offset.x * sin + offset.y * cos, offset.z)
end

---@param dyno {coords: vector3, heading: number}
---@param world vector3
---@return vector3 offset
function DynoGeometry.toLocal(dyno, world)
    local turn = math.rad(dyno.heading)
    local cos, sin = math.cos(turn), math.sin(turn)
    local delta = world - dyno.coords

    return vec3(delta.x * cos + delta.y * sin, -delta.x * sin + delta.y * cos, delta.z)
end

-- Where the centre of a wheel stands in a cradle: between its two rollers, on top of its one roller, or leaning
-- into the chock where it has none
---@param geometry DynoKindGeometry
---@param rollers number[] @ The cradle's rollers, its front or rear
---@param wheelRadius number
---@return number y @ Metres along the dyno from the cradle's middle
---@return number z @ Metres off the floor
function DynoGeometry.getSeat(geometry, rollers, wheelRadius)
    local chock = geometry.chock
    if (#rollers == 0 and chock) then return chock.y - chock.gap - wheelRadius * math.tan(math.rad(chock.angle) / 2.0), geometry.deckHeight + chock.base + wheelRadius end

    local reach = wheelRadius + geometry.rollerRadius
    local spread = #rollers > 1 and math.abs(rollers[1] - rollers[2]) / 2.0 or 0.0

    return 0.0, geometry.rollerHeight + math.sqrt(math.max(reach * reach - spread * spread, 0.0))
end

-- Where the rear cradle stands for a vehicle of this wheelbase whose front wheel stands in the front cradle, and
-- whether it reaches there
---@param geometry DynoKindGeometry
---@param wheelbase number
---@param frontRadius number
---@return number y
---@return boolean reaches
function DynoGeometry.getRearCradle(geometry, wheelbase, frontRadius)
    local rear = DynoGeometry.getSeat(geometry, geometry.front, frontRadius) - wheelbase
    local reaches = rear <= geometry.rearNearest + 0.05 and rear >= geometry.rearFurthest - 0.05

    return math.max(geometry.rearFurthest, math.min(geometry.rearNearest, rear)), reaches
end

---@param dyno {coords: vector3, heading: number, kind?: DynoKind}
---@return vector2 middle @ The middle of the bed's floor in the world
---@return vector2 across @ The dyno's x in the world
---@return vector2 along @ Its y, the way a vehicle's nose points on it
---@return {min: vector2, max: vector2} footprint
local function getFloor(dyno)
    local footprint = DynoGeometry.get(dyno.kind).footprint
    local middle = DynoGeometry.toWorld(dyno, vec3((footprint.min.x + footprint.max.x) / 2.0, (footprint.min.y + footprint.max.y) / 2.0, 0.0))
    local turn = math.rad(dyno.heading)
    local cos, sin = math.cos(turn), math.sin(turn)

    return middle.xy, vec2(cos, sin), vec2(-sin, cos), footprint
end

---@param dyno {coords: vector3, heading: number, kind?: DynoKind}
---@param axis vector2
---@return number reach @ Metres the bed reaches out from its middle along the axis
local function getFloorReach(dyno, axis)
    local _, across, along, footprint = getFloor(dyno)

    return (footprint.max.x - footprint.min.x) / 2.0 * math.abs(axis.x * across.x + axis.y * across.y) + (footprint.max.y - footprint.min.y) / 2.0 * math.abs(axis.x * along.x + axis.y * along.y)
end

-- Two dynos whose beds cross, where the props of both would stand in each other
---@param one {coords: vector3, heading: number, kind?: DynoKind}
---@param other {coords: vector3, heading: number, kind?: DynoKind}
---@return boolean overlapping
function DynoGeometry.doOverlap(one, other)
    if (math.abs(one.coords.z - other.coords.z) > overlapHeight) then return false end

    local oneMiddle, oneAcross, oneAlong = getFloor(one)
    local otherMiddle, otherAcross, otherAlong = getFloor(other)
    local offset = otherMiddle - oneMiddle

    for _, axis in ipairs({oneAcross, oneAlong, otherAcross, otherAlong}) do
        local apart = math.abs(offset.x * axis.x + offset.y * axis.y)
        if (apart >= getFloorReach(one, axis) + getFloorReach(other, axis) - overlapSlack) then return false end
    end

    return true
end

-- Where a placed dyno's screen stands, on the side the placing tool gave it, see Config.Settings.dyno.kinds
---@param kind DynoKind
---@param side DynoScreenSide
---@return {offset: vector3, heading: number}? screen
function DynoGeometry.getPlacedScreen(kind, side)
    local settings = Config.Settings.dyno.kinds[kind]
    local screen = settings and settings.screen
    if (not screen or side == "none") then return nil end
    if (side == "left") then return {offset = screen.offset, heading = screen.heading} end

    return {offset = vec3(-screen.offset.x, screen.offset.y, screen.offset.z), heading = (360.0 - screen.heading) % 360.0}
end

-- Where a dyno's result is printed: at its screen, or where a placed dyno's screen would stand on its left
---@param dyno {kind?: DynoKind, screen?: {offset: vector3}}
---@return vector3 offset @ On the floor, in the dyno's frame
function DynoGeometry.getPrintFloor(dyno)
    if (dyno.screen) then return dyno.screen.offset end

    local screen = DynoGeometry.getPlacedScreen(dyno.kind or "car", "left")

    return screen and screen.offset or vec3(0.0, 0.0, 0.0)
end