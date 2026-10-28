-- Dynos placed with "/dynos", saved so they stand again after a restart, in a table made as the resource starts.
-- Dynos from shared/dynos.lua and other resources are never saved here
DynoPlaced = {}

local createTable = [[
CREATE TABLE IF NOT EXISTS `zyke_dyno_dynos` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `x` double NOT NULL,
  `y` double NOT NULL,
  `z` double NOT NULL,
  `heading` double NOT NULL,
  `kind` varchar(8) NOT NULL DEFAULT 'car',
  `screen` varchar(5) NOT NULL DEFAULT 'left',
  `creator` varchar(100) DEFAULT NULL,
  `created` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]

-- Row ids by dyno id
---@type table<integer, integer>
local rows = {}
-- Set once the saved dynos stand and their rows are known
local ready = false

---@param side string
---@return DynoScreenSide side
local function readSide(side)
    return (side == "right" or side == "none") and side or "left"
end

---@param kind string
---@return DynoKind kind
local function readKind(kind)
    return DynoGeometry.kinds[kind] and kind or "car"
end

-- Saves a dyno placed with the admin tool
---@param dynoId integer
---@param side DynoScreenSide
---@param plyId PlayerId
function DynoPlaced.save(dynoId, side, plyId)
    while (not ready) do Wait(100) end

    -- Placing on the spot of a dyno of shared/dynos.lua gives that dyno back, which is not saved
    local dyno = GetDynos()[dynoId]
    if (not dyno or not dyno.placed or rows[dynoId]) then return end

    local rowId = MySQL.insert.await("INSERT INTO `zyke_dyno_dynos` (`x`, `y`, `z`, `heading`, `kind`, `screen`, `creator`) VALUES (?, ?, ?, ?, ?, ?, ?)", {dyno.coords.x, dyno.coords.y, dyno.coords.z, dyno.heading, dyno.kind, side, Z.getIdentifier(plyId)})
    if (rowId) then rows[dynoId] = rowId end
end

-- Deletes the row of a placed dyno that was taken away
---@param dynoId integer
function DynoPlaced.remove(dynoId)
    while (not ready) do Wait(100) end

    local rowId = rows[dynoId]
    if (not rowId) then return end

    rows[dynoId] = nil

    MySQL.update.await("DELETE FROM `zyke_dyno_dynos` WHERE `id` = ?", {rowId})
end

CreateThread(function()
    MySQL.query.await(createTable)

    -- Tables made before bike dynos hold car dynos only
    if (not Z.hasDatabaseColumn("zyke_dyno_dynos", "kind")) then MySQL.query.await("ALTER TABLE `zyke_dyno_dynos` ADD COLUMN `kind` varchar(8) NOT NULL DEFAULT 'car' AFTER `heading`") end

    local saved = MySQL.query.await("SELECT `id`, `x`, `y`, `z`, `heading`, `kind`, `screen` FROM `zyke_dyno_dynos`") or {}

    for _, row in ipairs(saved) do
        local kind = readKind(row.kind)
        local options = {coords = vec3(row.x, row.y, row.z), heading = row.heading, kind = kind, screen = DynoGeometry.getPlacedScreen(kind, readSide(row.screen))}
        local dynoId = CreateDyno(options, ResName, true)

        if (not dynoId) then
            Z.debug("Saved dyno could not be stood", row.id)
        elseif (rows[dynoId]) then
            -- Two rows for one spot would bring the dyno back after it was taken away
            MySQL.update.await("DELETE FROM `zyke_dyno_dynos` WHERE `id` = ?", {row.id})
        else
            rows[dynoId] = row.id
        end
    end

    ready = true
end)