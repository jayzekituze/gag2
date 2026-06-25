-- MailboxGUI.lua
-- Paste this into your executor.

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local cfg = {
    username = "",
    items    = {},
    note     = "",
    interval = 10,
}

local STACK = {
    Sprinklers=1, WateringCans=1, Mushrooms=1, Gnomes=1, Raccoons=1, Crates=1,
    SeedPacks=1, Trowels=1, Props=1, Seeds=1, HarvestedFruits=1, Flashbangs=1, EmptyPots=1,
}

local function getNet()
    return require(RS:WaitForChild("SharedModules"):WaitForChild("Networking"))
end
local function getPS()
    return require(RS:WaitForChild("ClientModules"):WaitForChild("PlayerStateClient"))
end
local function getInv()
    local PS = getPS()
    local ok, r = pcall(function() return PS:WaitForLocalReplica(5) end)
    return ok and r and r.Data and type(r.Data.Inventory) == "table" and r.Data.Inventory
end

local function buildBatch(inv, items)
    local out, max = {}, 20
    for _, entry in ipairs(items) do
        local name, amt = entry.name, entry.amount
        if #out >= max then break end
        local want = math.max(1, math.floor(tonumber(amt) or 1))
        if type(inv.Pets) == "table" then
            for key, p in pairs(inv.Pets) do
                if want <= 0 or #out >= max then break end
                if type(p) == "table" and p.Id and not p.Equipped and tostring(p.Name) == name then
                    out[#out+1] = { Category="Pets", ItemKey=key, Count=1 }
                    want -= 1
                end
            end
        end
        if want > 0 then
            for cat in pairs(STACK) do
                local t = inv[cat]
                if type(t) == "table" and type(t[name]) == "number" and t[name] > 0 then
                    out[#out+1] = { Category=cat, ItemKey=name, Count=math.min(want, t[name]) }
                    break
                end
            end
        end
    end
    return out
end

local function doSend(logFn)
    if cfg.username == "" then logFn("[Mailbox] No username set.") return false end
    if #cfg.items == 0 then logFn("[Mailbox] No items added.") return false end
    local inv = getInv()
    if not inv then logFn("[Mailbox] Could not read inventory.") return false end
    local batch = buildBatch(inv, cfg.items)
    if #batch == 0 then logFn("[Mailbox] Nothing found to send.") return false end
    local Net = getNet()
    local ok, uid = pcall(function() return Net.Mailbox.LookupPlayer:Fire(cfg.username) end)
    if not ok or type(uid) ~= "number" or uid <= 0 then
        logFn("[Mailbox] Player lookup failed.") return false
    end
    local ok2, success = pcall(function()
        return Net.Mailbox.SendBatch:Fire(uid, batch, cfg.note or "")
    end)
    if success == true then
        logFn("[Mailbox] Sent to " .. cfg.username .. " ✓")
        return true
    else
        logFn("[Mailbox] Send failed.")
        return false
    end
end

local function doClaim(logFn)
    local Net = getNet()
    local ok = pcall(function() return Net.Mailbox.ClaimAll:Fire() end)
    if ok then logFn("[Mailbox] Mail claimed ✓") else logFn("[Mailbox] Claim failed.") end
end

-- ─── GUI ─────────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "MailboxGUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.new(0, 370, 0, 580)
frame.Position = UDim2.new(0.5, -185, 0.5, -290)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 38)
titleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
titleBar.BorderSizePixel = 0
titleBar.Parent = frame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local titleFix = Instance.new("Frame")
titleFix.Size = UDim2.new(1, 0, 0, 10)
titleFix.Position = UDim2.new(0, 0, 1, -10)
titleFix.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
titleFix.BorderSizePixel = 0
titleFix.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -40, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "📬 Mailbox GUI"
titleLabel.TextColor3 = Color3.fromRGB(220, 220, 255)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 15
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 5)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.BorderSizePixel = 0
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

-- Scroll
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -16, 1, -46)
scroll.Position = UDim2.new(0, 8, 0, 42)
scroll.BackgroundTransparency = 1
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 160)
scroll.BorderSizePixel = 0
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = frame

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = scroll

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 4)
padding.PaddingBottom = UDim.new(0, 8)
padding.Parent = scroll

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function makeLabel(text, order, parent)
    local p = parent or scroll
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 16)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = Color3.fromRGB(150, 150, 195)
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.LayoutOrder = order
    lbl.Parent = p
    return lbl
end

local function makeInput(placeholder, order, parent, w)
    local p = parent or scroll
    local box = Instance.new("TextBox")
    box.Size = w or UDim2.new(1, 0, 0, 34)
    box.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
    box.BorderSizePixel = 0
    box.Text = ""
    box.PlaceholderText = placeholder
    box.PlaceholderColor3 = Color3.fromRGB(80, 80, 115)
    box.TextColor3 = Color3.fromRGB(220, 220, 255)
    box.Font = Enum.Font.Gotham
    box.TextSize = 13
    box.ClearTextOnFocus = false
    box.LayoutOrder = order
    box.Parent = p
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 7)
    local pad = Instance.new("UIPadding", box)
    pad.PaddingLeft = UDim.new(0, 10)
    return box
end

local function makeButton(text, color, order, parent, w)
    local p = parent or scroll
    local btn = Instance.new("TextButton")
    btn.Size = w or UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3 = color
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.LayoutOrder = order
    btn.Parent = p
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
    return btn
end

local function makeDivider(order)
    local d = Instance.new("Frame")
    d.Size = UDim2.new(1, 0, 0, 1)
    d.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
    d.BorderSizePixel = 0
    d.LayoutOrder = order
    d.Parent = scroll
    return d
end

local function makeToggleRow(labelText, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order
    row.Parent = scroll

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -54, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = Color3.fromRGB(200, 200, 230)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local togFrame = Instance.new("Frame")
    togFrame.Size = UDim2.new(0, 44, 0, 24)
    togFrame.Position = UDim2.new(1, -44, 0.5, -12)
    togFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
    togFrame.BorderSizePixel = 0
    togFrame.Parent = row
    Instance.new("UICorner", togFrame).CornerRadius = UDim.new(1, 0)

    local thumb = Instance.new("Frame")
    thumb.Size = UDim2.new(0, 18, 0, 18)
    thumb.Position = UDim2.new(0, 3, 0.5, -9)
    thumb.BackgroundColor3 = Color3.fromRGB(180, 180, 210)
    thumb.BorderSizePixel = 0
    thumb.Parent = togFrame
    Instance.new("UICorner", thumb).CornerRadius = UDim.new(1, 0)

    local state = false
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.Parent = togFrame

    local function refresh()
        if state then
            togFrame.BackgroundColor3 = Color3.fromRGB(80, 130, 255)
            thumb.Position = UDim2.new(1, -21, 0.5, -9)
            thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        else
            togFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
            thumb.Position = UDim2.new(0, 3, 0.5, -9)
            thumb.BackgroundColor3 = Color3.fromRGB(180, 180, 210)
        end
    end
    btn.MouseButton1Click:Connect(function() state = not state refresh() end)
    return row, function() return state end, function(v) state = v refresh() end
end

-- ─── Log box ──────────────────────────────────────────────────────────────────
local logBox = Instance.new("TextLabel")
logBox.Size = UDim2.new(1, 0, 0, 46)
logBox.BackgroundColor3 = Color3.fromRGB(12, 12, 20)
logBox.BorderSizePixel = 0
logBox.TextColor3 = Color3.fromRGB(100, 220, 130)
logBox.Font = Enum.Font.Code
logBox.TextSize = 11
logBox.Text = "Idle."
logBox.TextWrapped = true
logBox.TextXAlignment = Enum.TextXAlignment.Left
logBox.TextYAlignment = Enum.TextYAlignment.Top
logBox.LayoutOrder = 100
logBox.Parent = scroll
Instance.new("UICorner", logBox).CornerRadius = UDim.new(0, 6)
local logPad = Instance.new("UIPadding", logBox)
logPad.PaddingLeft = UDim.new(0, 8)
logPad.PaddingTop = UDim.new(0, 6)

local function log(msg) logBox.Text = msg end

-- ─── Section: Recipient ───────────────────────────────────────────────────────
makeLabel("Recipient username", 1)
local usernameBox = makeInput("Enter Roblox username", 2)
usernameBox.FocusLost:Connect(function() cfg.username = usernameBox.Text end)

makeDivider(3)

-- ─── Section: Items (dynamic rows) ───────────────────────────────────────────
makeLabel("Items to send", 4)

-- Container that holds all item rows + add button, managed by a UIListLayout
local itemsContainer = Instance.new("Frame")
itemsContainer.Name = "ItemsContainer"
itemsContainer.Size = UDim2.new(1, 0, 0, 10) -- auto-expands
itemsContainer.AutomaticSize = Enum.AutomaticSize.Y
itemsContainer.BackgroundTransparency = 1
itemsContainer.BorderSizePixel = 0
itemsContainer.LayoutOrder = 5
itemsContainer.Parent = scroll

local icLayout = Instance.new("UIListLayout")
icLayout.SortOrder = Enum.SortOrder.LayoutOrder
icLayout.Padding = UDim.new(0, 6)
icLayout.Parent = itemsContainer

local itemRows = {}  -- list of { nameBox, amountBox, frame }

local function collectItems()
    cfg.items = {}
    for _, row in ipairs(itemRows) do
        local name = row.nameBox.Text
        local amt  = tonumber(row.amountBox.Text) or 1
        if name ~= "" then
            table.insert(cfg.items, { name = name, amount = amt })
        end
    end
end

local addItemBtn  -- forward declare so removeRow can reference itemsContainer order

local function removeRow(rowData)
    rowData.frame:Destroy()
    for i, r in ipairs(itemRows) do
        if r == rowData then table.remove(itemRows, i) break end
    end
    collectItems()
end

local function addItemRow(defaultName, defaultAmt)
    local rowFrame = Instance.new("Frame")
    rowFrame.Size = UDim2.new(1, 0, 0, 80)  -- two input lines + spacing
    rowFrame.AutomaticSize = Enum.AutomaticSize.Y
    rowFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
    rowFrame.BorderSizePixel = 0
    rowFrame.LayoutOrder = #itemRows + 1
    rowFrame.Parent = itemsContainer
    Instance.new("UICorner", rowFrame).CornerRadius = UDim.new(0, 8)

    local innerPad = Instance.new("UIPadding", rowFrame)
    innerPad.PaddingLeft   = UDim.new(0, 10)
    innerPad.PaddingRight  = UDim.new(0, 10)
    innerPad.PaddingTop    = UDim.new(0, 8)
    innerPad.PaddingBottom = UDim.new(0, 8)

    local innerLayout = Instance.new("UIListLayout", rowFrame)
    innerLayout.SortOrder = Enum.SortOrder.LayoutOrder
    innerLayout.Padding = UDim.new(0, 6)

    -- Row header: "Item #N" label + remove X button
    local headerRow = Instance.new("Frame")
    headerRow.Size = UDim2.new(1, 0, 0, 16)
    headerRow.BackgroundTransparency = 1
    headerRow.LayoutOrder = 1
    headerRow.Parent = rowFrame

    local rowIndex = #itemRows + 1
    local headerLbl = Instance.new("TextLabel")
    headerLbl.Size = UDim2.new(1, -26, 1, 0)
    headerLbl.BackgroundTransparency = 1
    headerLbl.Text = "Item #" .. rowIndex
    headerLbl.TextColor3 = Color3.fromRGB(130, 130, 180)
    headerLbl.Font = Enum.Font.GothamSemibold
    headerLbl.TextSize = 11
    headerLbl.TextXAlignment = Enum.TextXAlignment.Left
    headerLbl.Parent = headerRow

    local removeBtn = Instance.new("TextButton")
    removeBtn.Size = UDim2.new(0, 20, 0, 16)
    removeBtn.Position = UDim2.new(1, -20, 0, 0)
    removeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    removeBtn.Text = "✕"
    removeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    removeBtn.Font = Enum.Font.GothamBold
    removeBtn.TextSize = 10
    removeBtn.BorderSizePixel = 0
    removeBtn.Parent = headerRow
    Instance.new("UICorner", removeBtn).CornerRadius = UDim.new(0, 4)

    -- Item name label + box
    local nameLbl = Instance.new("TextLabel")
    nameLbl.Size = UDim2.new(1, 0, 0, 13)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = "Item name"
    nameLbl.TextColor3 = Color3.fromRGB(120, 120, 165)
    nameLbl.Font = Enum.Font.Gotham
    nameLbl.TextSize = 11
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.LayoutOrder = 2
    nameLbl.Parent = rowFrame

    local nameBox = Instance.new("TextBox")
    nameBox.Size = UDim2.new(1, 0, 0, 32)
    nameBox.BackgroundColor3 = Color3.fromRGB(32, 32, 48)
    nameBox.BorderSizePixel = 0
    nameBox.Text = defaultName or ""
    nameBox.PlaceholderText = "e.g. Bee"
    nameBox.PlaceholderColor3 = Color3.fromRGB(75, 75, 110)
    nameBox.TextColor3 = Color3.fromRGB(220, 220, 255)
    nameBox.Font = Enum.Font.Gotham
    nameBox.TextSize = 13
    nameBox.ClearTextOnFocus = false
    nameBox.LayoutOrder = 3
    nameBox.Parent = rowFrame
    Instance.new("UICorner", nameBox).CornerRadius = UDim.new(0, 6)
    local np = Instance.new("UIPadding", nameBox)
    np.PaddingLeft = UDim.new(0, 10)

    -- Amount label + box
    local amtLbl = Instance.new("TextLabel")
    amtLbl.Size = UDim2.new(1, 0, 0, 13)
    amtLbl.BackgroundTransparency = 1
    amtLbl.Text = "Amount"
    amtLbl.TextColor3 = Color3.fromRGB(120, 120, 165)
    amtLbl.Font = Enum.Font.Gotham
    amtLbl.TextSize = 11
    amtLbl.TextXAlignment = Enum.TextXAlignment.Left
    amtLbl.LayoutOrder = 4
    amtLbl.Parent = rowFrame

    local amountBox = Instance.new("TextBox")
    amountBox.Size = UDim2.new(1, 0, 0, 32)
    amountBox.BackgroundColor3 = Color3.fromRGB(32, 32, 48)
    amountBox.BorderSizePixel = 0
    amountBox.Text = defaultAmt and tostring(defaultAmt) or ""
    amountBox.PlaceholderText = "e.g. 5"
    amountBox.PlaceholderColor3 = Color3.fromRGB(75, 75, 110)
    amountBox.TextColor3 = Color3.fromRGB(220, 220, 255)
    amountBox.Font = Enum.Font.Gotham
    amountBox.TextSize = 13
    amountBox.ClearTextOnFocus = false
    amountBox.LayoutOrder = 5
    amountBox.Parent = rowFrame
    Instance.new("UICorner", amountBox).CornerRadius = UDim.new(0, 6)
    local ap = Instance.new("UIPadding", amountBox)
    ap.PaddingLeft = UDim.new(0, 10)

    local rowData = { frame = rowFrame, nameBox = nameBox, amountBox = amountBox }
    table.insert(itemRows, rowData)

    removeBtn.MouseButton1Click:Connect(function() removeRow(rowData) end)
    nameBox.FocusLost:Connect(collectItems)
    amountBox.FocusLost:Connect(collectItems)

    return rowData
end

-- Add Item button (sits at bottom of itemsContainer)
local addItemBtnFrame = Instance.new("Frame")
addItemBtnFrame.Size = UDim2.new(1, 0, 0, 34)
addItemBtnFrame.BackgroundTransparency = 1
addItemBtnFrame.LayoutOrder = 999
addItemBtnFrame.Parent = itemsContainer

addItemBtn = Instance.new("TextButton")
addItemBtn.Size = UDim2.new(1, 0, 1, 0)
addItemBtn.BackgroundColor3 = Color3.fromRGB(35, 100, 60)
addItemBtn.BorderSizePixel = 0
addItemBtn.Text = "+ Add Item"
addItemBtn.TextColor3 = Color3.fromRGB(200, 255, 210)
addItemBtn.Font = Enum.Font.GothamBold
addItemBtn.TextSize = 12
addItemBtn.Parent = addItemBtnFrame
Instance.new("UICorner", addItemBtn).CornerRadius = UDim.new(0, 7)

addItemBtn.MouseButton1Click:Connect(function()
    addItemRow()
end)

-- Start with one empty row
addItemRow()

makeDivider(6)

-- ─── Section: Note ────────────────────────────────────────────────────────────
makeLabel("Mail note  (optional)", 7)
local noteBox = makeInput("Leave a note...", 8)
noteBox.FocusLost:Connect(function() cfg.note = noteBox.Text end)

makeDivider(9)

-- ─── Section: Interval ───────────────────────────────────────────────────────
makeLabel("Auto send interval  (seconds)", 10)

local intervalRow = Instance.new("Frame")
intervalRow.Size = UDim2.new(1, 0, 0, 34)
intervalRow.BackgroundTransparency = 1
intervalRow.LayoutOrder = 11
intervalRow.Parent = scroll

local intervalBox = Instance.new("TextBox")
intervalBox.Size = UDim2.new(0, 70, 1, 0)
intervalBox.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
intervalBox.BorderSizePixel = 0
intervalBox.Text = "10"
intervalBox.TextColor3 = Color3.fromRGB(220, 220, 255)
intervalBox.Font = Enum.Font.GothamBold
intervalBox.TextSize = 14
intervalBox.ClearTextOnFocus = false
intervalBox.Parent = intervalRow
Instance.new("UICorner", intervalBox).CornerRadius = UDim.new(0, 7)
local ip = Instance.new("UIPadding", intervalBox)
ip.PaddingLeft = UDim.new(0, 10)

intervalBox.FocusLost:Connect(function()
    local v = tonumber(intervalBox.Text)
    if v and v >= 1 then cfg.interval = v else intervalBox.Text = tostring(cfg.interval) end
end)

local secLbl = Instance.new("TextLabel")
secLbl.Size = UDim2.new(1, -80, 1, 0)
secLbl.Position = UDim2.new(0, 80, 0, 0)
secLbl.BackgroundTransparency = 1
secLbl.Text = "seconds between each send"
secLbl.TextColor3 = Color3.fromRGB(120, 120, 165)
secLbl.Font = Enum.Font.Gotham
secLbl.TextSize = 12
secLbl.TextXAlignment = Enum.TextXAlignment.Left
secLbl.Parent = intervalRow

makeDivider(12)

-- ─── Section: Toggles ─────────────────────────────────────────────────────────
local _, getAutoSend, setAutoSend     = makeToggleRow("Auto Send",       13)
local _, getAutoClaim, setAutoClaim   = makeToggleRow("Auto Claim Mail", 14)

makeDivider(15)

-- ─── Buttons ──────────────────────────────────────────────────────────────────
local sendOnceBtn  = makeButton("▶  Send Once",        Color3.fromRGB(60, 120, 220),  16)
local autoSendBtn  = makeButton("⏵  Start Auto Send",  Color3.fromRGB(40, 160, 90),   17)
local claimNowBtn  = makeButton("📥  Claim Mail Now",  Color3.fromRGB(120, 65, 200),  18)

-- ─── Logic ────────────────────────────────────────────────────────────────────
local autoSendRunning = false
local autoSendThread  = nil
local autoClaimRunning = false
local autoClaimThread  = nil

sendOnceBtn.MouseButton1Click:Connect(function()
    collectItems()
    cfg.username = usernameBox.Text
    cfg.note = noteBox.Text
    log("[Mailbox] Sending once...")
    task.spawn(function() pcall(function() doSend(log) end) end)
end)

local function stopAutoSend()
    autoSendRunning = false
    if autoSendThread then task.cancel(autoSendThread) autoSendThread = nil end
    autoSendBtn.Text = "⏵  Start Auto Send"
    autoSendBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
    log("[Mailbox] Auto send stopped.")
end

local function startAutoSend()
    autoSendRunning = true
    autoSendBtn.Text = "⏹  Stop Auto Send"
    autoSendBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
    autoSendThread = task.spawn(function()
        while autoSendRunning do
            collectItems()
            cfg.username = usernameBox.Text
            cfg.note     = noteBox.Text
            cfg.interval = tonumber(intervalBox.Text) or 10
            pcall(function() doSend(log) end)
            task.wait(cfg.interval)
        end
    end)
end

autoSendBtn.MouseButton1Click:Connect(function()
    if autoSendRunning then stopAutoSend() setAutoSend(false)
    else startAutoSend() setAutoSend(true) end
end)

claimNowBtn.MouseButton1Click:Connect(function()
    log("[Mailbox] Claiming mail...")
    task.spawn(function() pcall(function() doClaim(log) end) end)
end)

local function syncAutoClaimLoop()
    if getAutoClaim() and not autoClaimRunning then
        autoClaimRunning = true
        autoClaimThread = task.spawn(function()
            while getAutoClaim() do
                pcall(function() doClaim(log) end)
                task.wait(30)
            end
            autoClaimRunning = false
        end)
    end
end

task.spawn(function()
    while gui.Parent do
        if getAutoSend() and not autoSendRunning then startAutoSend()
        elseif not getAutoSend() and autoSendRunning then stopAutoSend() end
        syncAutoClaimLoop()
        task.wait(0.5)
    end
end)

log("Ready. Add items, fill details, then send.")
