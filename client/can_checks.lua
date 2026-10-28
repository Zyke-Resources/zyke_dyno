-- Editable local gate for starting a run; the server checks again in server/can_checks.lua. Return false and a
-- locale key to say why, which shows in the panel on the dyno

---@param dynoId integer
---@param vehicle integer
---@return boolean allowed
---@return string? reason
function CanRunDyno(dynoId, vehicle)
    return true
end