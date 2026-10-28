-- The Dyno app for zyke_laptop, added only while that resource runs, with its page in web/laptop/. The server
-- checks every request again, see server/laptop.lua

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
local registered = false

-- Read by client/run.lua, which plays the run on the connected dyno however far away it is, for its live graph
DynoLaptop = {}

---@return integer? dynoId
function DynoLaptop.getConnected()
    return connectedId
end

---@return boolean mayUse @ The player's job may connect to at least one dyno
local function mayUseAny()
    for _, dyno in pairs(GetDynos()) do
        local jobs = dyno.jobs or settings.jobs
        if (not jobs or Z.isJob(jobs)) then return true end
    end

    return false
end

-- RegisterApp only adds the app on this client, so each client checks its own job. The server checks it again on
-- every request
---@param force? boolean @ Registers again even when nothing changed, as the laptop forgets apps when it restarts
local function syncApp(force)
    if (GetResourceState("zyke_laptop") ~= "started") then return end

    local wanted = mayUseAny()
    if (wanted == registered and not force) then return end

    registered = wanted

    if (not wanted) then return exports.zyke_laptop:UnregisterApp(appId) end

    exports.zyke_laptop:RegisterApp({
        id = appId,
        label = T("laptop:appName"),
        icon = "gauge",
        category = "utilities",
        description = T("laptop:appDescription"),
        ui = "web/laptop/index.html",
        window = {width = 1000, height = 660, minWidth = 680, minHeight = 480, resizable = true},
    })
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

-- Called without arguments, as anything in force would register the app again on every change
OnDynosChange(function()
    syncApp()
end)

AddEventHandler("zyke_lib:OnCharacterSelect", function()
    syncApp()
end)

RegisterNetEvent("zyke_lib:OnJobUpdate", function()
    syncApp()
end)

-- Fired when zyke_laptop starts, after this resource or again after it restarts. The job is read once zyke_lib's
-- loader is done
AddEventHandler("zyke_laptop:Ready", function()
    while (not HasLoaderFinished) do Wait(10) end

    syncApp(true)
end)

CreateThread(function()
    while (not HasLoaderFinished) do Wait(10) end

    syncApp(true)
end)