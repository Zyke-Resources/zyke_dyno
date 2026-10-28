-- Each character's saved dynos in the laptop app, kept by DynoDatabase.getKey since dyno ids change when dynos are
-- placed or the server restarts

if (not Config.Settings.dyno.laptop.enabled) then return end

DynoSaved = {}

-- Unnamed dynos kept per character, named ones stay until forgotten
local savedLimit = 10
-- Characters in a name at most, as the column holds
DynoSaved.nameLength = 32

local createTable = [[
CREATE TABLE IF NOT EXISTS `zyke_dyno_saved` (
  `identifier` varchar(100) NOT NULL,
  `dyno` varchar(32) NOT NULL,
  `name` varchar(32) DEFAULT NULL,
  `reopen` tinyint(1) NOT NULL DEFAULT 0,
  `used` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`identifier`, `dyno`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]

local ready = false

---@class DynoSavedRow
---@field dyno string @ Key from DynoDatabase.getKey
---@field name? string
---@field reopen boolean @ The app opens on this dyno

local function waitReady()
    while (not ready) do Wait(100) end
end

-- The character's saved dynos, the most recently connected to first
---@param identifier string
---@return DynoSavedRow[] rows
function DynoSaved.get(identifier)
    waitReady()

    local rows = MySQL.query.await("SELECT `dyno`, `name`, `reopen` FROM `zyke_dyno_saved` WHERE `identifier` = ? ORDER BY `used` DESC", {identifier}) or {}

    for i = 1, #rows do
        rows[i].reopen = rows[i].reopen == 1 or rows[i].reopen == true
    end

    return rows
end

---@param identifier string
---@param dynoKey string
---@return string? name
function DynoSaved.getName(identifier, dynoKey)
    waitReady()

    return MySQL.scalar.await("SELECT `name` FROM `zyke_dyno_saved` WHERE `identifier` = ? AND `dyno` = ?", {identifier, dynoKey})
end

-- Saves the dyno as the one the app opens on, and forgets the oldest unnamed dynos over the limit
---@param identifier string
---@param dynoKey string
function DynoSaved.connect(identifier, dynoKey)
    waitReady()

    MySQL.query.await("INSERT INTO `zyke_dyno_saved` (`identifier`, `dyno`, `reopen`) VALUES (?, ?, 1) ON DUPLICATE KEY UPDATE `reopen` = 1, `used` = current_timestamp()", {identifier, dynoKey})
    MySQL.update.await("UPDATE `zyke_dyno_saved` SET `reopen` = 0 WHERE `identifier` = ? AND `dyno` <> ?", {identifier, dynoKey})
    MySQL.update.await([[
        DELETE FROM `zyke_dyno_saved` WHERE `identifier` = ? AND `name` IS NULL AND `dyno` NOT IN (
            SELECT `dyno` FROM (
                SELECT `dyno` FROM `zyke_dyno_saved` WHERE `identifier` = ? AND `name` IS NULL ORDER BY `used` DESC LIMIT ?
            ) AS `newest`
        )
    ]], {identifier, identifier, savedLimit})
end

-- The app opens on the list from now on, until the character connects again
---@param identifier string
function DynoSaved.disconnect(identifier)
    waitReady()

    MySQL.update.await("UPDATE `zyke_dyno_saved` SET `reopen` = 0 WHERE `identifier` = ?", {identifier})
end

---@param identifier string
---@param dynoKey string
function DynoSaved.forget(identifier, dynoKey)
    waitReady()

    MySQL.update.await("DELETE FROM `zyke_dyno_saved` WHERE `identifier` = ? AND `dyno` = ?", {identifier, dynoKey})
end

---@param identifier string
---@param dynoKey string
---@param name? string @ nil gives the dyno its own name back
function DynoSaved.rename(identifier, dynoKey, name)
    waitReady()

    MySQL.query.await("INSERT INTO `zyke_dyno_saved` (`identifier`, `dyno`, `name`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `name` = VALUES(`name`)", {identifier, dynoKey, name})
end

CreateThread(function()
    MySQL.query.await(createTable)

    ready = true
end)