-- Each car's run history by plate, and each dyno's for the laptop app. The table is made as the resource starts

DynoDatabase = {}

local settings = Config.Settings.dyno

local createTable = [[
CREATE TABLE IF NOT EXISTS `zyke_dyno_runs` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `plate` varchar(16) NOT NULL,
  `dyno` varchar(32) DEFAULT NULL,
  `model` varchar(32) NOT NULL,
  `label` varchar(64) DEFAULT NULL,
  `drive` varchar(3) NOT NULL,
  `engine_kw` double NOT NULL,
  `wheel_kw` double NOT NULL,
  `wheel_nm` double NOT NULL,
  `power_rpm` int(11) NOT NULL,
  `torque_rpm` int(11) NOT NULL,
  `curve` longtext NOT NULL,
  `driver` varchar(100) DEFAULT NULL,
  `created` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `plate` (`plate`),
  KEY `dyno` (`dyno`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]

-- For tables made before runs kept their dyno
local addDynoColumn = "ALTER TABLE `zyke_dyno_runs` ADD COLUMN `dyno` varchar(32) DEFAULT NULL AFTER `plate`, ADD KEY `dyno` (`dyno`, `id`)"
local hasDynoColumn = "SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = 'zyke_dyno_runs' AND `COLUMN_NAME` = 'dyno'"

local ready = false

---@param row table @ Row of zyke_dyno_runs
---@return DynoSheet sheet
local function fromRow(row)
    return {
        rowId = row.id,
        plate = row.plate,
        model = row.model,
        label = row.label,
        drive = row.drive,
        engineKw = row.engine_kw,
        wheelKw = row.wheel_kw,
        wheelNm = row.wheel_nm,
        powerRpm = row.power_rpm,
        torqueRpm = row.torque_rpm,
        loss = row.engine_kw > 0 and 1.0 - row.wheel_kw / row.engine_kw or nil,
        curve = json.decode(row.curve),
        date = row.date,
    }
end

-- Dyno ids follow the order dynos are stood in, so the history keeps each by its spot instead
---@param dyno ZykeDyno
---@return string dynoKey
function DynoDatabase.getKey(dyno)
    return ("%.1f,%.1f,%.1f"):format(dyno.coords.x, dyno.coords.y, dyno.coords.z)
end

local function waitReady()
    while (not ready) do Wait(100) end
end

---@param rows table[] @ Rows of zyke_dyno_runs
---@return DynoSheet[] sheets
local function fromRows(rows)
    local sheets = {}

    for i = 1, #rows do
        sheets[i] = fromRow(rows[i])
    end

    return sheets
end

---@param sheet DynoSheet
function DynoDatabase.save(sheet)
    waitReady()

    local dyno = sheet.dynoId and GetDynos()[sheet.dynoId]

    MySQL.insert.await("INSERT INTO `zyke_dyno_runs` (`plate`, `dyno`, `model`, `label`, `drive`, `engine_kw`, `wheel_kw`, `wheel_nm`, `power_rpm`, `torque_rpm`, `curve`, `driver`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", {
        sheet.plate, dyno and DynoDatabase.getKey(dyno), sheet.model, sheet.label, sheet.drive, sheet.engineKw, sheet.wheelKw, sheet.wheelNm, sheet.powerRpm, sheet.torqueRpm, json.encode(sheet.curve), Z.getIdentifier(sheet.driver),
    })

    local keep = settings.historyPerPlate
    if (keep <= 0) then return end

    -- The first run stays, since it is the car's stock sheet that later runs are laid over
    MySQL.update.await([[
        DELETE FROM `zyke_dyno_runs` WHERE `plate` = ? AND `id` NOT IN (
            SELECT `id` FROM (
                SELECT `id` FROM `zyke_dyno_runs` WHERE `plate` = ? ORDER BY `id` DESC LIMIT ?
            ) AS `newest`
        ) AND `id` <> (SELECT `id` FROM (SELECT MIN(`id`) AS `id` FROM `zyke_dyno_runs` WHERE `plate` = ?) AS `first`)
    ]], {sheet.plate, sheet.plate, keep, sheet.plate})
end

---@param plate string
---@param limit? integer
---@return DynoSheet[] sheets @ Newest first
function DynoDatabase.getRuns(plate, limit)
    waitReady()

    return fromRows(MySQL.query.await("SELECT `id`, `plate`, `model`, `label`, `drive`, `engine_kw`, `wheel_kw`, `wheel_nm`, `power_rpm`, `torque_rpm`, `curve`, UNIX_TIMESTAMP(`created`) AS `date` FROM `zyke_dyno_runs` WHERE `plate` = ? ORDER BY `id` DESC LIMIT ?", {plate, math.floor(tonumber(limit) or 10)}) or {})
end

-- The runs saved on one dyno, by its key from DynoDatabase.getKey
---@param dynoKey string
---@param limit integer
---@return DynoSheet[] sheets @ Newest first
function DynoDatabase.getDynoRuns(dynoKey, limit)
    waitReady()

    return fromRows(MySQL.query.await("SELECT `id`, `plate`, `model`, `label`, `drive`, `engine_kw`, `wheel_kw`, `wheel_nm`, `power_rpm`, `torque_rpm`, `curve`, UNIX_TIMESTAMP(`created`) AS `date` FROM `zyke_dyno_runs` WHERE `dyno` = ? ORDER BY `id` DESC LIMIT ?", {dynoKey, limit}) or {})
end

---@param dynoKey string
---@param plate string
---@return boolean ranThere
function DynoDatabase.hasRunOn(dynoKey, plate)
    waitReady()

    return MySQL.scalar.await("SELECT 1 FROM `zyke_dyno_runs` WHERE `dyno` = ? AND `plate` = ? LIMIT 1", {dynoKey, plate}) ~= nil
end

---@param plate string
---@return DynoSheet? sheet
function DynoDatabase.getLast(plate)
    return DynoDatabase.getRuns(plate, 1)[1]
end

-- The car's last run and its first, which a new run is drawn over. The first is left out while it is the last
---@param plate string
---@return {previous?: DynoSheet, first?: DynoSheet} compare
function DynoDatabase.getCompare(plate)
    waitReady()

    local previous = DynoDatabase.getLast(plate)
    local first = MySQL.single.await("SELECT `id`, `plate`, `model`, `label`, `drive`, `engine_kw`, `wheel_kw`, `wheel_nm`, `power_rpm`, `torque_rpm`, `curve`, UNIX_TIMESTAMP(`created`) AS `date` FROM `zyke_dyno_runs` WHERE `plate` = ? ORDER BY `id` ASC LIMIT 1", {plate})
    local firstSheet = first and fromRow(first)

    return {previous = previous, first = firstSheet and previous and firstSheet.rowId ~= previous.rowId and firstSheet or nil}
end

CreateThread(function()
    MySQL.query.await(createTable)

    if (MySQL.scalar.await(hasDynoColumn) == 0) then MySQL.query.await(addDynoColumn) end

    ready = true
end)