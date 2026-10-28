-- The graph on every dyno screen near the player from one DUI used as an atlas: each screen gets a 1280x720 tile of
-- the page and its face is drawn from that tile, so one model and no render target serve every copy at once

DynoScreen = {}

local settings = Config.Settings.dyno
local screen = settings.screen

local nearCheckMs = 1000
-- Between looks at whether the camera sees each screen's face
local viewCheckMs = 100

-- Pixels of one screen's tile, 16:9 as its face
local tileWidth, tileHeight = 1280, 720
-- Tiles the DUI holds at most, two columns of them from three on
local maxSlots = 4

-- Metres off the face so it does not show through, under the bezel's 4 mm
local lift = 0.002

---@class DynoScreenSlot
---@field dynoId integer
---@field token integer @ Goes up per dyno given a tile, so a playing run sends itself again to it
---@field uv number[] @ Left, top, right and bottom of its tile in the DUI's texture
---@field set? DynoPropSet @ The props its face was placed from
---@field face? DynoScreenFace
---@field seen boolean @ The camera saw its face at the last look

---@type ZykeDuiInstance?
local dui
local slotCount, columns = 0, 1
local pageReady = false
---@type table<integer, DynoScreenSlot>
local slots = {}
-- Slot by dyno ID
---@type table<integer, integer>
local slotOf = {}
local token = 0

---@param dynoId integer
---@return integer? token @ nil while this dyno's screen has no tile
function DynoScreen.getToken(dynoId)
    local slot = slots[slotOf[dynoId]]
    if (not slot or not pageReady) then return nil end

    return slot.token
end

-- Updates to a screen nobody looks at can wait, as each one sent to the DUI takes about 0.1 ms
---@param dynoId integer
---@return boolean seen @ This dyno's screen has a tile and the camera sees its face
function DynoScreen.isSeen(dynoId)
    local slot = slots[slotOf[dynoId]]

    return slot ~= nil and slot.seen
end

---@param dynoId integer
---@param message {event: string, data?: table}
function DynoScreen.send(dynoId, message)
    local slot = slotOf[dynoId]
    if (not slot or not dui or not pageReady) then return end

    dui:sendMessage({event = message.event, slot = slot, data = message.data})
end

-- What the screen shows between runs: the last result on this dyno, if there is one, and how to get on it
---@param dynoId integer
local function sendStandby(dynoId)
    local dyno = GetDynos()[dynoId]
    local labels = DynoNui.getLabels()

    labels.standbyHint = T(DynoGeometry.get(dyno and dyno.kind).locale.standby)

    DynoScreen.send(dynoId, {event = "Labels", data = {labels = labels, units = settings.units}})
    DynoScreen.send(dynoId, {event = "Standby", data = {last = dyno and dyno.last}})
end

local function removeDui()
    if (dui) then dui:remove() end

    dui, slotCount, pageReady, slots, slotOf = nil, 0, false, {}, {}
end

-- Out of the front of a face whose corners run top left, top right, bottom right and bottom left
---@param corners vector3[]
---@return vector3 normal @ Not of unit length
local function getNormal(corners)
    local down, across = corners[4] - corners[1], corners[2] - corners[1]

    return vec3(down.y * across.z - down.z * across.y, down.z * across.x - down.x * across.z, down.x * across.y - down.y * across.x)
end

-- The screen's face in the model's frame, moved out along its normal by lift
---@return vector3[] corners @ Top left, top right, bottom right and bottom left as seen from the front
local function getLiftedFace()
    local face = screen.face
    local normal = getNormal(face)
    local out = normal / #normal * lift

    return {face[1] + out, face[2] + out, face[3] + out, face[4] + out}
end

local liftedFace = getLiftedFace()

-- Where the print point stands in the screen model's frame: 15 cm under the picture and 5 cm out from it, so its
-- marker leaves the graph clear
---@return vector3 offset
function DynoScreen.getPrintOffset()
    local face = screen.face
    local normal = getNormal(face)

    return (face[3] + face[4]) * 0.5 + normal / #normal * 0.05 - vec3(0.0, 0.0, 0.15)
end

---@class DynoScreenFace
---@field corners vector3[] @ In the world, in the order of getLiftedFace
---@field center vector3
---@field normal vector3 @ See getNormal
---@field radius number @ Metres from the centre to a corner

---@param entity integer @ The screen prop
---@return DynoScreenFace face
local function getFace(entity)
    ---@type vector3[]
    local corners = {}

    for i = 1, 4 do
        corners[i] = GetOffsetFromEntityInWorldCoords(entity, liftedFace[i].x, liftedFace[i].y, liftedFace[i].z)
    end

    local center = (corners[1] + corners[3]) * 0.5

    return {corners = corners, center = center, normal = getNormal(corners), radius = #(corners[1] - center)}
end

-- The camera stands in front of the face and has it in view
---@param face DynoScreenFace
---@return boolean seen
local function isFaceSeen(face)
    local toCamera = GetFinalRenderedCamCoord() - face.center
    if (toCamera.x * face.normal.x + toCamera.y * face.normal.y + toCamera.z * face.normal.z <= 0.0) then return false end

    return IsSphereVisible(face.center.x, face.center.y, face.center.z, face.radius)
end

-- Its tile in the DUI's texture, half a pixel in on each side so filtering does not bleed the next tile in
---@param slot integer
---@return number[] uv @ Left, top, right and bottom
local function getUv(slot)
    local column, row = (slot - 1) % columns, (slot - 1) // columns
    local width, height = tileWidth * columns, tileHeight * math.ceil(slotCount / columns)

    return {(column * tileWidth + 0.5) / width, (row * tileHeight + 0.5) / height, ((column + 1) * tileWidth - 0.5) / width, ((row + 1) * tileHeight - 0.5) / height}
end

-- Draws a tile of the DUI over a screen's face as two triangles in the world, wound so only their front shows
---@param instance ZykeDuiInstance
---@param corners vector3[] @ See getFace
---@param uv number[] @ See getUv
local function drawFace(instance, corners, uv)
    local topLeft, topRight, bottomRight, bottomLeft = corners[1], corners[2], corners[3], corners[4]
    local left, top, right, bottom = uv[1], uv[2], uv[3], uv[4]

    DrawTexturedPoly(topLeft.x, topLeft.y, topLeft.z, bottomLeft.x, bottomLeft.y, bottomLeft.z, topRight.x, topRight.y, topRight.z, 255, 255, 255, 255, instance.dictName, instance.txtName, left, top, 1.0, left, bottom, 1.0, right, top, 1.0)
    DrawTexturedPoly(topRight.x, topRight.y, topRight.z, bottomLeft.x, bottomLeft.y, bottomLeft.z, bottomRight.x, bottomRight.y, bottomRight.z, 255, 255, 255, 255, instance.dictName, instance.txtName, right, top, 1.0, left, bottom, 1.0, right, bottom, 1.0)
end

-- Places a tile's face again when its dyno's props were spawned anew, as they stand still otherwise, and looks at
-- which faces the camera sees
---@return DynoScreenSlot[] seen
local function lookAtFaces()
    local seen = {}

    for _, slot in pairs(slots) do
        local set = DynoProps.get(slot.dynoId)

        if (set ~= slot.set or not slot.face) then
            slot.set = set
            slot.face = set and set.screen and DoesEntityExist(set.screen) and getFace(set.screen) or nil
        end

        slot.seen = slot.face ~= nil and isFaceSeen(slot.face)

        if (slot.seen) then seen[#seen + 1] = slot end
    end

    return seen
end

-- Draws the seen faces every frame, and looks again every viewCheckMs. The page shows nothing until it has loaded,
-- and the screens stay dark until then
---@param instance ZykeDuiInstance
local function drawScreens(instance)
    while (dui == instance) do
        local seen = pageReady and lookAtFaces() or {}

        if (#seen > 0) then
            local lookAt = GetGameTimer() + viewCheckMs

            while (GetGameTimer() < lookAt and dui == instance) do
                for i = 1, #seen do
                    local slot = seen[i]

                    -- A tile given to another dyno since the look is not drawn on the old screen
                    if (slot.seen) then drawFace(instance, slot.face.corners, slot.uv) end
                end

                Wait(0)
            end
        else
            Wait(viewCheckMs)
        end
    end
end

---@param count integer @ Tiles
local function createDui(count)
    removeDui()

    local tileColumns = count > 2 and 2 or 1
    local url = ("nui://%s/nui/index.html?screen=1&slots=%d&columns=%d"):format(ResName, count, tileColumns)
    local instance = Z.dui:new({url = url, width = tileWidth * tileColumns, height = tileHeight * math.ceil(count / tileColumns)})
    if (not instance) then return end

    dui, slotCount, columns = instance, count, tileColumns

    CreateThread(function()
        drawScreens(instance)
    end)

    -- The page can not tell the DUI it has loaded, so it is given a moment before anything is sent
    SetTimeout(1500, function()
        if (dui ~= instance) then return end

        pageReady = true

        for dynoId in pairs(slotOf) do
            sendStandby(dynoId)
        end
    end)
end

-- Screens whose props have spawned, as many as the DUI needs tiles for: every screen near enough to come into reach
---@return integer count
local function countScreens()
    local count = 0

    for dynoId, dyno in pairs(GetDynos()) do
        if (dyno.screen and DynoProps.get(dynoId)) then count += 1 end
    end

    return math.min(count, maxSlots)
end

---@return integer[] dynoIds @ The dynos whose screens are within reach, nearest first
local function getNearest()
    local coords = GetEntityCoords(PlayerPedId())
    local found = {}

    for dynoId, dyno in pairs(GetDynos()) do
        local distance = dyno.screen and DynoProps.get(dynoId) and #(DynoGeometry.toWorld(dyno, dyno.screen.offset) - coords)
        if (distance and distance < settings.screenDistance) then found[#found + 1] = {dynoId = dynoId, distance = distance} end
    end

    table.sort(found, function(a, b)
        return a.distance < b.distance
    end)

    local dynoIds = {}

    for i = 1, #found do
        dynoIds[i] = found[i].dynoId
    end

    return dynoIds
end

-- Gives each of the nearest screens a tile. A screen keeps its tile while it stays among them, and one that leaves
-- frees its tile for the next
---@param nearest integer[] @ Dyno IDs, nearest first
local function assignSlots(nearest)
    local kept = {}

    for i = 1, math.min(#nearest, slotCount) do
        kept[nearest[i]] = true
    end

    for dynoId, slot in pairs(slotOf) do
        if (not kept[dynoId]) then
            slots[slot].seen = false
            slots[slot], slotOf[dynoId] = nil, nil
        end
    end

    for dynoId in pairs(kept) do
        if (not slotOf[dynoId]) then
            local slot = 1
            while (slots[slot]) do
                slot += 1
            end

            token += 1
            slots[slot] = {dynoId = dynoId, token = token, uv = getUv(slot), seen = false}
            slotOf[dynoId] = slot

            if (pageReady) then sendStandby(dynoId) end
        end
    end
end

-- A finished run leaves its result for the screen to show until the next one
---@param dynos table<integer, ZykeDyno>
OnDynosChange(function(dynos)
    for dynoId in pairs(slotOf) do
        if (dynos[dynoId] and not dynos[dynoId].run) then sendStandby(dynoId) end
    end
end)

-- A DUI lives only while a screen is within reach. It is made again with more tiles when more screens have spawned
-- than it holds, and with fewer only the next time it is made
CreateThread(function()
    while (true) do
        local nearest = getNearest()

        if (#nearest == 0) then
            if (dui) then removeDui() end
        else
            local count = countScreens()
            if (not dui or count > slotCount) then createDui(count) end

            if (dui) then assignSlots(nearest) end
        end

        Wait(nearCheckMs)
    end
end)