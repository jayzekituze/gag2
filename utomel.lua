-- Auto Send Mailbox GUI
-- Paste into your executor

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

-- ─── Config ───────────────────────────────────────────────────────────────────
local cfg = {
    username = "",
    items    = {},   -- { name, amount }
    note     = "",
    interval = 10,
    maxItems = 100,
}

local STACK = {
    Sprinklers=1, WateringCans=1, Mushrooms=1, Gnomes=1, Raccoons=1, Crates=1,
    SeedPacks=1, Trowels=1, Props=1, Seeds=1, HarvestedFruits=1, Flashbangs=1, EmptyPots=1,
}

local function getNet() return require(RS:WaitForChild("SharedModules"):WaitForChild("Networking")) end
local function getPS()  return require(RS:WaitForChild("ClientModules"):WaitForChild("PlayerStateClient")) end
local function getInv()
    local ok, r = pcall(function() return getPS():WaitForLocalReplica(5) end)
    return ok and r and r.Data and type(r.Data.Inventory)=="table" and r.Data.Inventory
end

local function buildBatch(inv, items)
    local out, max = {}, 20
    for _, entry in ipairs(items) do
        local name, amt = entry.name, math.min(entry.amount, cfg.maxItems)
        if #out >= max then break end
        local want = math.max(1, math.floor(tonumber(amt) or 1))
        if type(inv.Pets)=="table" then
            for key, p in pairs(inv.Pets) do
                if want<=0 or #out>=max then break end
                if type(p)=="table" and p.Id and not p.Equipped and tostring(p.Name)==name then
                    out[#out+1] = {Category="Pets", ItemKey=key, Count=1}
                    want -= 1
                end
            end
        end
        if want > 0 then
            for cat in pairs(STACK) do
                local t = inv[cat]
                if type(t)=="table" and type(t[name])=="number" and t[name]>0 then
                    out[#out+1] = {Category=cat, ItemKey=name, Count=math.min(want, t[name])}
                    break
                end
            end
        end
    end
    return out
end

local function doSend(logFn)
    if cfg.username=="" then logFn("⚠  No username set.") return false end
    if #cfg.items==0 then logFn("⚠  No items in list.") return false end
    local inv = getInv()
    if not inv then logFn("⚠  Could not read inventory.") return false end
    local batch = buildBatch(inv, cfg.items)
    if #batch==0 then logFn("⚠  Items not found in inventory.") return false end
    local Net = getNet()
    local ok, uid = pcall(function() return Net.Mailbox.LookupPlayer:Fire(cfg.username) end)
    if not ok or type(uid)~="number" or uid<=0 then logFn("⚠  Player lookup failed.") return false end
    local ok2, success = pcall(function() return Net.Mailbox.SendBatch:Fire(uid, batch, cfg.note or "") end)
    if success==true then logFn("✓  Sent to "..cfg.username) return true
    else logFn("✗  Send failed.") return false end
end

local function doClaim(logFn)
    local ok = pcall(function() return getNet().Mailbox.ClaimAll:Fire() end)
    logFn(ok and "✓  Mail claimed." or "✗  Claim failed.")
end

-- ─── GUI Root ─────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "AutoSendMailbox"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Colours
local C = {
    bg       = Color3.fromRGB(15, 15, 22),
    surface  = Color3.fromRGB(22, 22, 34),
    card     = Color3.fromRGB(28, 28, 44),
    cardHov  = Color3.fromRGB(34, 34, 52),
    border   = Color3.fromRGB(50, 50, 75),
    accent   = Color3.fromRGB(90, 130, 255),
    accentDk = Color3.fromRGB(55, 90, 200),
    green    = Color3.fromRGB(50, 185, 100),
    greenDk  = Color3.fromRGB(35, 140, 70),
    red      = Color3.fromRGB(210, 65, 65),
    redDk    = Color3.fromRGB(160, 45, 45),
    purple   = Color3.fromRGB(140, 80, 220),
    txt      = Color3.fromRGB(225, 225, 245),
    txtMuted = Color3.fromRGB(130, 130, 170),
    txtDim   = Color3.fromRGB(80, 80, 115),
    input    = Color3.fromRGB(20, 20, 32),
    tag      = Color3.fromRGB(38, 38, 58),
    tagBrd   = Color3.fromRGB(60, 60, 90),
}

-- ─── Main window (resizable) ──────────────────────────────────────────────────
local mainFrame = Instance.new("Frame")
mainFrame.Name = "Window"
mainFrame.Size = UDim2.new(0, 420, 0, 560)
mainFrame.Position = UDim2.new(0.5, -210, 0.5, -280)
mainFrame.BackgroundColor3 = C.bg
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.ClipsDescendants = true
mainFrame.Parent = gui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)

-- Subtle border
local winStroke = Instance.new("UIStroke", mainFrame)
winStroke.Color = C.border
winStroke.Thickness = 1
winStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

-- Resize handle (bottom-right corner)
local resizeHandle = Instance.new("TextButton")
resizeHandle.Size = UDim2.new(0, 18, 0, 18)
resizeHandle.Position = UDim2.new(1, -18, 1, -18)
resizeHandle.BackgroundTransparency = 1
resizeHandle.Text = "⇲"
resizeHandle.TextColor3 = C.txtDim
resizeHandle.Font = Enum.Font.GothamBold
resizeHandle.TextSize = 13
resizeHandle.ZIndex = 10
resizeHandle.Parent = mainFrame

do
    local dragging, startMouse, startSize = false
    resizeHandle.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            startMouse = inp.Position
            startSize = mainFrame.AbsoluteSize
        end
    end)
    game:GetService("UserInputService").InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = inp.Position - startMouse
            local newW = math.clamp(startSize.X + delta.X, 340, 620)
            local newH = math.clamp(startSize.Y + delta.Y, 420, 700)
            mainFrame.Size = UDim2.new(0, newW, 0, newH)
        end
    end)
    game:GetService("UserInputService").InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
end

-- ─── Title bar ────────────────────────────────────────────────────────────────
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundColor3 = C.surface
titleBar.BorderSizePixel = 0
titleBar.ZIndex = 3
titleBar.Parent = mainFrame

-- fix rounded top only
local titleFix = Instance.new("Frame")
titleFix.Size = UDim2.new(1, 0, 0, 12)
titleFix.Position = UDim2.new(0, 0, 1, -12)
titleFix.BackgroundColor3 = C.surface
titleFix.BorderSizePixel = 0
titleFix.Parent = titleBar

local titleCrn = Instance.new("UICorner", titleBar)
titleCrn.CornerRadius = UDim.new(0, 12)

-- Icon dot
local iconDot = Instance.new("Frame")
iconDot.Size = UDim2.new(0, 10, 0, 10)
iconDot.Position = UDim2.new(0, 14, 0.5, -5)
iconDot.BackgroundColor3 = C.accent
iconDot.BorderSizePixel = 0
iconDot.Parent = titleBar
Instance.new("UICorner", iconDot).CornerRadius = UDim.new(1, 0)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -120, 1, 0)
titleLbl.Position = UDim2.new(0, 30, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "Auto Send Mailbox"
titleLbl.TextColor3 = C.txt
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 15
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Parent = titleBar

-- Hide toggle button
local hideBtn = Instance.new("TextButton")
hideBtn.Size = UDim2.new(0, 28, 0, 28)
hideBtn.Position = UDim2.new(1, -68, 0.5, -14)
hideBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 60)
hideBtn.Text = "−"
hideBtn.TextColor3 = Color3.fromRGB(255,255,255)
hideBtn.Font = Enum.Font.GothamBold
hideBtn.TextSize = 16
hideBtn.BorderSizePixel = 0
hideBtn.Parent = titleBar
Instance.new("UICorner", hideBtn).CornerRadius = UDim.new(0, 6)

local closeBtn2 = Instance.new("TextButton")
closeBtn2.Size = UDim2.new(0, 28, 0, 28)
closeBtn2.Position = UDim2.new(1, -34, 0.5, -14)
closeBtn2.BackgroundColor3 = C.red
closeBtn2.Text = "✕"
closeBtn2.TextColor3 = Color3.fromRGB(255,255,255)
closeBtn2.Font = Enum.Font.GothamBold
closeBtn2.TextSize = 13
closeBtn2.BorderSizePixel = 0
closeBtn2.Parent = titleBar
Instance.new("UICorner", closeBtn2).CornerRadius = UDim.new(0, 6)
closeBtn2.MouseButton1Click:Connect(function() gui:Destroy() end)

-- Mini icon button (always visible when hidden)
local miniBtn = Instance.new("TextButton")
miniBtn.Size = UDim2.new(0, 36, 0, 36)
miniBtn.Position = UDim2.new(0, 10, 0.5, -18)
miniBtn.BackgroundColor3 = C.accent
miniBtn.Text = "📬"
miniBtn.TextSize = 18
miniBtn.Font = Enum.Font.GothamBold
miniBtn.BorderSizePixel = 0
miniBtn.Visible = false
miniBtn.ZIndex = 20
miniBtn.Parent = gui
Instance.new("UICorner", miniBtn).CornerRadius = UDim.new(0, 10)

local guiVisible = true
hideBtn.MouseButton1Click:Connect(function()
    guiVisible = not guiVisible
    mainFrame.Visible = guiVisible
    miniBtn.Visible = not guiVisible
    hideBtn.Text = guiVisible and "−" or "+"
end)
miniBtn.MouseButton1Click:Connect(function()
    guiVisible = true
    mainFrame.Visible = true
    miniBtn.Visible = false
    hideBtn.Text = "−"
end)

-- ─── Tab bar ──────────────────────────────────────────────────────────────────
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(0, 130, 1, -44)
tabBar.Position = UDim2.new(0, 0, 0, 44)
tabBar.BackgroundColor3 = C.surface
tabBar.BorderSizePixel = 0
tabBar.Parent = mainFrame

local tabStroke = Instance.new("UIStroke", tabBar)
tabStroke.Color = C.border
tabStroke.Thickness = 1
tabStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local tabLayout = Instance.new("UIListLayout", tabBar)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Padding = UDim.new(0, 2)

local tabPad = Instance.new("UIPadding", tabBar)
tabPad.PaddingTop = UDim.new(0, 10)
tabPad.PaddingLeft = UDim.new(0, 6)
tabPad.PaddingRight = UDim.new(0, 6)

-- Version label at bottom of sidebar
local versionLbl = Instance.new("TextLabel")
versionLbl.Size = UDim2.new(1, 0, 0, 20)
versionLbl.Position = UDim2.new(0, 0, 1, -24)
versionLbl.BackgroundTransparency = 1
versionLbl.Text = "v1.0"
versionLbl.TextColor3 = C.txtDim
versionLbl.Font = Enum.Font.Gotham
versionLbl.TextSize = 10
versionLbl.TextXAlignment = Enum.TextXAlignment.Center
versionLbl.Parent = tabBar

-- Content area
local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, -130, 1, -44)
contentArea.Position = UDim2.new(0, 130, 0, 44)
contentArea.BackgroundColor3 = C.bg
contentArea.BorderSizePixel = 0
contentArea.ClipsDescendants = true
contentArea.Parent = mainFrame

-- ─── Tab button factory ───────────────────────────────────────────────────────
local tabs = {}
local activeTab = nil

local function makeTab(icon, name, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 38)
    btn.BackgroundColor3 = C.surface
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.LayoutOrder = order
    btn.Parent = tabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

    local iconLbl = Instance.new("TextLabel")
    iconLbl.Size = UDim2.new(0, 22, 1, 0)
    iconLbl.Position = UDim2.new(0, 8, 0, 0)
    iconLbl.BackgroundTransparency = 1
    iconLbl.Text = icon
    iconLbl.TextSize = 14
    iconLbl.Font = Enum.Font.GothamBold
    iconLbl.TextColor3 = C.txtMuted
    iconLbl.Parent = btn

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Size = UDim2.new(1, -36, 1, 0)
    nameLbl.Position = UDim2.new(0, 34, 0, 0)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = name
    nameLbl.Font = Enum.Font.GothamSemibold
    nameLbl.TextSize = 13
    nameLbl.TextColor3 = C.txtMuted
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.Parent = btn

    -- accent bar on left
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 3, 0, 20)
    bar.Position = UDim2.new(0, 0, 0.5, -10)
    bar.BackgroundColor3 = C.accent
    bar.BorderSizePixel = 0
    bar.Visible = false
    bar.Parent = btn
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)

    -- Page frame
    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = C.border
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.Parent = contentArea

    local pageLayout = Instance.new("UIListLayout", page)
    pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
    pageLayout.Padding = UDim.new(0, 10)

    local pagePad = Instance.new("UIPadding", page)
    pagePad.PaddingTop    = UDim.new(0, 14)
    pagePad.PaddingBottom = UDim.new(0, 14)
    pagePad.PaddingLeft   = UDim.new(0, 12)
    pagePad.PaddingRight  = UDim.new(0, 12)

    local tabData = {btn=btn, page=page, bar=bar, iconLbl=iconLbl, nameLbl=nameLbl}
    table.insert(tabs, tabData)

    btn.MouseButton1Click:Connect(function()
        if activeTab then
            activeTab.page.Visible = false
            activeTab.btn.BackgroundColor3 = C.surface
            activeTab.bar.Visible = false
            activeTab.iconLbl.TextColor3 = C.txtMuted
            activeTab.nameLbl.TextColor3 = C.txtMuted
        end
        activeTab = tabData
        page.Visible = true
        btn.BackgroundColor3 = C.card
        bar.Visible = true
        iconLbl.TextColor3 = C.txt
        nameLbl.TextColor3 = C.txt
    end)

    return tabData
end

local mailTab     = makeTab("✉", "Mail",     1)
local settingsTab = makeTab("⚙", "Settings", 2)

-- Activate mail tab by default
mailTab.btn.BackgroundColor3 = C.card
mailTab.bar.Visible = true
mailTab.iconLbl.TextColor3 = C.txt
mailTab.nameLbl.TextColor3 = C.txt
mailTab.page.Visible = true
activeTab = mailTab

-- ─── Shared widget builders ───────────────────────────────────────────────────
local function sectionLabel(text, order, page)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, 18)
    f.BackgroundTransparency = 1
    f.LayoutOrder = order
    f.Parent = page

    local lbl = Instance.new("TextLabel", f)
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text:upper()
    lbl.TextColor3 = C.txtDim
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    return f
end

local function makeInputBox(placeholder, order, page)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, 0, 0, 36)
    box.BackgroundColor3 = C.input
    box.BorderSizePixel = 0
    box.Text = ""
    box.PlaceholderText = placeholder
    box.PlaceholderColor3 = C.txtDim
    box.TextColor3 = C.txt
    box.Font = Enum.Font.Gotham
    box.TextSize = 13
    box.ClearTextOnFocus = false
    box.LayoutOrder = order
    box.Parent = page
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", box)
    stroke.Color = C.border
    stroke.Thickness = 1
    local pad = Instance.new("UIPadding", box)
    pad.PaddingLeft = UDim.new(0, 12)
    box.Focused:Connect(function() stroke.Color = C.accent end)
    box.FocusLost:Connect(function() stroke.Color = C.border end)
    return box
end

local function makeBigBtn(text, color, order, page)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 38)
    btn.BackgroundColor3 = color
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.LayoutOrder = order
    btn.Parent = page
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = color:Lerp(Color3.new(1,1,1), 0.08)}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = color}):Play()
    end)
    return btn
end

local function makeToggle(labelText, order, page)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 40)
    row.BackgroundColor3 = C.card
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = page
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", row)
    stroke.Color = C.border stroke.Thickness = 1

    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(1, -64, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = C.txt
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local pill = Instance.new("Frame", row)
    pill.Size = UDim2.new(0, 44, 0, 24)
    pill.Position = UDim2.new(1, -56, 0.5, -12)
    pill.BackgroundColor3 = C.border
    pill.BorderSizePixel = 0
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

    local thumb = Instance.new("Frame", pill)
    thumb.Size = UDim2.new(0, 18, 0, 18)
    thumb.Position = UDim2.new(0, 3, 0.5, -9)
    thumb.BackgroundColor3 = Color3.fromRGB(180, 180, 210)
    thumb.BorderSizePixel = 0
    Instance.new("UICorner", thumb).CornerRadius = UDim.new(1, 0)

    local state = false
    local hitbox = Instance.new("TextButton", row)
    hitbox.Size = UDim2.new(1, 0, 1, 0)
    hitbox.BackgroundTransparency = 1
    hitbox.Text = ""

    local function refresh()
        if state then
            TweenService:Create(pill, TweenInfo.new(0.2), {BackgroundColor3 = C.accent}):Play()
            TweenService:Create(thumb, TweenInfo.new(0.2), {Position = UDim2.new(1,-21,0.5,-9), BackgroundColor3 = Color3.new(1,1,1)}):Play()
        else
            TweenService:Create(pill, TweenInfo.new(0.2), {BackgroundColor3 = C.border}):Play()
            TweenService:Create(thumb, TweenInfo.new(0.2), {Position = UDim2.new(0,3,0.5,-9), BackgroundColor3 = Color3.fromRGB(180,180,210)}):Play()
        end
    end
    hitbox.MouseButton1Click:Connect(function() state = not state refresh() end)
    return row, function() return state end, function(v) state=v refresh() end
end

-- ─── Log bar (shared, sits at very bottom of mail page) ───────────────────────
local logBar = Instance.new("Frame")
logBar.Size = UDim2.new(1, 0, 0, 38)
logBar.BackgroundColor3 = C.card
logBar.BorderSizePixel = 0
logBar.LayoutOrder = 200
logBar.Parent = mailTab.page
Instance.new("UICorner", logBar).CornerRadius = UDim.new(0, 8)
local logStroke = Instance.new("UIStroke", logBar)
logStroke.Color = C.border logStroke.Thickness = 1

local logDot = Instance.new("Frame", logBar)
logDot.Size = UDim2.new(0, 7, 0, 7)
logDot.Position = UDim2.new(0, 12, 0.5, -3.5)
logDot.BackgroundColor3 = C.green
logDot.BorderSizePixel = 0
Instance.new("UICorner", logDot).CornerRadius = UDim.new(1, 0)

local logLbl = Instance.new("TextLabel", logBar)
logLbl.Size = UDim2.new(1, -30, 1, 0)
logLbl.Position = UDim2.new(0, 26, 0, 0)
logLbl.BackgroundTransparency = 1
logLbl.Text = "Idle — ready to send."
logLbl.TextColor3 = C.txtMuted
logLbl.Font = Enum.Font.Gotham
logLbl.TextSize = 12
logLbl.TextXAlignment = Enum.TextXAlignment.Left
logLbl.TextTruncate = Enum.TextTruncate.AtEnd

local function log(msg, isErr)
    logLbl.Text = msg
    local col = isErr and C.red or C.green
    logDot.BackgroundColor3 = col
    logLbl.TextColor3 = isErr and Color3.fromRGB(240, 140, 140) or C.txtMuted
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- MAIL TAB
-- ═══════════════════════════════════════════════════════════════════════════════
local mp = mailTab.page

sectionLabel("Recipient", 1, mp)
local usernameBox = makeInputBox("Roblox username", 2, mp)
usernameBox.FocusLost:Connect(function() cfg.username = usernameBox.Text end)

-- ─── Item list card ───────────────────────────────────────────────────────────
sectionLabel("Items to send", 3, mp)

local itemCard = Instance.new("Frame")
itemCard.Size = UDim2.new(1, 0, 0, 10)
itemCard.AutomaticSize = Enum.AutomaticSize.Y
itemCard.BackgroundColor3 = C.card
itemCard.BorderSizePixel = 0
itemCard.LayoutOrder = 4
itemCard.Parent = mp
Instance.new("UICorner", itemCard).CornerRadius = UDim.new(0, 10)
local icStroke = Instance.new("UIStroke", itemCard)
icStroke.Color = C.border icStroke.Thickness = 1

local icLayout = Instance.new("UIListLayout", itemCard)
icLayout.SortOrder = Enum.SortOrder.LayoutOrder
icLayout.Padding = UDim.new(0, 0)

-- Input row at top of card
local inputRow = Instance.new("Frame", itemCard)
inputRow.Size = UDim2.new(1, 0, 0, 48)
inputRow.BackgroundTransparency = 1
inputRow.LayoutOrder = 1

local nameIn = Instance.new("TextBox", inputRow)
nameIn.Size = UDim2.new(1, -86, 0, 32)
nameIn.Position = UDim2.new(0, 10, 0.5, -16)
nameIn.BackgroundColor3 = C.input
nameIn.BorderSizePixel = 0
nameIn.PlaceholderText = "Item name"
nameIn.PlaceholderColor3 = C.txtDim
nameIn.Text = ""
nameIn.TextColor3 = C.txt
nameIn.Font = Enum.Font.Gotham
nameIn.TextSize = 13
nameIn.ClearTextOnFocus = false
Instance.new("UICorner", nameIn).CornerRadius = UDim.new(0, 7)
local ns = Instance.new("UIStroke", nameIn); ns.Color = C.border; ns.Thickness = 1
local np2 = Instance.new("UIPadding", nameIn); np2.PaddingLeft = UDim.new(0, 10)
nameIn.Focused:Connect(function() ns.Color = C.accent end)
nameIn.FocusLost:Connect(function() ns.Color = C.border end)

local amtIn = Instance.new("TextBox", inputRow)
amtIn.Size = UDim2.new(0, 52, 0, 32)
amtIn.Position = UDim2.new(1, -76, 0.5, -16)
amtIn.BackgroundColor3 = C.input
amtIn.BorderSizePixel = 0
amtIn.PlaceholderText = "Qty"
amtIn.PlaceholderColor3 = C.txtDim
amtIn.Text = ""
amtIn.TextColor3 = C.txt
amtIn.Font = Enum.Font.GothamBold
amtIn.TextSize = 13
amtIn.ClearTextOnFocus = false
Instance.new("UICorner", amtIn).CornerRadius = UDim.new(0, 7)
local as2 = Instance.new("UIStroke", amtIn); as2.Color = C.border; as2.Thickness = 1
local ap2 = Instance.new("UIPadding", amtIn); ap2.PaddingLeft = UDim.new(0, 8)
amtIn.Focused:Connect(function() as2.Color = C.accent end)
amtIn.FocusLost:Connect(function() as2.Color = C.border end)

local addRowBtn = Instance.new("TextButton", inputRow)
addRowBtn.Size = UDim2.new(0, 32, 0, 32)
addRowBtn.Position = UDim2.new(1, -22, 0.5, -16)
addRowBtn.BackgroundColor3 = C.green
addRowBtn.Text = "+"
addRowBtn.TextColor3 = Color3.new(1,1,1)
addRowBtn.Font = Enum.Font.GothamBold
addRowBtn.TextSize = 18
addRowBtn.BorderSizePixel = 0
Instance.new("UICorner", addRowBtn).CornerRadius = UDim.new(0, 7)

-- Divider
local inputDiv = Instance.new("Frame", itemCard)
inputDiv.Size = UDim2.new(1, -20, 0, 1)
inputDiv.Position = UDim2.new(0, 10, 0, 0) -- layout handles vertical
inputDiv.BackgroundColor3 = C.border
inputDiv.BorderSizePixel = 0
inputDiv.LayoutOrder = 2

-- Item list scroll inner
local itemListFrame = Instance.new("Frame", itemCard)
itemListFrame.Name = "ItemList"
itemListFrame.Size = UDim2.new(1, 0, 0, 0)
itemListFrame.AutomaticSize = Enum.AutomaticSize.Y
itemListFrame.BackgroundTransparency = 1
itemListFrame.BorderSizePixel = 0
itemListFrame.LayoutOrder = 3

local ilLayout = Instance.new("UIListLayout", itemListFrame)
ilLayout.SortOrder = Enum.SortOrder.LayoutOrder
ilLayout.Padding = UDim.new(0, 0)

local emptyLbl = Instance.new("TextLabel", itemListFrame)
emptyLbl.Size = UDim2.new(1, 0, 0, 36)
emptyLbl.BackgroundTransparency = 1
emptyLbl.Text = "No items added yet."
emptyLbl.TextColor3 = C.txtDim
emptyLbl.Font = Enum.Font.Gotham
emptyLbl.TextSize = 12
emptyLbl.LayoutOrder = 999

local itemEntries = {}

local function refreshEmptyLabel()
    emptyLbl.Visible = #itemEntries == 0
end

local function rebuildCfgItems()
    cfg.items = {}
    for _, e in ipairs(itemEntries) do
        local amt = math.min(tonumber(e.amt) or 1, cfg.maxItems)
        table.insert(cfg.items, { name = e.name, amount = amt })
    end
end

local function addItemTag(name, amt)
    if name == "" then log("⚠  Enter an item name first.", true) return end
    amt = math.min(math.max(1, math.floor(tonumber(amt) or 1)), cfg.maxItems)

    local row = Instance.new("Frame", itemListFrame)
    row.Size = UDim2.new(1, 0, 0, 38)
    row.BackgroundColor3 = C.tag
    row.BorderSizePixel = 0
    row.LayoutOrder = #itemEntries + 1

    -- alternating shade
    if (#itemEntries % 2) == 0 then
        row.BackgroundColor3 = C.card
    end

    -- subtle left accent
    local accent = Instance.new("Frame", row)
    accent.Size = UDim2.new(0, 3, 0, 20)
    accent.Position = UDim2.new(0, 0, 0.5, -10)
    accent.BackgroundColor3 = C.accent
    accent.BorderSizePixel = 0
    Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 2)

    local nameLbl2 = Instance.new("TextLabel", row)
    nameLbl2.Size = UDim2.new(1, -100, 1, 0)
    nameLbl2.Position = UDim2.new(0, 12, 0, 0)
    nameLbl2.BackgroundTransparency = 1
    nameLbl2.Text = name
    nameLbl2.TextColor3 = C.txt
    nameLbl2.Font = Enum.Font.GothamSemibold
    nameLbl2.TextSize = 13
    nameLbl2.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl2.TextTruncate = Enum.TextTruncate.AtEnd

    local amtBadge = Instance.new("Frame", row)
    amtBadge.Size = UDim2.new(0, 44, 0, 22)
    amtBadge.Position = UDim2.new(1, -76, 0.5, -11)
    amtBadge.BackgroundColor3 = Color3.fromRGB(30, 55, 100)
    amtBadge.BorderSizePixel = 0
    Instance.new("UICorner", amtBadge).CornerRadius = UDim.new(0, 5)

    local amtLbl2 = Instance.new("TextLabel", amtBadge)
    amtLbl2.Size = UDim2.new(1, 0, 1, 0)
    amtLbl2.BackgroundTransparency = 1
    amtLbl2.Text = "x"..tostring(amt)
    amtLbl2.TextColor3 = Color3.fromRGB(130, 185, 255)
    amtLbl2.Font = Enum.Font.GothamBold
    amtLbl2.TextSize = 11

    local removeBtn2 = Instance.new("TextButton", row)
    removeBtn2.Size = UDim2.new(0, 24, 0, 24)
    removeBtn2.Position = UDim2.new(1, -28, 0.5, -12)
    removeBtn2.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
    removeBtn2.Text = "✕"
    removeBtn2.TextColor3 = Color3.fromRGB(220, 100, 100)
    removeBtn2.Font = Enum.Font.GothamBold
    removeBtn2.TextSize = 10
    removeBtn2.BorderSizePixel = 0
    Instance.new("UICorner", removeBtn2).CornerRadius = UDim.new(0, 5)

    local entry = { frame=row, name=name, amt=amt }
    table.insert(itemEntries, entry)
    refreshEmptyLabel()

    removeBtn2.MouseButton1Click:Connect(function()
        row:Destroy()
        for i, e in ipairs(itemEntries) do
            if e == entry then table.remove(itemEntries, i) break end
        end
        rebuildCfgItems()
        refreshEmptyLabel()
        log("Removed: "..name)
    end)

    rebuildCfgItems()
    log("Added: "..name.." ×"..amt)
end

addRowBtn.MouseButton1Click:Connect(function()
    local n = nameIn.Text:match("^%s*(.-)%s*$")
    local a = amtIn.Text
    addItemTag(n, a)
    nameIn.Text = ""
    amtIn.Text = ""
end)

-- also add on Enter from name box
nameIn.FocusLost:Connect(function(entered)
    if entered then
        local n = nameIn.Text:match("^%s*(.-)%s*$")
        local a = amtIn.Text
        addItemTag(n, a)
        nameIn.Text = ""
        amtIn.Text = ""
    end
end)

-- Note
sectionLabel("Note (optional)", 5, mp)
local noteBox = makeInputBox("Mail note...", 6, mp)
noteBox.FocusLost:Connect(function() cfg.note = noteBox.Text end)

-- Interval
sectionLabel("Auto send interval", 7, mp)

local intRow = Instance.new("Frame")
intRow.Size = UDim2.new(1, 0, 0, 36)
intRow.BackgroundTransparency = 1
intRow.LayoutOrder = 8
intRow.Parent = mp

local intBox = Instance.new("TextBox", intRow)
intBox.Size = UDim2.new(0, 80, 1, 0)
intBox.BackgroundColor3 = C.input
intBox.BorderSizePixel = 0
intBox.Text = "10"
intBox.TextColor3 = C.txt
intBox.Font = Enum.Font.GothamBold
intBox.TextSize = 14
intBox.ClearTextOnFocus = false
Instance.new("UICorner", intBox).CornerRadius = UDim.new(0, 8)
local intStroke = Instance.new("UIStroke", intBox); intStroke.Color = C.border; intStroke.Thickness = 1
local intPad = Instance.new("UIPadding", intBox); intPad.PaddingLeft = UDim.new(0, 12)
intBox.Focused:Connect(function() intStroke.Color = C.accent end)
intBox.FocusLost:Connect(function()
    intStroke.Color = C.border
    local v = tonumber(intBox.Text)
    if v and v >= 1 then cfg.interval = v else intBox.Text = tostring(cfg.interval) end
end)

local intSuffix = Instance.new("TextLabel", intRow)
intSuffix.Size = UDim2.new(1, -90, 1, 0)
intSuffix.Position = UDim2.new(0, 88, 0, 0)
intSuffix.BackgroundTransparency = 1
intSuffix.Text = "seconds"
intSuffix.TextColor3 = C.txtDim
intSuffix.Font = Enum.Font.Gotham
intSuffix.TextSize = 13
intSuffix.TextXAlignment = Enum.TextXAlignment.Left

-- Toggles
local _, getAutoSend, setAutoSend   = makeToggle("Auto Send",       9,  mp)
local _, getAutoClaim, setAutoClaim = makeToggle("Auto Claim Mail", 10, mp)

-- Buttons
local sendOnceBtn = makeBigBtn("▶  Send Once",       C.accent,  11, mp)
local autoSendBtn = makeBigBtn("⏵  Start Auto Send", C.green,   12, mp)
local claimNowBtn = makeBigBtn("📥  Claim Mail Now", C.purple,  13, mp)

-- logBar already parented at order 200

-- ═══════════════════════════════════════════════════════════════════════════════
-- SETTINGS TAB
-- ═══════════════════════════════════════════════════════════════════════════════
local sp = settingsTab.page

sectionLabel("Appearance", 1, sp)

local function settingRow(label, desc, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 52)
    row.BackgroundColor3 = C.card
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = sp
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
    local st = Instance.new("UIStroke", row); st.Color = C.border; st.Thickness = 1

    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(1, -16, 0, 22)
    lbl.Position = UDim2.new(0, 12, 0, 8)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = C.txt
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local desc2 = Instance.new("TextLabel", row)
    desc2.Size = UDim2.new(1, -16, 0, 16)
    desc2.Position = UDim2.new(0, 12, 0, 28)
    desc2.BackgroundTransparency = 1
    desc2.Text = desc
    desc2.TextColor3 = C.txtDim
    desc2.Font = Enum.Font.Gotham
    desc2.TextSize = 11
    desc2.TextXAlignment = Enum.TextXAlignment.Left
    return row
end

local maxItemsRow = settingRow("Max items per send", "Capped at 100 to stay safe", 2)

local maxBox = Instance.new("TextBox", maxItemsRow)
maxBox.Size = UDim2.new(0, 60, 0, 28)
maxBox.Position = UDim2.new(1, -70, 0.5, -14)
maxBox.BackgroundColor3 = C.input
maxBox.BorderSizePixel = 0
maxBox.Text = "100"
maxBox.TextColor3 = C.txt
maxBox.Font = Enum.Font.GothamBold
maxBox.TextSize = 13
maxBox.ClearTextOnFocus = false
Instance.new("UICorner", maxBox).CornerRadius = UDim.new(0, 6)
local ms = Instance.new("UIStroke", maxBox); ms.Color = C.border; ms.Thickness = 1
local mp2 = Instance.new("UIPadding", maxBox); mp2.PaddingLeft = UDim.new(0, 8)
maxBox.Focused:Connect(function() ms.Color = C.accent end)
maxBox.FocusLost:Connect(function()
    ms.Color = C.border
    local v = tonumber(maxBox.Text)
    if v then
        cfg.maxItems = math.clamp(v, 1, 100)
        maxBox.Text = tostring(cfg.maxItems)
    else
        maxBox.Text = tostring(cfg.maxItems)
    end
end)

sectionLabel("About", 3, sp)

local aboutCard = Instance.new("Frame")
aboutCard.Size = UDim2.new(1, 0, 0, 80)
aboutCard.BackgroundColor3 = C.card
aboutCard.BorderSizePixel = 0
aboutCard.LayoutOrder = 4
aboutCard.Parent = sp
Instance.new("UICorner", aboutCard).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", aboutCard).Color = C.border

local aboutLbl = Instance.new("TextLabel", aboutCard)
aboutLbl.Size = UDim2.new(1, -20, 1, 0)
aboutLbl.Position = UDim2.new(0, 12, 0, 0)
aboutLbl.BackgroundTransparency = 1
aboutLbl.Text = "Auto Send Mailbox  v1.0\nBatch sends items via Mailbox network.\nMax 20 unique items per batch.\nItem limit per entry capped at 100."
aboutLbl.TextColor3 = C.txtMuted
aboutLbl.Font = Enum.Font.Gotham
aboutLbl.TextSize = 11
aboutLbl.TextXAlignment = Enum.TextXAlignment.Left
aboutLbl.TextYAlignment = Enum.TextYAlignment.Center

-- ═══════════════════════════════════════════════════════════════════════════════
-- BUTTON LOGIC
-- ═══════════════════════════════════════════════════════════════════════════════
local autoSendRunning  = false
local autoSendThread   = nil
local autoClaimRunning = false
local autoClaimThread  = nil

sendOnceBtn.MouseButton1Click:Connect(function()
    rebuildCfgItems()
    cfg.username = usernameBox.Text
    cfg.note     = noteBox.Text
    log("Sending...")
    task.spawn(function()
        local ok, err = pcall(function() doSend(log) end)
        if not ok then log("Error: "..tostring(err), true) end
    end)
end)

local function stopAutoSend()
    autoSendRunning = false
    if autoSendThread then task.cancel(autoSendThread) autoSendThread = nil end
    autoSendBtn.Text = "⏵  Start Auto Send"
    autoSendBtn.BackgroundColor3 = C.green
    log("Auto send stopped.")
end

local function startAutoSend()
    autoSendRunning = true
    autoSendBtn.Text = "⏹  Stop Auto Send"
    autoSendBtn.BackgroundColor3 = C.red
    autoSendThread = task.spawn(function()
        while autoSendRunning do
            rebuildCfgItems()
            cfg.username = usernameBox.Text
            cfg.note     = noteBox.Text
            cfg.interval = tonumber(intBox.Text) or 10
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
    log("Claiming mail...")
    task.spawn(function() pcall(function() doClaim(log) end) end)
end)

local function syncAutoClaim()
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
        syncAutoClaim()
        task.wait(0.5)
    end
end)

log("Ready — fill in details and send.")
