-- The "/dynos" placing tool. Only dynos placed with it can be taken away again, see server/placed.lua

local geometry = DynoGeometry
local keys = Config.Settings.dyno.keys

-- Metres from the player, the server allows a little over
local placeReach = 12.0

-- Metres
local lineRange = 30.0
-- How much nearer another line has to be to take over
local lineKeep = 0.3
local lineStep = 0.05

-- Metres
local lineLength = 30.0
-- Keeps the line from flickering in the floor
local lineLift = 0.03

-- Metres in from the deck's rear end and on past its front
local arrowIn, arrowOut = 0.6, 0.5

-- Degrees per scroll wheel step
local turnStep = 1.0
local turnFast = 10.0

local shiftControl = 21

---@type table<DynoScreenSide, DynoScreenSide>
local nextSide = {left = "right", right = "none", none = "left"}
---@type table<DynoScreenSide, string>
local sideLabels = {left = "control:screenLeft", right = "control:screenRight", none = "control:screenNone"}

-- Metres above or below a dyno's floor the cursor may be to aim at it
local floorSlack = 1.0

-- Shape test flags, 1 is the map and 16 props
local placeFlags = 1
local removeFlags = 17

local ghostAlpha = 170

-- Attack, aim, melee, pause, weapon wheel (Tab), sprint (Shift) and cover (Q)
local blockedControls = {24, 25, 140, 141, 142, 257, 263, 264, 14, 15, 16, 17, 37, 21, 44, 199, 200}

local colours = {line = {255, 255, 255, 150}, arrow = {110, 200, 130, 220}, wrong = {225, 60, 60, 220}}

-- Kept is a dyno the tool can not take away
---@type {removable: DynoBoxColours, kept: DynoBoxColours}
local boxColours = {
    removable = {floor = {110, 170, 255, 110}, side = {150, 185, 255, 38}, edge = {200, 220, 255, 140}},
    kept = {floor = {225, 60, 60, 110}, side = {225, 60, 60, 38}, edge = {255, 140, 140, 140}},
}

-- Metres over the bed
local boxClearance = 0.05
-- Read from each kind's bed model once
---@type table<DynoKind, number>
local boxHeights = {}

---@class DynoPlaceLine
---@field dynoId integer
---@field axis "across" | "along"

---@class DynoPlaceSession
---@field removing boolean @ Takes dynos away instead of placing them
---@field hover? integer @ The dyno aimed at while taking dynos away
---@field heading number @ Degrees, the way it is turned while free
---@field lined boolean @ Keeps to the line of the nearest dyno
---@field line? DynoPlaceLine @ The line it keeps to now
---@field onLine boolean @ The keys were set for it keeping to a line
---@field screen DynoScreenSide
---@field kind DynoKind
---@field coords? vector3 @ Where it stands now, nil while the camera is not on the floor
---@field placeHeading number @ The way it is turned now, the line's dyno's while lined up
---@field along? number @ Metres along the line from the dyno it runs through
---@field warning? string @ Locale key of why it can not be placed or taken away here
---@field ghost? DynoPropSet
---@field keybinds KeybindItem[]
---@field shown? string @ What the panel shows, so it is only sent when it changes
---@field busy boolean @ The server is being asked
---@field done boolean

---@type DynoPlaceSession?
local placing

---@param from vector3
---@param to vector3
---@param flags? integer @ What the line meets, the map by default
---@return vector3? hit @ Where the line first meets it
---@return integer entity @ The entity it met, 0 for the map
local function probe(from, to, flags)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, flags or placeFlags, PlayerPedId(), 0)
    local _, hit, at, _, entity = GetShapeTestResult(handle)

    return hit == 1 and at or nil, entity
end

---@param flags integer
---@return vector3? cursor @ Where the middle of the screen meets the floor, or a prop with removeFlags
---@return integer entity
local function getCursor(flags)
    local from = GetGameplayCamCoord()
    local rotation = GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local direction = vec3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local reach = #(from - GetEntityCoords(PlayerPedId())) + placeReach + 5.0

    return probe(from, from + direction * reach, flags)
end

---@param heading number
---@return vector2 across @ The dyno's x in the world
---@return vector2 along @ Its y, the way a vehicle's nose points on it
local function getAxes(heading)
    local turn = math.rad(heading)
    local c, s = math.cos(turn), math.sin(turn)

    return vec2(c, s), vec2(-s, c)
end

---@param dyno ZykeDyno
---@param axis "across" | "along"
---@return vector2 direction
local function getLineDirection(dyno, axis)
    local across, along = getAxes(dyno.heading)

    return axis == "across" and across or along
end

---@param dyno ZykeDyno
---@param axis "across" | "along"
---@param cursor vector3
---@return number off @ Metres from the cursor to the line
---@return number along @ Metres along the line from the dyno to the cursor
local function measureLine(dyno, axis, cursor)
    local direction = getLineDirection(dyno, axis)
    local offset = cursor.xy - dyno.coords.xy
    local along = offset.x * direction.x + offset.y * direction.y

    return #(offset - direction * along), along
end

-- The line nearest the cursor, across or along a dyno. The line held now stays until another one is clearly
-- nearer, so the copy does not flicker between two
---@param session DynoPlaceSession
---@param cursor vector3
---@return DynoPlaceLine? line
local function findLine(session, cursor)
    local held = session.line
    local best, bestOff, keptOff

    for dynoId, dyno in pairs(GetDynos()) do
        if (#(dyno.coords.xy - cursor.xy) <= lineRange) then
            for _, axis in ipairs({"across", "along"}) do
                local off = measureLine(dyno, axis, cursor)
                if (held and held.dynoId == dynoId and held.axis == axis) then keptOff = off end
                if (not bestOff or off < bestOff) then best, bestOff = {dynoId = dynoId, axis = axis}, off end
            end
        end
    end

    if (keptOff and keptOff <= bestOff + lineKeep) then return held end

    return best
end

-- Where the copy stands for the cursor: on it while free, and on the nearest line while lined up, on the floor
-- under that spot
---@param session DynoPlaceSession
---@param cursor vector3
local function locate(session, cursor)
    session.line = session.lined and findLine(session, cursor) or nil

    local line = session.line
    local dyno = line and GetDynos()[line.dynoId]

    if (not line or not dyno) then
        session.coords = cursor
        session.placeHeading = session.heading
        session.along = nil

        return
    end

    local _, along = measureLine(dyno, line.axis, cursor)
    along = math.floor(along / lineStep + 0.5) * lineStep

    local at = dyno.coords.xy + getLineDirection(dyno, line.axis) * along
    local floor = probe(vec3(at.x, at.y, cursor.z + 1.0), vec3(at.x, at.y, cursor.z - 2.0))

    session.coords = vec3(at.x, at.y, floor and floor.z or cursor.z)
    session.placeHeading = dyno.heading
    session.along = along
end

-- The dyno whose bed the cursor is on, the one whose middle is nearest where two overlap
---@param cursor vector3
---@return integer? dynoId
local function findHovered(cursor)
    local best, bestDistance

    for dynoId, dyno in pairs(GetDynos()) do
        local footprint = geometry.get(dyno.kind).footprint
        local point = geometry.toLocal(dyno, cursor)
        local distance = #point.xy
        local under = point.x >= footprint.min.x and point.x <= footprint.max.x and point.y >= footprint.min.y and point.y <= footprint.max.y and math.abs(point.z) <= floorSlack
        if (under and (not bestDistance or distance < bestDistance)) then best, bestDistance = dynoId, distance end
    end

    return best
end

-- Only a dyno placed with the tool is taken away with it, since one of shared/dynos.lua or of another resource is
-- made again as that starts
---@param session DynoPlaceSession
---@return string? warning
local function getRemoveWarning(session)
    local dyno = session.hover and GetDynos()[session.hover]
    if (not dyno) then return "place:noDyno" end
    if (not dyno.placed) then return "place:notPlaced" end
    if (#(dyno.coords - GetEntityCoords(PlayerPedId())) > placeReach) then return "place:tooFar" end

    return nil
end

---@param session DynoPlaceSession
---@return boolean overlapping @ The copy stands in a dyno that stands already
local function isOverlapping(session)
    local placed = {coords = session.coords, heading = session.placeHeading, kind = session.kind}

    for _, dyno in pairs(GetDynos()) do
        if (geometry.doOverlap(dyno, placed)) then return true end
    end

    return false
end

---@param session DynoPlaceSession
local function updateWarning(session)
    local coords = session.coords

    if (session.removing) then
        session.warning = getRemoveWarning(session)
    elseif (not coords) then
        session.warning = "place:noFloor"
    elseif (#(coords - GetEntityCoords(PlayerPedId())) > placeReach) then
        session.warning = "place:tooFar"
    elseif (isOverlapping(session)) then
        session.warning = "place:overlap"
    else
        session.warning = nil
    end
end

---@param value number
---@return string shown @ To a tenth, without a trailing .0
local function formatNumber(value)
    return ("%g"):format(math.floor(value * 10.0 + 0.5) / 10.0)
end

-- The keys, with the way the copy is turned and what it keeps to beside the title, sent only when that changed
---@param session DynoPlaceSession
local function showPanel(session)
    local title, detail

    if (session.removing) then
        title = T("title:removeDyno")
        detail = session.hover and T("place:dynoId", {session.hover}) or nil
    else
        local heading = T("place:heading", {formatNumber(session.placeHeading % 360.0)})
        local line = session.line

        title = T(geometry.get(session.kind).locale.place)
        detail = line and ("%s  ·  %s"):format(heading, T("place:linedUp", {line.dynoId, ("%.2f"):format(math.abs(session.along or 0.0))})) or heading
    end

    local warning = session.warning and T(session.warning) or nil
    local shown = ("%s|%s|%s"):format(title, detail or "", warning or "")
    if (shown == session.shown) then return end

    session.shown = shown

    Z.keybinds.show(session.keybinds, {title = title, detail = detail, warning = warning})
end

-- The server places it, while the frames go on
---@param session DynoPlaceSession
local function confirm(session)
    if (session.busy) then return end

    local coords, heading, side, kind = session.coords, session.placeHeading % 360.0, session.screen, session.kind
    if (session.warning or not coords) then Z.notify("reason:actionUnavailable") return end

    session.busy = true

    CreateThread(function()
        local dynoId, notification = Z.callback.request("zyke_dyno:AddDyno", nil, coords, heading, side, kind)

        session.busy = false

        if (not dynoId) then Z.notify(notification or "reason:actionUnavailable") return end

        Z.notify("dynoPlaced", {dynoId})
    end)
end

-- The server takes the dyno aimed at away, while the frames go on
---@param session DynoPlaceSession
local function removeHovered(session)
    if (session.busy) then return end

    local dynoId = session.hover
    if (session.warning or not dynoId) then Z.notify("reason:actionUnavailable") return end

    session.busy = true

    CreateThread(function()
        local removed, notification = Z.callback.request("zyke_dyno:RemovePlacedDyno", nil, dynoId)

        session.busy = false

        if (not removed) then Z.notify(notification or "reason:actionUnavailable") return end

        Z.notify("dynoRemoved", {dynoId})
    end)
end

---@param session DynoPlaceSession
---@param key string
local function turn(session, key)
    local step = IsDisabledControlPressed(0, shiftControl) and turnFast or turnStep

    session.heading = (session.heading + (key == "SCROLLUP" and step or -step)) % 360.0
end

-- The copy of the kind placed now, made again when the kind changes
---@param session DynoPlaceSession
local function makeGhost(session)
    if (session.ghost) then DynoProps.removeGhost(session.ghost) end

    session.ghost = DynoProps.makeGhost(ghostAlpha, session.kind)
end

---@param kind DynoKind
---@return DynoKind next @ The kind after it, see DynoGeometry.order
local function getNextKind(kind)
    local order = geometry.order

    for i = 1, #order do
        if (order[i] == kind) then return order[i % #order + 1] end
    end

    return order[1]
end

---@param session DynoPlaceSession
local function setKeys(session)
    local keybinds

    session.onLine = session.line ~= nil

    if (session.removing) then
        keybinds = {{label = T("control:removeDyno"), key = "LEFTMOUSE", func = function() removeHovered(session) end}}
    else
        keybinds = {{label = T("control:placeDyno"), key = "LEFTMOUSE", func = function() confirm(session) end}}

        -- On a line, the dyno it lines up with turns it. With none near it stands free
        if (not session.onLine) then
            keybinds[#keybinds + 1] = {
                label = T("control:placeTurn"),
                key = {"SCROLLUP", "SCROLLDOWN"},
                ---@param key string @ SCROLLUP or SCROLLDOWN
                func = function(key) turn(session, key) end,
            }
            keybinds[#keybinds + 1] = {label = T("control:placeTurnFast"), key = "LEFTSHIFT", func = function() end}
        end

        keybinds[#keybinds + 1] = {
            label = T(session.lined and "control:placeFree" or "control:placeLine"),
            command = "zyke_dyno_placeLine",
            func = function()
                session.lined = not session.lined
                -- Free again, it stays turned the way the line had it
                session.heading = session.placeHeading

                setKeys(session)
            end,
        }
        keybinds[#keybinds + 1] = {
            label = T(sideLabels[nextSide[session.screen]]),
            command = "zyke_dyno_placeScreen",
            func = function()
                session.screen = nextSide[session.screen]

                setKeys(session)
            end,
        }
        keybinds[#keybinds + 1] = {
            label = T(geometry.get(getNextKind(session.kind)).locale.switchTo),
            command = "zyke_dyno_placeKind",
            func = function()
                session.kind = getNextKind(session.kind)

                makeGhost(session)
                setKeys(session)
            end,
        }
    end

    keybinds[#keybinds + 1] = {
        label = T(session.removing and "control:modePlace" or "control:modeRemove"),
        command = "zyke_dyno_placeMode",
        func = function()
            session.removing = not session.removing
            session.hover = nil

            setKeys(session)
        end,
    }
    keybinds[#keybinds + 1] = {label = T("control:placeDone"), key = "RIGHTMOUSE", hiddenKey = {"ESC", "BACKSPACE"}, func = function() session.done = true end}

    -- Refilled in place, as each items table is its own panel in zyke_lib and a new one would stack on the old
    for i = #session.keybinds, 1, -1 do
        session.keybinds[i] = nil
    end

    for i = 1, #keybinds do
        session.keybinds[i] = keybinds[i]
    end

    session.shown = nil
end

-- The copy where the dyno would stand, with its screen on the side picked, hidden while taking dynos away
---@param session DynoPlaceSession
local function poseGhost(session)
    local ghost = session.ghost
    if (not ghost) then return end

    local coords = session.coords

    DynoProps.poseGhost(ghost, coords and {coords = coords, heading = session.placeHeading, kind = session.kind, screen = geometry.getPlacedScreen(session.kind, session.screen)} or nil)
end

-- The line it keeps to, and an arrow over the deck the way a vehicle's nose points, red where it can not be placed
---@param session DynoPlaceSession
local function drawGuides(session)
    local coords = session.coords
    if (not coords) then return end

    local line = session.line
    local dyno = line and GetDynos()[line.dynoId]

    if (dyno) then
        local direction = getLineDirection(dyno, line.axis) * lineLength
        local middle = vec3(dyno.coords.x, dyno.coords.y, coords.z + lineLift)

        DynoDraw.line(middle - vec3(direction.x, direction.y, 0.0), middle + vec3(direction.x, direction.y, 0.0), colours.line)
    end

    local layout = geometry.get(session.kind)
    local across, along = getAxes(session.placeHeading)
    local z = coords.z + layout.deckHeight + lineLift
    local tip = coords.xy + along * (layout.deck.max.y + arrowOut)
    local base = coords.xy + along * (layout.deck.min.y + arrowIn)
    local colour = session.warning and colours.wrong or colours.arrow
    local head = vec3(tip.x, tip.y, z)

    DynoDraw.line(vec3(base.x, base.y, z), head, colour)
    DynoDraw.line(head, vec3(tip.x - along.x * 0.4 + across.x * 0.3, tip.y - along.y * 0.4 + across.y * 0.3, z), colour)
    DynoDraw.line(head, vec3(tip.x - along.x * 0.4 - across.x * 0.3, tip.y - along.y * 0.4 - across.y * 0.3, z), colour)
end

-- The bed stands on a dyno this client shows, so its model is loaded by the time one is aimed at
---@param kind DynoKind
---@return number height @ Metres, the top of the bed
local function getBoxHeight(kind)
    if (boxHeights[kind]) then return boxHeights[kind] end

    local _, most = GetModelDimensions(joaat(geometry.get(kind).models.bed))

    -- A model not loaded yet reads as nothing, and is read again the next frame
    if (most.z > 0.0) then boxHeights[kind] = most.z + boxClearance end

    return most.z + boxClearance
end

-- The box round the dyno aimed at while taking dynos away
---@param session DynoPlaceSession
local function drawHover(session)
    local dyno = session.hover and GetDynos()[session.hover]
    if (not dyno) then return end

    local footprint = geometry.get(dyno.kind).footprint

    DynoDraw.box(dyno, footprint.min, footprint.max, getBoxHeight(dyno.kind), session.warning and boxColours.kept or boxColours.removable)
end

---@param session DynoPlaceSession
local function runFrame(session)
    local cursor, entity = getCursor(session.removing and removeFlags or placeFlags)

    if (session.removing) then
        session.coords = nil
        session.line = nil
        -- A prop aimed at is its dyno's, and a floor under a bed that dyno's
        session.hover = DynoProps.getDynoOfEntity(entity) or (cursor and findHovered(cursor)) or nil
    elseif (cursor) then
        locate(session, cursor)
    else
        session.coords = nil
        session.line = nil
    end

    if ((session.line ~= nil) ~= session.onLine) then setKeys(session) end

    updateWarning(session)
    poseGhost(session)
    drawGuides(session)
    drawHover(session)
    showPanel(session)

    for i = 1, #blockedControls do
        DisableControlAction(0, blockedControls[i], true)
    end

    DisablePlayerFiring(PlayerId(), true)
    Z.keybinds.handle(session.keybinds)
end

Z.keybinds.addKeyMapping("zyke_dyno_placeLine", T("keymap:placeLine"), keys.placeLine)
Z.keybinds.addKeyMapping("zyke_dyno_placeScreen", T("keymap:placeScreen"), keys.placeScreen)
Z.keybinds.addKeyMapping("zyke_dyno_placeKind", T("keymap:placeKind"), keys.placeKind)
Z.keybinds.addKeyMapping("zyke_dyno_placeMode", T("keymap:placeMode"), keys.placeMode)

-- Takes the tool out until the admin puts it away
RegisterNetEvent("zyke_dyno:PlaceDyno", function()
    if (placing) then return end

    local ped = PlayerPedId()
    if (IsPedInAnyVehicle(ped, false)) then Z.notify("reason:actionUnavailable") return end

    local heading = math.floor(GetGameplayCamRot(2).z + 0.5) % 360.0

    ---@type DynoPlaceSession
    local session = {removing = false, heading = heading, placeHeading = heading, lined = true, onLine = false, screen = "left", kind = "car", keybinds = {}, busy = false, done = false}
    placing = session

    setKeys(session)
    makeGhost(session)

    if (session.ghost) then
        while (not session.done and placing == session and not IsEntityDead(ped)) do
            runFrame(session)

            Wait(0)
        end
    end

    Z.keybinds.hide(session.keybinds)

    if (session.ghost) then DynoProps.removeGhost(session.ghost) end
    if (placing == session) then placing = nil end
end)

-- A restart while the tool is out would leave the copy standing
---@param resource string
AddEventHandler("onResourceStop", function(resource)
    if (resource ~= ResName or not placing) then return end

    if (placing.ghost) then DynoProps.removeGhost(placing.ghost) end

    Z.keybinds.hide(placing.keybinds)
end)