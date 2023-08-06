local RefundSavePath = ModPath .. "crash_save_cashback.json"
local CrashlogPath = Application:nice_path(os.getenv("LOCALAPPDATA") .. '/PAYDAY 2/', true) .. 'crashlog.txt'

local function Log(...)
    log("[REFUND_CRASH]", ...)
end

local function LoadSave()
    local file = io.open(RefundSavePath, "r")
    local save = nil
    if file then
        Log("Can read save, decoding it")
        save = json.decode(file:read("*all"))
        file:close()
    end

    -- if file is failed to open or file is empty
    if save == nil then
        Log("Save is empty or I can't open it")
        save = {
            PreviousCrashHash = '',
            IsJobActive = false,
            OffshoreMoneySpend = nil,
        }
    end

    return save
end

local function CreateObserverTable(table, callback)
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

local function SaveJson(table)
    local Save = io.open(RefundSavePath, "w+")
    if Save then
        Save:write(json.encode(table))
        Save:close()
    end
end

local RefundStatus = CreateObserverTable(LoadSave(), function(table, ...)
    Log("Refund status changed, saving file")
    SaveJson(table)
end)

local function getHashOfCrash()
    if io.file_is_readable(CrashlogPath) then
        return file.FileHash(CrashlogPath)
    else
        return nil
    end
end

local function onWillingfulContractTermination()
    Log("Player has terminated contract willingfully. Reset cashbacks status")
    RefundStatus.OffshoreMoneySpend = nil
    RefundStatus.IsJobActive = false
end

local function addOffshore(money)
    Log("Current offshore: " .. tostring(managers.money:offshore()))
    managers.money:add_to_offshore(RefundStatus.OffshoreMoneySpend)
    Log("Returned: " .. RefundStatus.OffshoreMoneySpend .. "$ offshore money from crash")
    Log("After offshore" .. tostring(managers.money:offshore()))
end

-- HOOKS
Hooks:PostHook(MoneyManager, "on_buy_premium_contract", "REFUND_CRASH_ON_CONTRACT_BUY",
    function(self, job_id, difficulty_id)
        local offshoreSpend = self:get_cost_of_premium_contract(job_id, difficulty_id)
        RefundStatus.OffshoreMoneySpend = offshoreSpend
        RefundStatus.IsJobActive = true
        Log(tostring(offshoreSpend) .. "$ offshore was spend on contract " .. job_id)
    end
)

Hooks:PreHook(MenuCallbackHandler, "load_start_menu_lobby", "REFUND_CRASH_ABORT", function()
    onWillingfulContractTermination()
end)

Hooks:PreHook(MenuCallbackHandler, "_dialog_end_game_yes", "REFUND_CRASH_END_GAME_YES", function()
    onWillingfulContractTermination()
end)

Hooks:PreHook(MenuManager, "on_leave_lobby", "REFUND_CRASH_ON_LEAVE_LOBBY", function()
    onWillingfulContractTermination()
end)

Hooks:PostHook(MoneyManager, "load", "REFUND_CRASH_SETUP", function()    
    --- START UP 
    local currentHash = getHashOfCrash()
    Log("hash: " .. currentHash)

    if currentHash == nil then
        Log("Can't get hash of crash. Crash file doesn't exists or isn't readable")
        return
    end

    if currentHash == RefundStatus.PreviousCrashHash then
        Log("Identical hash, no new crash")
        return
    end


    if not (RefundStatus.IsJobActive or false) then 
        Log("Job wasnt active at crash")
        return
    end

    if not (RefundStatus.OffshoreMoneySpend or false) then 
        Log("Spent offshore is empty")
        return
    end

    addOffshore(RefundStatus.OffshoreMoneySpend)
    RefundStatus.PreviousCrashHash = currentHash
end)
