-- The "/dynos" command and the placing tool's requests. Each request checks the admin's permission and reach again

local admin = Config.Settings.dyno.admin
if (not admin or admin.enabled ~= true) then return end

-- Metres from the admin, the placing tool reaches 12
local placeReach = 15.0

---@param plyId PlayerId
Z.registerCommand(admin.command, function(plyId)
    if (plyId <= 0) then return end

    -- The server has no floor to read, so the admin's client finds it
    TriggerClientEvent("zyke_dyno:PlaceDyno", plyId)
end, T("command:dynos"), nil, {permission = admin.permission, errorMsg = "noPermission"})

-- A dyno standing in another would stand its props in the other's
---@param placed {coords: vector3, heading: number, kind: DynoKind}
---@return boolean overlapping
local function isOverlapping(placed)
    for _, dyno in pairs(GetDynos()) do
        if (DynoGeometry.doOverlap(dyno, placed)) then return true end
    end

    return false
end

-- The admin's client found the floor they aim at, the way the dyno is turned, the side of its screen and its kind
---@param plyId PlayerId
---@param coords vector3
---@param heading number
---@param side DynoScreenSide
---@param kind DynoKind
---@return integer? dynoId
---@return string? notification
Z.callback.register("zyke_dyno:AddDyno", function(plyId, coords, heading, side, kind)
    if (not Z.hasPermission(plyId, admin.permission)) then return nil, "noPermission" end
    if (type(coords) ~= "vector3" or type(heading) ~= "number" or heading ~= heading) then return nil, "reason:actionUnavailable" end
    if (side ~= "left" and side ~= "right" and side ~= "none") then return nil, "reason:actionUnavailable" end
    if (not DynoGeometry.kinds[kind]) then return nil, "reason:actionUnavailable" end

    local ped = GetPlayerPed(plyId)
    if (ped == 0 or #(GetEntityCoords(ped) - coords) > placeReach) then return nil, "reason:actionUnavailable" end

    local placed = {coords = coords, heading = heading % 360.0, kind = kind, screen = DynoGeometry.getPlacedScreen(kind, side)}
    if (isOverlapping(placed)) then return nil, "dynoOverlaps" end

    local dynoId = CreateDyno(placed, ResName, true)
    if (not dynoId) then return nil, "reason:actionUnavailable" end

    DynoPlaced.save(dynoId, side, plyId)

    return dynoId
end)

-- The placing tool takes away the dyno the admin aims at, one placed with it
---@param plyId PlayerId
---@param dynoId integer
---@return boolean removed
---@return string? notification
Z.callback.register("zyke_dyno:RemovePlacedDyno", function(plyId, dynoId)
    if (not Z.hasPermission(plyId, admin.permission)) then return false, "noPermission" end

    local dyno = GetDynos()[dynoId]
    if (not dyno or not dyno.placed) then return false, "reason:actionUnavailable" end

    local ped = GetPlayerPed(plyId)
    if (ped == 0 or #(GetEntityCoords(ped) - dyno.coords) > placeReach) then return false, "reason:actionUnavailable" end

    local removed = RemoveDyno(dynoId)
    if (removed) then DynoPlaced.remove(dynoId) end

    return removed
end)