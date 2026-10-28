-- Connections to dynos from the zyke_laptop app. Every request checks again that the player is at a laptop and may
-- connect. The app only reads, it never starts or stops a run

local settings = Config.Settings.dyno
local laptop = settings.laptop
if (not laptop.enabled) then return end

-- Runs a history list holds at most
local historyLimit = 20

---@type table<PlayerId, integer> @ The dyno each player is connected to
local connections = {}

-- Read by server/dynos.lua, which passes a run's samples on to the players following it from a laptop
DynoLaptop = {}

---@param plyId PlayerId
---@param dynoId integer
---@return boolean connected
function DynoLaptop.isConnected(plyId, dynoId)
    return connections[plyId] == dynoId
end

---@class DynoLaptopEntry
---@field id integer
---@field label? string
---@field run? {plate: string, label: string}
---@field last? {plate: string, label: string, wheelKw: number, wheelNm: number, date: integer}
---@field distance number
---@field inRange boolean
---@field name? string @ The name the player gave it, which only they see
---@field saved? boolean @ The player connected to it before, see server/saved.lua

---@class DynoLaptopResult
---@field ok boolean
---@field error? string @ Locale key

---@class DynoLaptopConnection : DynoLaptopResult
---@field dyno DynoLaptopEntry
---@field last? DynoSheet

---@param plyId PlayerId
---@return boolean atLaptop
local function isAtLaptop(plyId)
    if (GetResourceState("zyke_laptop") ~= "started") then return false end

    return exports.zyke_laptop:IsAtLaptop(plyId) == true
end

---@param plyId PlayerId
---@param dyno ZykeDyno
---@return boolean allowed
local function hasAccess(plyId, dyno)
    local jobs = dyno.jobs or settings.jobs

    return not jobs or Z.isJob(plyId, jobs)
end

---@param plyId PlayerId
---@param dyno ZykeDyno
---@return number distance @ Metres from the player at the laptop to the dyno
local function getDistance(plyId, dyno)
    return #(GetEntityCoords(GetPlayerPed(plyId)) - dyno.coords)
end

-- Whether the player may connect to the dyno from where they stand
---@param plyId PlayerId
---@param dynoId any
---@return ZykeDyno? dyno
---@return string? err @ Locale key
local function checkDyno(plyId, dynoId)
    if (not isAtLaptop(plyId)) then return nil, "laptop:error:notAtLaptop" end

    local dyno = GetDynos()[tonumber(dynoId) or 0]
    if (not dyno) then return nil, "laptop:error:noDyno" end
    if (not hasAccess(plyId, dyno)) then return nil, "laptop:error:noAccess" end
    if (laptop.range and getDistance(plyId, dyno) > laptop.range) then return nil, "laptop:error:tooFar" end

    return dyno
end

-- The player's dyno, while they are still at a laptop and may still connect to it. A connection that no longer
-- holds is dropped
---@param plyId PlayerId
---@return integer? dynoId
---@return ZykeDyno? dyno
---@return string? err @ Locale key
local function getConnected(plyId)
    local dynoId = connections[plyId]
    if (not dynoId) then return nil, nil, "laptop:error:notConnected" end

    local dyno, err = checkDyno(plyId, dynoId)
    if (not dyno) then connections[plyId] = nil return nil, nil, err end

    return dynoId, dyno
end

---@param dynoKey string
---@return integer? dynoId
local function findDyno(dynoKey)
    for dynoId, dyno in pairs(GetDynos()) do
        if (DynoDatabase.getKey(dyno) == dynoKey) then return dynoId end
    end

    return nil
end

---@param plyId PlayerId
---@param dynoId integer
---@param dyno ZykeDyno
---@param name? string
---@return DynoLaptopEntry entry
local function getEntry(plyId, dynoId, dyno, name)
    local distance = getDistance(plyId, dyno)
    local last = dyno.last

    return {
        id = dynoId,
        label = dyno.label,
        name = name,
        run = dyno.run and {plate = dyno.run.plate, label = dyno.run.label} or nil,
        last = last and {plate = last.plate, label = last.label, wheelKw = last.wheelKw, wheelNm = last.wheelNm, date = last.date} or nil,
        distance = math.floor(distance + 0.5),
        inRange = not laptop.range or distance <= laptop.range,
    }
end

-- The connected dyno as the page shows it, with the name the player gave it
---@param plyId PlayerId
---@param dynoId integer
---@param dyno ZykeDyno
---@return DynoLaptopConnection connection
local function getConnection(plyId, dynoId, dyno)
    local identifier = Z.getIdentifier(plyId)
    local name = identifier and DynoSaved.getName(identifier, DynoDatabase.getKey(dyno))

    return {ok = true, dyno = getEntry(plyId, dynoId, dyno, name), last = dyno.last}
end

-- A name as the player typed it, on one line with single spaces and no more characters than the column holds. An
-- empty one gives the dyno its own name back
---@param name any
---@return string? name
---@return boolean valid
local function readName(name)
    if (type(name) ~= "string") then return nil, false end

    local trimmed = name:gsub("%c", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    local length = utf8.len(trimmed)
    if (not length) then return nil, false end
    if (length == 0) then return nil, true end
    if (length > DynoSaved.nameLength) then trimmed = trimmed:sub(1, utf8.offset(trimmed, DynoSaved.nameLength + 1) - 1):gsub(" $", "") end

    return trimmed, true
end

-- The dynos the player's job may use, the ones out of range included so the list says why they can't connect.
-- The ones they connected to before come first, the most recent first
---@param plyId PlayerId
---@return {ok: boolean, error?: string, dynos?: DynoLaptopEntry[]} result
Z.callback.register("zyke_dyno:laptop:GetDynos", function(plyId)
    if (not isAtLaptop(plyId)) then return {ok = false, error = "laptop:error:notAtLaptop"} end

    local identifier = Z.getIdentifier(plyId)
    local rows = identifier and DynoSaved.get(identifier) or {}
    ---@type table<string, {rank: integer, name?: string}>
    local saved = {}
    ---@type table<integer, integer> @ Where each saved dyno stands in the player's saved list
    local ranks = {}
    local list = {}

    for i = 1, #rows do
        saved[rows[i].dyno] = {rank = i, name = rows[i].name}
    end

    for dynoId, dyno in pairs(GetDynos()) do
        if (hasAccess(plyId, dyno)) then
            local own = saved[DynoDatabase.getKey(dyno)]
            local entry = getEntry(plyId, dynoId, dyno, own and own.name)

            ranks[dynoId] = own and own.rank
            entry.saved = own ~= nil
            list[#list + 1] = entry
        end
    end

    ---@param a DynoLaptopEntry
    ---@param b DynoLaptopEntry
    ---@return boolean isBefore
    table.sort(list, function(a, b)
        local rankA, rankB = ranks[a.id] or math.huge, ranks[b.id] or math.huge
        if (rankA ~= rankB) then return rankA < rankB end

        return a.id < b.id
    end)

    return {ok = true, dynos = list}
end)

---@param plyId PlayerId
---@param data table @ {dynoId}
---@return DynoLaptopResult | DynoLaptopConnection result
Z.callback.register("zyke_dyno:laptop:Connect", function(plyId, data)
    local dynoId = type(data) == "table" and math.tointeger(tonumber(data.dynoId)) or nil
    local dyno, err = checkDyno(plyId, dynoId)
    if (not dyno or not dynoId) then return {ok = false, error = err} end

    local identifier = Z.getIdentifier(plyId)

    connections[plyId] = dynoId

    if (identifier) then DynoSaved.connect(identifier, DynoDatabase.getKey(dyno)) end

    return getConnection(plyId, dynoId, dyno)
end)

-- As the app opens: the dyno it was connected to, or the last one the character connected to and never
-- disconnected from, while they still may connect to it. Fails without an error when there is none
---@param plyId PlayerId
---@return DynoLaptopResult | DynoLaptopConnection result
Z.callback.register("zyke_dyno:laptop:Resume", function(plyId)
    ---@type integer?
    local dynoId = connections[plyId]

    if (not dynoId) then
        local identifier = Z.getIdentifier(plyId)
        local rows = identifier and DynoSaved.get(identifier) or {}

        for i = 1, #rows do
            if (rows[i].reopen) then dynoId = findDyno(rows[i].dyno) break end
        end
    end

    if (not dynoId) then return {ok = false} end

    local dyno, err = checkDyno(plyId, dynoId)
    if (not dyno) then connections[plyId] = nil return {ok = false, error = err} end

    connections[plyId] = dynoId

    return getConnection(plyId, dynoId, dyno)
end)

-- Leaves the dyno, which the app then no longer opens on; it stays in the list's saved dynos
---@param plyId PlayerId
---@return DynoLaptopResult result
Z.callback.register("zyke_dyno:laptop:Disconnect", function(plyId)
    local identifier = Z.getIdentifier(plyId)

    connections[plyId] = nil

    if (identifier) then DynoSaved.disconnect(identifier) end

    return {ok = true}
end)

-- Takes a dyno off the player's saved dynos, and the name they gave it with it
---@param plyId PlayerId
---@param data table @ {dynoId}
---@return DynoLaptopResult result
Z.callback.register("zyke_dyno:laptop:Forget", function(plyId, data)
    local dyno = type(data) == "table" and GetDynos()[math.tointeger(tonumber(data.dynoId)) or 0]
    if (not dyno) then return {ok = false, error = "laptop:error:noDyno"} end

    local identifier = Z.getIdentifier(plyId)
    if (not identifier) then return {ok = false, error = "laptop:error:unavailable"} end

    DynoSaved.forget(identifier, DynoDatabase.getKey(dyno))

    return {ok = true}
end)

-- Names the connected dyno for this character only. Other players, the screen and the sheet keep its own name
---@param plyId PlayerId
---@param data table @ {name}
---@return DynoLaptopResult | DynoLaptopConnection result
Z.callback.register("zyke_dyno:laptop:Rename", function(plyId, data)
    local dynoId, dyno, err = getConnected(plyId)
    if (not dynoId or not dyno) then return {ok = false, error = err} end

    local name, valid = readName(type(data) == "table" and data.name)
    if (not valid) then return {ok = false, error = "laptop:error:badName"} end

    local identifier = Z.getIdentifier(plyId)
    if (not identifier) then return {ok = false, error = "laptop:error:unavailable"} end

    DynoSaved.rename(identifier, DynoDatabase.getKey(dyno), name)

    return getConnection(plyId, dynoId, dyno)
end)

-- The connected dyno and its last result sheet, the same summary its screen shows
---@param plyId PlayerId
---@return DynoLaptopResult | DynoLaptopConnection result
Z.callback.register("zyke_dyno:laptop:GetStatus", function(plyId)
    local dynoId, dyno, err = getConnected(plyId)
    if (not dynoId or not dyno) then return {ok = false, error = err} end

    return getConnection(plyId, dynoId, dyno)
end)

---@param plyId PlayerId
---@return {ok: boolean, error?: string, runs?: DynoSheet[]} result
Z.callback.register("zyke_dyno:laptop:GetHistory", function(plyId)
    local dynoId, dyno, err = getConnected(plyId)
    if (not dynoId or not dyno) then return {ok = false, error = err} end

    return {ok = true, runs = DynoDatabase.getDynoRuns(DynoDatabase.getKey(dyno), historyLimit)}
end)

-- Every saved run of one car, for a car that ran on the connected dyno, so the app can't look up any plate
---@param plyId PlayerId
---@param data table @ {plate}
---@return {ok: boolean, error?: string, plate?: string, runs?: DynoSheet[]} result
Z.callback.register("zyke_dyno:laptop:GetPlateHistory", function(plyId, data)
    local dynoId, dyno, err = getConnected(plyId)
    if (not dynoId or not dyno) then return {ok = false, error = err} end

    local plate = type(data) == "table" and type(data.plate) == "string" and TrimPlate(data.plate:sub(1, 16))
    if (not plate or not DynoDatabase.hasRunOn(DynoDatabase.getKey(dyno), plate)) then return {ok = false, error = "laptop:error:unavailable"} end

    return {ok = true, plate = plate, runs = DynoDatabase.getRuns(plate, historyLimit)}
end)

AddEventHandler("playerDropped", function()
    connections[source] = nil
end)