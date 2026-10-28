-- A result sheet read from a printed item, open until it is closed or runs out

DynoSheet = {}

-- A sheet stays up this long unless it is closed first
local openMs = 90000

---@type DynoSheet?
local open

---@return boolean isOpen
function DynoSheet.isOpen()
    return open ~= nil
end

-- Closes the open sheet, as a new run of the player's own takes the screen
function DynoSheet.close()
    open = nil
end

---@param sheet DynoSheet
local function show(sheet)
    open = sheet

    DynoNui.showSheet(sheet)

    local items = {{label = T("control:close"), key = "BACKSPACE", hiddenKey = "RIGHTMOUSE", func = function()
        open = nil
    end}}

    Z.keybinds.show(items, {title = T("title:sheet"), detail = sheet.plate})

    local closeAt = GetGameTimer() + openMs
    while (open == sheet and GetGameTimer() < closeAt) do
        Z.keybinds.handle(items)

        Wait(0)
    end

    Z.keybinds.hide(items)

    if (open == sheet) then open = nil end
    if (not open) then DynoNui.showSheet(nil) end
end

---@param sheet DynoSheet
RegisterNetEvent("zyke_dyno:ShowSheet", function(sheet)
    show(sheet)
end)