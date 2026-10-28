-- The point at each dyno's screen that lists its last runs to print, a zyke_lib interest point or a target option,
-- see interaction in shared/config.lua. The server checks every list and print again in server/share.lua

local settings = Config.Settings.dyno
if (not settings.printout.enabled) then return end

local markerSet = "print"
local printKey = "zyke_dyno_printSheet"

-- Metres from the player
local markerDistance = 6.0
local reach = 2.0

local nearMs = 300
local idleMs = 1000

-- Metres over the floor the point stands at beside a dyno without a screen
local bareHeight = 1.1

---@type table<string, integer> @ The dyno of each marked point, by point id
local markedDynos = {}
-- The points last sent to zyke_lib, by dyno and entity
local markedKey = ""

---@type table<integer, integer> @ The entity holding each dyno's target option, by dyno id
local targets = {}

-- The list is open, so a second press does not stack another
local listing = false

-- The dyno stands between runs and the player's job may use it
---@param dyno ZykeDyno
---@return boolean mayPrint
local function mayPrint(dyno)
    if (dyno.run) then return false end

    local jobs = dyno.jobs or settings.jobs

    return not jobs or Z.isJob(jobs)
end

-- The screen the point stands on, or the bed of a dyno without one, and the point in that entity's frame
---@param dynoId integer
---@param dyno ZykeDyno
---@return integer? entity
---@return vector3? offset
local function getSpot(dynoId, dyno)
    local set = DynoProps.get(dynoId)
    if (not set) then return nil end
    if (set.screen and dyno.screen) then return set.screen, DynoScreen.getPrintOffset() end

    return set.bed, DynoGeometry.getPrintFloor(dyno) + vec3(0.0, 0.0, bareHeight)
end

---@param entry DynoPrintEntry
---@return ContextOption option
local function getOption(entry)
    local units = settings.units
    local power, torque = T("unit:" .. units.power), T("unit:" .. units.torque)

    return {
        title = entry.label or entry.plate,
        description = ("%s  |  %.0f %s  |  %s"):format(entry.plate, DynoFormula.toPowerUnit(entry.wheelKw), power, entry.date),
        icon = "print",
        args = entry.rowId,
        metadata = {
            {label = T("nui:plate"), value = entry.plate},
            {label = T("nui:peakPower"), value = ("%.0f %s %s %.0f %s"):format(DynoFormula.toPowerUnit(entry.wheelKw), power, T("nui:at"), entry.powerRpm, T("nui:rpm"))},
            {label = T("nui:peakTorque"), value = ("%.0f %s %s %.0f %s"):format(DynoFormula.toTorqueUnit(entry.wheelNm), torque, T("nui:at"), entry.torqueRpm, T("nui:rpm"))},
            {label = T("nui:engine"), value = ("%.0f %s"):format(DynoFormula.toPowerUnit(entry.engineKw), power)},
            {label = T("nui:drivetrain"), value = entry.drive},
            {label = T("nui:date"), value = entry.date},
        },
    }
end

-- The run the player picks from the dyno's last runs, newest first
---@param dynoId integer
---@return integer? rowId
local function pickRun(dynoId)
    local entries = Z.callback.request("zyke_dyno:GetPrintList", nil, dynoId)
    if (not entries) then return nil end
    if (#entries == 0) then Z.notify("noSheets") return nil end

    local options = {}

    for i = 1, #entries do
        options[i] = getOption(entries[i])
    end

    local rowId = Z.openContext({title = T("title:sheets"), description = T("menu:sheetsHint"), icon = "print", options = options})

    return math.type(rowId) == "integer" and rowId or nil
end

---@param dynoId integer
local function openList(dynoId)
    if (listing) then return end

    listing = true

    local rowId = pickRun(dynoId)

    listing = false

    if (not rowId) then return end

    TriggerServerEvent("zyke_dyno:PrintSheet", dynoId, rowId)
end

local function clearPoints()
    markedDynos = {}

    if (markedKey == "") then return end

    markedKey = ""

    Z.clearInterestPoints(markerSet)
end

---@param dynoId integer
---@param dyno ZykeDyno
---@param coords vector3 @ The player's
---@return InterestPoint? point
local function getPoint(dynoId, dyno, coords)
    local entity, offset = getSpot(dynoId, dyno)
    if (not entity or not offset) then return nil end

    local spot = GetOffsetFromEntityInWorldCoords(entity, offset.x, offset.y, offset.z)
    if (#(spot - coords) > markerDistance or not mayPrint(dyno)) then return nil end

    return {id = tostring(dynoId), entity = entity, offset = offset, key = "+" .. printKey, label = T("control:print"), reach = reach}
end

-- Marks the print points near the player on foot
---@return boolean near @ A point is marked, so the next look comes sooner
local function refreshPoints()
    local ped = PlayerPedId()
    if (IsPedInAnyVehicle(ped, false) or IsEntityDead(ped)) then clearPoints() return false end

    local coords = GetEntityCoords(ped)
    local points, dynosById, keys = {}, {}, {}

    for dynoId, dyno in pairs(GetDynos()) do
        local point = getPoint(dynoId, dyno, coords)

        if (point) then
            points[#points + 1] = point
            dynosById[point.id] = dynoId
            keys[#keys + 1] = point.id .. ":" .. point.entity
        end
    end

    if (#points == 0) then clearPoints() return false end

    local key = table.concat(keys, "|")
    if (key ~= markedKey) then Z.setInterestPoints(markerSet, points, {aim = true}) end

    markedDynos, markedKey = dynosById, key

    return true
end

local function onPrintKey()
    local pointId = Z.getAimedInterestPoint(markerSet)
    local dynoId = pointId and markedDynos[pointId]
    if (not dynoId) then return end

    -- The result can go between looks, such as a run starting
    local dyno = GetDynos()[dynoId]
    if (not dyno or not mayPrint(dyno)) then Z.shakeInterestPoint(markerSet, pointId) return end

    openList(dynoId)
end

---@param dynoId integer
---@param entity integer
local function addTarget(dynoId, entity)
    targets[dynoId] = entity

    Z.target.addEntity(entity, {distance = reach, options = {{
        name = "zyke_dyno:print",
        icon = "fas fa-print",
        label = T("control:print"),
        canInteract = function()
            local dyno = GetDynos()[dynoId]

            return dyno ~= nil and mayPrint(dyno)
        end,
        -- The list waits on the server, which the target resource's handler may not allow
        onSelect = function()
            CreateThread(function()
                openList(dynoId)
            end)
        end,
    }}})
end

-- Keeps one target option on the screen, or the bed, of each dyno whose props stand
local function refreshTargets()
    local dynos = GetDynos()

    for dynoId, entity in pairs(targets) do
        local dyno = dynos[dynoId]

        if (not dyno or getSpot(dynoId, dyno) ~= entity) then
            Z.target.remove(entity)

            targets[dynoId] = nil
        end
    end

    for dynoId, dyno in pairs(dynos) do
        local entity = getSpot(dynoId, dyno)
        if (entity and not targets[dynoId]) then addTarget(dynoId, entity) end
    end
end

-- Target is set by zyke_lib's loader, so the mode is picked once it has finished
CreateThread(function()
    while (not HasLoaderFinished) do Wait(10) end

    if (settings.interaction == "target") then
        if (Target) then
            while (true) do
                refreshTargets()

                Wait(idleMs)
            end
        end

        print(("^3[%s] interaction is set to \"target\" but neither ox_target nor qb-target is started, using interaction points^7"):format(ResName))
    end

    Z.registerKey(printKey, settings.keys.printSheet, T("keymap:printSheet"), onPrintKey)

    while (true) do
        Wait(refreshPoints() and nearMs or idleMs)
    end
end)

---@param resource string
AddEventHandler("onResourceStop", function(resource)
    if (resource ~= ResName) then return end

    clearPoints()

    for _, entity in pairs(targets) do
        Z.target.remove(entity)
    end
end)