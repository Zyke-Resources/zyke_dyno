-- The props of each dyno within reach, local to this client. client/run.lua turns the rollers during a run

---@class DynoPropSet
---@field kind DynoKind
---@field bed integer
---@field front integer[] @ The front cradle's rollers, nose side first, none on a bike dyno
---@field rear integer[]
---@field carriage integer
---@field screen? integer
---@field rearY number @ Where the rear cradle stands along the dyno
---@field frontAngle number @ Radians each cradle's rollers have turned
---@field rearAngle number

DynoProps = {}

local settings = Config.Settings.dyno
local geometry = DynoGeometry

-- Between looks at which dynos are within reach
local streamCheckMs = 1000

---@type table<integer, DynoPropSet>
local spawned = {}

---@param model string
---@param coords vector3
---@return integer? entity
local function spawnProp(model, coords)
    if (not Z.loadModel(model, true)) then return nil end

    local entity = CreateObjectNoOffset(joaat(model), coords.x, coords.y, coords.z, false, false, false)

    FreezeEntityPosition(entity, true)
    SetModelAsNoLongerNeeded(joaat(model))

    return entity
end

-- Every prop of a set, the screen last since a set without one stops a loop over them there
---@param set DynoPropSet
---@return integer[] entities
local function getEntities(set)
    local entities = {set.bed, set.carriage}

    for _, rollers in ipairs({set.front, set.rear}) do
        for _, roller in ipairs(rollers) do
            entities[#entities + 1] = roller
        end
    end

    entities[#entities + 1] = set.screen

    return entities
end

-- Stands a cradle's rollers on their axes, turned round them by angle. The rollers of a cradle share one turn, so it
-- is worked out once for them all, as this runs every frame of a run
---@param dyno {coords: vector3, heading: number}
---@param layout DynoKindGeometry
---@param rollers integer[]
---@param offsets number[] @ Each roller's metres along the dyno from the cradle's middle, see DynoKindGeometry
---@param y number @ Metres along the dyno the cradle's middle stands
---@param angle number @ Radians
local function poseCradle(dyno, layout, rollers, offsets, y, angle)
    if (not offsets[1]) then return end

    local turn = math.rad(dyno.heading)
    local right = vec3(math.cos(turn), math.sin(turn), 0.0)
    local forward = vec3(-right.y, right.x, 0.0)
    local cos, sin = math.cos(angle), math.sin(angle)
    local spunForward = forward * cos + vec3(0.0, 0.0, sin)
    local spunUp = forward * -sin + vec3(0.0, 0.0, cos)
    local middle = dyno.coords + forward * y + vec3(0.0, 0.0, layout.rollerHeight)

    for i = 1, #offsets do
        local at = middle + forward * offsets[i]

        SetEntityMatrix(rollers[i], spunForward.x, spunForward.y, spunForward.z, right.x, right.y, right.z, spunUp.x, spunUp.y, spunUp.z, at.x, at.y, at.z)
    end
end

-- Stands the front cradle's rollers, the rear cradle's or both at the set's angles, the rear ones where that cradle
-- stands along the dyno
---@param set DynoPropSet
---@param dyno {coords: vector3, heading: number}
---@param front boolean
---@param rear boolean
local function poseRollers(set, dyno, front, rear)
    local layout = geometry.get(set.kind)

    if (front) then poseCradle(dyno, layout, set.front, layout.front, 0.0, set.frontAngle) end
    if (rear) then poseCradle(dyno, layout, set.rear, layout.rear, set.rearY, set.rearAngle) end
end

---@param set DynoPropSet
---@param dyno {coords: vector3, heading: number}
local function poseCarriage(set, dyno)
    local carriage = geometry.toWorld(dyno, vec3(0.0, set.rearY, 0.0))

    SetEntityCoordsNoOffset(set.carriage, carriage.x, carriage.y, carriage.z, false, false, false)
    SetEntityHeading(set.carriage, dyno.heading)
end

-- Turns a set's rollers, slides its rear cradle along the dyno and stands its bed and screen
---@param set DynoPropSet
---@param dyno {coords: vector3, heading: number, screen?: {offset: vector3, heading: number}}
local function poseSet(set, dyno)
    SetEntityCoordsNoOffset(set.bed, dyno.coords.x, dyno.coords.y, dyno.coords.z, false, false, false)
    SetEntityHeading(set.bed, dyno.heading)

    poseRollers(set, dyno, true, true)
    poseCarriage(set, dyno)

    if (not set.screen) then return end

    SetEntityVisible(set.screen, dyno.screen ~= nil, false)

    if (not dyno.screen) then return end

    local at = geometry.toWorld(dyno, dyno.screen.offset + vec3(0.0, 0.0, settings.screen.height))

    SetEntityCoordsNoOffset(set.screen, at.x, at.y, at.z, false, false, false)
    SetEntityHeading(set.screen, dyno.heading + dyno.screen.heading)
end

-- Turns both cradles' rollers and slides the rear cradle along the dyno. Runs every frame of a run, so only what
-- turned or slid is placed again: the bed and the screen stand still
---@param dynoId integer
---@param frontAngle number
---@param rearAngle number
---@param rearY number
function DynoProps.pose(dynoId, frontAngle, rearAngle, rearY)
    local set = spawned[dynoId]
    if (not set) then return end

    local dyno = GetDynos()[dynoId]
    if (not dyno) then return end

    local turnedFront, turnedRear, slid = frontAngle ~= set.frontAngle, rearAngle ~= set.rearAngle, rearY ~= set.rearY

    set.frontAngle, set.rearAngle, set.rearY = frontAngle, rearAngle, rearY

    poseRollers(set, dyno, turnedFront, turnedRear or slid)

    if (slid) then poseCarriage(set, dyno) end
end

---@param dynoId integer
---@return DynoPropSet? set
function DynoProps.get(dynoId)
    return spawned[dynoId]
end

-- The props of a dyno, the screen's only when it has one
---@param dyno {coords: vector3, heading: number, kind?: DynoKind, screen?: {offset: vector3, heading: number}}
---@param withScreen boolean
---@return DynoPropSet? set
local function makeSet(dyno, withScreen)
    local kind = dyno.kind or "car"
    local layout = geometry.get(kind)
    local bed = spawnProp(layout.models.bed, dyno.coords)
    if (not bed) then return nil end

    local set = {kind = kind, bed = bed, front = {}, rear = {}, rearY = layout.rearFurthest, frontAngle = 0.0, rearAngle = 0.0}

    for i = 1, #layout.front do
        set.front[i] = spawnProp(layout.models.roller, dyno.coords)
    end

    for i = 1, #layout.rear do
        set.rear[i] = spawnProp(layout.models.roller, dyno.coords)
    end

    set.carriage = spawnProp(layout.models.carriage, dyno.coords)

    if (withScreen) then set.screen = spawnProp(settings.screen.model, dyno.coords) end

    poseSet(set, dyno)

    return set
end

---@param set DynoPropSet
local function deleteSet(set)
    for _, entity in ipairs(getEntities(set)) do
        if (DoesEntityExist(entity)) then DeleteEntity(entity) end
    end
end

---@param dynoId integer
---@param dyno ZykeDyno
local function spawnSet(dynoId, dyno)
    spawned[dynoId] = makeSet(dyno, dyno.screen ~= nil)
end

---@param dynoId integer
local function removeSet(dynoId)
    local set = spawned[dynoId]
    if (not set) then return end

    spawned[dynoId] = nil

    deleteSet(set)
end

-- A see-through copy of a dyno for the placing tool, see client/admin.lua, that nothing collides with
---@param alpha integer
---@param kind DynoKind
---@return DynoPropSet? ghost
function DynoProps.makeGhost(alpha, kind)
    local at = GetEntityCoords(PlayerPedId()) - vec3(0.0, 0.0, 50.0)
    local ghost = makeSet({coords = at, heading = 0.0, kind = kind}, true)
    if (not ghost) then return nil end

    for _, entity in ipairs(getEntities(ghost)) do
        SetEntityCollision(entity, false, false)
        SetEntityAlpha(entity, alpha, false)
    end

    return ghost
end

-- Stands the copy where the dyno would stand, or hides it
---@param ghost DynoPropSet
---@param dyno? {coords: vector3, heading: number, screen?: {offset: vector3, heading: number}}
function DynoProps.poseGhost(ghost, dyno)
    for _, entity in ipairs(getEntities(ghost)) do
        SetEntityVisible(entity, dyno ~= nil, false)
    end

    if (dyno) then poseSet(ghost, dyno) end
end

---@param ghost DynoPropSet
function DynoProps.removeGhost(ghost)
    deleteSet(ghost)
end

---@param entity integer
---@return integer? dynoId @ The dyno one of whose props this client stands the entity is
function DynoProps.getDynoOfEntity(entity)
    if (entity == 0) then return nil end

    for dynoId, set in pairs(spawned) do
        for _, prop in ipairs(getEntities(set)) do
            if (prop == entity) then return dynoId end
        end
    end

    return nil
end

-- A dyno that moved or went away takes its props with it
local function streamProps()
    local coords = GetEntityCoords(PlayerPedId())
    local dynos = GetDynos()

    for dynoId in pairs(spawned) do
        local dyno = dynos[dynoId]
        if (not dyno or #(dyno.coords - coords) > settings.streamDistance + 10.0) then removeSet(dynoId) end
    end

    for dynoId, dyno in pairs(dynos) do
        if (not spawned[dynoId] and #(dyno.coords - coords) <= settings.streamDistance) then spawnSet(dynoId, dyno) end
    end
end

-- A dyno that stood somewhere else before, or was another kind, stands again as it is now
---@param dynos table<integer, ZykeDyno>
OnDynosChange(function(dynos)
    for dynoId, set in pairs(spawned) do
        local dyno = dynos[dynoId]
        if (not dyno or #(GetEntityCoords(set.bed) - dyno.coords) > 0.05 or (dyno.kind or "car") ~= set.kind) then removeSet(dynoId) end
    end
end)

CreateThread(function()
    while (true) do
        streamProps()

        Wait(streamCheckMs)
    end
end)

---@param resource string
AddEventHandler("onResourceStop", function(resource)
    if (resource ~= ResName) then return end

    for dynoId in pairs(spawned) do
        removeSet(dynoId)
    end
end)