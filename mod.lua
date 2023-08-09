------------
--- UTIL ---
------------
local Util = {}

--- Creates a proxy table with an observer pattern for tracking changes and invoking a callback.
--- @param table table The table to be observed.
--- @param callback function The callback function to be invoked on changes.
--- @return table table A proxy table with the observer pattern.
function Util.CreateObserverTable(table, callback)
    local observer = {}
    local mt = {
        __index = table,
        __newindex = function(proxyTable, key, value)
            rawset(table, key, value)
            callback(table, key, value) -- Call the callback function with key and value
        end
    }
    setmetatable(observer, mt)
    return observer
end

--- Logs a formatted message to the game's log.
--- @param ... any Variable number of arguments to be logged.
function Util.Log(...)
    local args = { ... }
    local first = table.remove(args, 1)
    log("[REFUND CRASH]: " .. tostring(first), unpack(args))
end

--- Logs the contents of a table.
--- @param table table The table to be logged.
function Util.LogTable(table)
    Util.Log(tostring(table))
    for index, value in pairs(table) do 
      Util.Log('    ' .. tostring(index) .. ' : ' .. tostring(value))
    end
end

--- Creates a new table by merging values from two tables. Values from table2 are added to table1 if they don't already exist.
--- @param table1 table The first table.
--- @param table2 table The second table.
--- @return table table A merged table.
function Util.createMergedTable(table1, table2)
    local mergedTable = {}

    -- Copy values from table1 to mergedTable
    for key, value in pairs(table1) do
        mergedTable[key] = value
    end

    -- Merge values from table2, only if they don't exist in table1
    for key, value in pairs(table2) do
        if mergedTable[key] == nil then
            mergedTable[key] = value
        end
    end

    return mergedTable
end
  
--- Adds offshore money to the player's account and logs the action.
--- @param money number The amount of offshore money to be added.
function Util.addOffshore(money)
    Util.Log("Current offshore: " .. tostring(managers.money:offshore()))
    managers.money:add_to_offshore(RefundMod.Status.OffshoreMoneySpend)
    Util.Log("Returned: " .. RefundMod.Status.OffshoreMoneySpend .. "$ offshore money from crash")
    Util.Log("After offshore" .. tostring(managers.money:offshore()))
end

Util.Log("Hello everynya!")
----------------
-- REFUND MOD --
----------------
_G.RefundMod = _G.RefundMod or {}

-- Path constants for RefundMod.

RefundMod.ModPath = ModPath -- Cache of ModPath
RefundMod.SavePath = ModPath .. "refund_on_crash_save.json"
RefundMod.CrashlogPath = Application:nice_path(os.getenv("LOCALAPPDATA") .. '/PAYDAY 2/', true) .. 'crashlog.txt'
RefundMod.MenuPath = ModPath .. "menu.json"
RefundMod._Status = {}

--- Saves the RefundMod status to a file.
function RefundMod:Save()
    local Save = io.open(self.SavePath, "w+")
    if Save then
        Util.Log("Save()")
        Util.LogTable(self._Status)
        Save:write(json.encode(self._Status))
        Save:close()
    end
end

--- Loads the RefundMod status from a file, merging it with default values.
--- @return table table An observer table containing the loaded status.
function RefundMod:Load()
    local file = io.open(self.SavePath, "r")
    local defaultStatus = {
        PreviousCrashHash = '',
        IsJobActive = false,
        OffshoreMoneySpend = nil,
        ShowMessage = true,
    }
    local status = nil
    if file then
        Util.Log("Can read save, decoding it")
        status = json.decode(file:read("*all"))
        if next(status) == nil then
            status = nil
        end
        file:close()
    end

    if status == nil then
        Util.Log("Save is empty or I can't open it")
        status = defaultStatus
    else
        status = Util.createMergedTable(status, defaultStatus)
    end

    Util.Log("Load()")
    Util.LogTable(status)
    self._Status = status
    return Util.CreateObserverTable(status, function (realTable)
        Util.Log("State has been changed, saving file")
        self:Save()
    end)
end
    
--- Retrieves the hash of the crash log file, if available.
--- @return string|nil hash The hash of the crash log file, or nil if unavailable.
function RefundMod:getHashOfCrash()
    if io.file_is_readable(self.CrashlogPath) then
        return file.FileHash(self.CrashlogPath)
    else
        return nil
    end
end

--- Refunds offshore money to the player's account and updates status.
--- @param new_hash string The hash of the crash log file triggering the refund.
function RefundMod:refund(new_hash)
    Util.addOffshore(self.Status.OffshoreMoneySpend)
    self.Status.PreviousCrashHash = new_hash

    if self.Status.ShowMessage then
        QuickMenu:new("Refund offshore on crash", "Refunded " .. self.Status.OffshoreMoneySpend .. "$ offshore to your account", {}):Show()
    end
end

--- Resets the RefundMod status upon player's willful contract termination.
function RefundMod:onWillfulContractTermination()
    Util.Log("Player has terminated contract willfully. Reset cashbacks status")
    self.Status.OffshoreMoneySpend = nil
    self.Status.IsJobActive = false
end

RefundMod.Status = RefundMod:Load()
RefundMod:Save()

-------------
--- HOOKS ---
-------------
Hooks:PostHook(MoneyManager, "on_buy_premium_contract", "REFUND_CRASH_ON_CONTRACT_BUY",
    function(self, job_id, difficulty_id)
        local offshoreSpend = self:get_cost_of_premium_contract(job_id, difficulty_id)
        RefundMod.Status.OffshoreMoneySpend = offshoreSpend
        RefundMod.Status.IsJobActive = true
        Util.Log(tostring(offshoreSpend) .. "$ offshore was spend on contract " .. job_id)
    end
)

Hooks:PreHook(MenuCallbackHandler, "load_start_menu_lobby", "REFUND_CRASH_ABORT", function()
    RefundMod:onWillfulContractTermination()
end)

Hooks:PreHook(MenuCallbackHandler, "_dialog_end_game_yes", "REFUND_CRASH_END_GAME_YES", function()
    RefundMod:onWillfulContractTermination()
end)

Hooks:PreHook(MenuManager, "on_leave_lobby", "REFUND_CRASH_ON_LEAVE_LOBBY", function()
    RefundMod:onWillfulContractTermination()
end)

MenuCallbackHandler.showCrashRefundMessage_onChange = function (self, item)
    local bool = item:value() == 'on' 
    RefundMod.Status.ShowMessage = bool
end

MenuHelper:LoadFromJsonFile(RefundMod.MenuPath, RefundMod, RefundMod.Status)

Hooks:PostHook(MoneyManager, "load", "REFUND_CRASH_SETUP", function()     
    local currentHash = RefundMod:getHashOfCrash()
    Util.Log("hash: " .. currentHash)

    if currentHash == nil then
        Util.Log("Can't get hash of crash. Crash file doesn't exists or isn't readable")
        return
    end

    if currentHash == RefundMod.Status.PreviousCrashHash then
        Util.Log("Identical hash, no new crash")
        return
    end


    if not (RefundMod.Status.IsJobActive or false) then 
        Util.Log("Job wasnt active at crash")
        return
    end

    if not (RefundMod.Status.OffshoreMoneySpend or false) then 
        Util.Log("Spent offshore is empty")
        return
    end

    RefundMod:refund(currentHash)
end)
