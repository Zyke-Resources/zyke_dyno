-- Editable gate for starting a run; return false and a locale key to refuse with a notification. Other
-- resources refuse runs through the RegisterRunCheck export instead, see the documentation

---@param plyId PlayerId
---@param dynoId integer
---@param vehicle integer
---@return boolean allowed
---@return string? reason
function CanRunDyno(plyId, dynoId, vehicle)
    return true
end