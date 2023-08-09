------------
--- UTIL ---
------------
local Util = {}

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

function Util.Log(...)
    local args = { ... }
    local first = table.remove(args, 1)
    log("[REFUND CRASH]: " .. tostring(first), unpack(args))
end

function Util.LogTable(table)
    Util.Log(tostring(table))
    for index, value in pairs(table) do 
      Util.Log('    ' .. tostring(index) .. ' : ' .. tostring(value))
    end
end
  
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
RefundMod.ModPath = ModPath -- cache it
RefundMod.SavePath = ModPath .. "refund_on_crash_save.json"
RefundMod.CrashlogPath = Application:nice_path(os.getenv("LOCALAPPDATA") .. '/PAYDAY 2/', true) .. 'crashlog.txt'
RefundMod.MenuPath = ModPath .. "menu.json"
RefundMod._Status = {}

function RefundMod:Save()
    local Save = io.open(self.SavePath, "w+")
    if Save then
        Util.Log("Save()")
        Util.LogTable(self._Status)
        Save:write(json.encode(self._Status))
        Save:close()
    end
end

function RefundMod:Load()
    local file = io.open(self.SavePath, "r")
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
        status = {
            PreviousCrashHash = '',
            IsJobActive = false,
            OffshoreMoneySpend = nil,
            ShowMessage = true,
        }
    end

    Util.Log("Load()")
    Util.LogTable(status)
    self._Status = status
    return Util.CreateObserverTable(status, function (realTable)
        Util.Log("State has been changed, saving file")
        self:Save()
    end)
end
    
function RefundMod:getHashOfCrash()
    if io.file_is_readable(self.CrashlogPath) then
        return file.FileHash(self.CrashlogPath)
    else
        return nil
    end
end

function RefundMod:refund(new_hash)
    Util.addOffshore(self.Status.OffshoreMoneySpend)
    self.Status.PreviousCrashHash = new_hash

    if self.Status.ShowMessage then
        QuickMenu:new("Refund offshore on crash", "Refunded " .. self.Status.OffshoreMoneySpend .. "$ offshore to your account", {}):Show()
    end
end

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
    --- START UP 
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
