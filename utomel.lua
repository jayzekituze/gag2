getgenv().MailboxConfig = {
    MAIL_USERNAME = { "kram_titanic" },
    MAIL_ITEM_NAME = { 
    ["Super Sprinkler"] = 10,           
    ["Super Watering Can"] = 10,         
    ["Uncommon Sprinkler"] = 50, 
    ["Ladder Crate"] = 50},
    MAIL_NOTE = "",
    SEND_INTERVAL = 30, -- auto send every 30 seconds
    AUTO_SEND = true,
}

local C = getgenv().MailboxConfig or {}
local RS = game:GetService("ReplicatedStorage")
local Net = require(RS:WaitForChild("SharedModules"):WaitForChild("Networking"))
local PS = require(RS:WaitForChild("ClientModules"):WaitForChild("PlayerStateClient"))

local STACK = {
    Sprinklers = 1, WateringCans = 1, Mushrooms = 1, Gnomes = 1, Raccoons = 1, Crates = 1,
    SeedPacks = 1, Trowels = 1, Props = 1, Seeds = 1, HarvestedFruits = 1, Flashbangs = 1, EmptyPots = 1,
}

local function getInv()
    local ok, r = pcall(function() return PS:WaitForLocalReplica(5) end)
    return ok and r and r.Data and type(r.Data.Inventory) == "table" and r.Data.Inventory
end

local function buildBatch(inv, items)
    local out, max = {}, 20
    for name, amt in items do
        if #out >= max then break end
        local want = math.max(1, math.floor(tonumber(amt) or 1))
        if type(inv.Pets) == "table" then
            for key, p in inv.Pets do
                if want <= 0 or #out >= max then break end
                if type(p) == "table" and p.Id and not p.Equipped and tostring(p.Name) == name then
                    out[#out + 1] = { Category = "Pets", ItemKey = key, Count = 1 }
                    want -= 1
                end
            end
        end
        if want > 0 then
            for cat in STACK do
                local t = inv[cat]
                if type(t) == "table" and type(t[name]) == "number" and t[name] > 0 then
                    out[#out + 1] = { Category = cat, ItemKey = name, Count = math.min(want, t[name]) }
                    break
                end
            end
        end
    end
    return out
end

getgenv().mailboxSendOnce = function()
    local users, items = C.MAIL_USERNAME or {}, C.MAIL_ITEM_NAME or {}
    if #users == 0 or not next(items) then return warn("[Mailbox] empty config") end
    local inv = getInv()
    if not inv then return warn("[Mailbox] no inventory") end
    local batch = buildBatch(inv, items)
    if #batch == 0 then return warn("[Mailbox] nothing to send") end
    local target = tostring(users[math.random(#users)])
    local ok, uid, err = pcall(function() return Net.Mailbox.LookupPlayer:Fire(target) end)
    if not ok or type(uid) ~= "number" or uid <= 0 then return warn("[Mailbox] lookup:", err) end
    ok, success, msg = pcall(function() return Net.Mailbox.SendBatch:Fire(uid, batch, C.MAIL_NOTE or "") end)
    print(success and "[Mailbox] sent to " .. target or "[Mailbox] fail:", msg or success)
    return success == true
end

if C.AUTO_SEND ~= false then
    task.spawn(function()
        while true do
            pcall(getgenv().mailboxSendOnce)
            task.wait(tonumber(C.SEND_INTERVAL) or 10)
        end
    end)
else
    getgenv().mailboxSendOnce()
end
