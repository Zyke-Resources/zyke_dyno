-- The Dyno app's page in web/laptop/ and its live run. server/laptop.lua registers the app and checks every
-- request again

local settings = Config.Settings.dyno
if (not settings.laptop.enabled) then return end

local appId = "zyke_dyno"
local serverEndpoints = {"GetDynos", "Connect", "Resume", "Disconnect", "Forget", "Rename", "GetStatus", "GetHistory", "GetPlateHistory"}

local liveMs = 100
-- The page asks for the status every few seconds
local pageTimeoutMs = 12000

---@type integer? @ The dyno the server let the page connect to
local connectedId
local pageSeenAt = 0
local following = false

-- Read by client/run.lua, which plays the run on the connected dyno however far away it is, for its live graph
DynoLaptop = {}

---@return integer? dynoId
function DynoLaptop.getConnected()
    return connectedId
end

-- The live run without what the page already has: the overlay runs come once per run, and only the points
-- recorded since the last send
---@param live table
---@param sentRunId? string
---@param sentPoints integer
---@return table message
local function getLiveMessage(live, sentRunId, sentPoints)
    local isNew = live.runId ~= sentRunId or #live.points < sentPoints
    local from = isNew and 1 or sentPoints + 1
    local points = {}

    for i = from, #live.points do
        points[#points + 1] = live.points[i]
    end

    return {
        runId = live.runId,
        plate = live.plate,
        label = live.label,
        drive = live.drive,
        phase = live.phase,
        rpm = live.rpm,
        speed = live.speed,
        throttle = live.throttle,
        gear = live.gear,
        redline = live.redline,
        startRpm = live.startRpm,
        from = from,
        points = points,
        compare = isNew and live.compare or nil,
    }
end

-- Sends the connected dyno's live run to the page until it disconnects or closes
local function follow()
    if (following) then return end

    following = true

    CreateThread(function()
        local sentRunId, sentPoints = nil, 0

        while (connectedId and GetGameTimer() - pageSeenAt < pageTimeoutMs) do
            local live = DynoLive.get(connectedId)

            if (live) then
                exports.zyke_laptop:SendAppMessage(appId, {event = "Live", data = getLiveMessage(live, sentRunId, sentPoints)})

                sentRunId, sentPoints = live.runId, #live.points
            elseif (sentRunId) then
                exports.zyke_laptop:SendAppMessage(appId, {event = "LiveEnd", data = {runId = sentRunId}})

                sentRunId, sentPoints = nil, 0
            end

            Wait(liveMs)
        end

        following = false
    end)
end

-- Every word the page shows, by its full locale key
---@return table<string, string> strings
local function getStrings()
    local strings = {}

    for key, value in pairs(Translations) do
        if (type(value) == "string" and (key:find("^laptop:") or key:find("^nui:") or key:find("^unit:"))) then strings[key] = value end
    end

    return strings
end

---@param _ table
---@param cb fun(setup: table)
RegisterNUICallback("dyno:Setup", function(_, cb)
    cb({strings = getStrings(), units = settings.units})
end)

for i = 1, #serverEndpoints do
    local endpoint = serverEndpoints[i]

    ---@param data table
    ---@param cb fun(result: table)
    RegisterNUICallback("dyno:" .. endpoint, function(data, cb)
        pageSeenAt = GetGameTimer()

        local result = Z.callback.request("zyke_dyno:laptop:" .. endpoint, nil, data) or {ok = false, error = "laptop:error:unavailable"}

        -- The status is asked for every few seconds, so this follows the server's connection
        if (endpoint == "Connect" or endpoint == "Resume" or endpoint == "GetStatus" or endpoint == "Disconnect") then connectedId = result.ok and result.dyno and result.dyno.id or nil end
        if (connectedId) then follow() end

        cb(result)
    end)
end