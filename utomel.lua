-- Auto Send Mailbox GUI v2.0
-- Paste into your executor

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- ─── Config ───────────────────────────────────────────────────────────────────
local cfg = {
    username   = "",
    items      = {},
    note       = "",
    interval   = 10,
    maxItems   = 100,
    webhook    = "",
    autoSave   = false,
    winW       = 520,
    winH       = 460,
}

-- Auto-save key (DataStore not available in exploit context, use getgenv)
local SAVE_KEY = "ASM_SavedConfig"

local function saveConfig()
    if not cfg.autoSave then return end
    local data = {
        username = cfg.username,
        items    = cfg.items,
        note     = cfg.note,
        interval = cfg.interval,
        maxItems = cfg.maxItems,
        webhook  = cfg.webhook,
        winW     = cfg.winW,
        winH     = cfg.winH,
    }
    getgenv()[SAVE_KEY] = data
end

local function loadConfig()
    local data = getgenv()[SAVE_KEY]
    if type(data) == "table" then
        cfg.username = data.username or ""
        cfg.items    = type(data.items)=="table" and data.items or {}
        cfg.note     = data.note or ""
        cfg.interval = data.interval or 10
        cfg.maxItems = data.maxItems or 100
        cfg.webhook  = data.webhook or ""
        cfg.winW     = data.winW or 520
        cfg.winH     = data.winH or 460
        return true
    end
    return false
end

-- ─── Core game logic ──────────────────────────────────────────────────────────
local STACK = {
    Sprinklers=1,WateringCans=1,Mushrooms=1,Gnomes=1,Raccoons=1,Crates=1,
    SeedPacks=1,Trowels=1,Props=1,Seeds=1,HarvestedFruits=1,Flashbangs=1,EmptyPots=1,
}

local function getNet() return require(RS:WaitForChild("SharedModules"):WaitForChild("Networking")) end
local function getPS()  return require(RS:WaitForChild("ClientModules"):WaitForChild("PlayerStateClient")) end
local function getInv()
    local ok,r = pcall(function() return getPS():WaitForLocalReplica(5) end)
    return ok and r and r.Data and type(r.Data.Inventory)=="table" and r.Data.Inventory
end

local function hasItemInInv(inv, name)
    if type(inv.Pets)=="table" then
        for _,p in pairs(inv.Pets) do
            if type(p)=="table" and p.Id and not p.Equipped and tostring(p.Name)==name then
                return true
            end
        end
    end
    for cat in pairs(STACK) do
        local t = inv[cat]
        if type(t)=="table" and type(t[name])=="number" and t[name]>0 then return true end
    end
    return false
end

local function buildBatch(inv, items)
    local out, max = {}, 20
    for _,entry in ipairs(items) do
        local name = entry.name
        local amt  = math.min(math.max(1, math.floor(tonumber(entry.amount) or 1)), cfg.maxItems)
        if #out >= max then break end
        if not hasItemInInv(inv, name) then continue end -- skip missing items cleanly
        local want = amt
        if type(inv.Pets)=="table" then
            for key,p in pairs(inv.Pets) do
                if want<=0 or #out>=max then break end
                if type(p)=="table" and p.Id and not p.Equipped and tostring(p.Name)==name then
                    out[#out+1]={Category="Pets",ItemKey=key,Count=1}
                    want-=1
                end
            end
        end
        if want>0 then
            for cat in pairs(STACK) do
                local t=inv[cat]
                if type(t)=="table" and type(t[name])=="number" and t[name]>0 then
                    out[#out+1]={Category=cat,ItemKey=name,Count=math.min(want,t[name])}
                    break
                end
            end
        end
    end
    return out
end

local function sendWebhook(username, items, success)
    if cfg.webhook=="" then return end
    local lines = {}
    for _,e in ipairs(items) do
        table.insert(lines, e.name.." ×"..tostring(e.amount))
    end
    local status = success and "✅ Sent" or "❌ Failed"
    local body = HttpService:JSONEncode({
        content = status.." → **"..username.."**\n"..table.concat(lines,"\n")
    })
    pcall(function()
        local req = (syn and syn.request) or (http and http.request) or request
        if req then
            req({Url=cfg.webhook, Method="POST", Headers={["Content-Type"]="application/json"}, Body=body})
        end
    end)
end

-- ─── Output log entries ───────────────────────────────────────────────────────
local outputLog = {}  -- { time, to, items, success, skipped }
local MAX_LOG = 10
local outputUpdateFn = nil  -- set later

local function addOutputEntry(to, items, skipped, success)
    local now = os.date("%H:%M:%S")
    local entry = {time=now, to=to, items=items, skipped=skipped, success=success}
    table.insert(outputLog, 1, entry)
    if #outputLog > MAX_LOG then table.remove(outputLog, #outputLog) end
    if outputUpdateFn then outputUpdateFn() end
end

local function doSend(logFn)
    if cfg.username=="" then logFn("⚠  No username set.", true) return false end
    if #cfg.items==0 then logFn("⚠  No items in list.", true) return false end
    local inv = getInv()
    if not inv then logFn("⚠  Could not read inventory.", true) return false end

    -- figure out which items exist vs missing
    local available, skipped = {}, {}
    for _,e in ipairs(cfg.items) do
        if hasItemInInv(inv, e.name) then
            table.insert(available, e)
        else
            table.insert(skipped, e.name)
        end
    end

    if #available==0 then
        logFn("⚠  None of your listed items found in inventory.", true)
        addOutputEntry(cfg.username, {}, skipped, false)
        return false
    end

    local batch = buildBatch(inv, available)
    if #batch==0 then logFn("⚠  Build batch failed.", true) return false end

    local Net = getNet()
    local ok,uid = pcall(function() return Net.Mailbox.LookupPlayer:Fire(cfg.username) end)
    if not ok or type(uid)~="number" or uid<=0 then
        logFn("⚠  Player lookup failed.", true)
        addOutputEntry(cfg.username, available, skipped, false)
        return false
    end

    local ok2,success = pcall(function() return Net.Mailbox.SendBatch:Fire(uid, batch, cfg.note or "") end)
    local worked = success==true
    if worked then
        local names = {}
        for _,e in ipairs(available) do table.insert(names, e.name.." ×"..e.amount) end
        logFn("✓  Sent to "..cfg.username..(#skipped>0 and "  (skipped "..#skipped..")" or ""))
        sendWebhook(cfg.username, available, true)
    else
        logFn("✗  Send failed.", true)
        sendWebhook(cfg.username, available, false)
    end
    addOutputEntry(cfg.username, available, skipped, worked)
    saveConfig()
    return worked
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- GUI
-- ═══════════════════════════════════════════════════════════════════════════════
local gui = Instance.new("ScreenGui")
gui.Name = "AutoSendMailbox"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Theme
local T = {
    bg       = Color3.fromRGB(13, 13, 20),
    sidebar  = Color3.fromRGB(18, 18, 28),
    surface  = Color3.fromRGB(22, 22, 36),
    card     = Color3.fromRGB(28, 28, 46),
    cardAlt  = Color3.fromRGB(24, 24, 40),
    input    = Color3.fromRGB(16, 16, 28),
    border   = Color3.fromRGB(48, 48, 72),
    borderHi = Color3.fromRGB(80, 100, 200),
    accent   = Color3.fromRGB(100, 140, 255),
    accentGl = Color3.fromRGB(130, 165, 255),
    green    = Color3.fromRGB(55, 200, 110),
    greenDk  = Color3.fromRGB(35, 150, 75),
    red      = Color3.fromRGB(220, 65, 65),
    redDk    = Color3.fromRGB(160, 40, 40),
    orange   = Color3.fromRGB(230, 150, 50),
    purple   = Color3.fromRGB(155, 85, 240),
    txt      = Color3.fromRGB(230, 230, 250),
    txtSub   = Color3.fromRGB(160, 160, 200),
    txtMute  = Color3.fromRGB(90, 90, 130),
    tagBg    = Color3.fromRGB(30, 30, 52),
    badgeBg  = Color3.fromRGB(28, 48, 100),
    badgeTxt = Color3.fromRGB(130, 185, 255),
}

-- ─── Main window ──────────────────────────────────────────────────────────────
local win = Instance.new("Frame")
win.Name = "Window"
win.Size = UDim2.new(0, cfg.winW, 0, cfg.winH)
win.Position = UDim2.new(0.5, -cfg.winW/2, 0.5, -cfg.winH/2)
win.BackgroundColor3 = T.bg
win.BorderSizePixel = 0
win.Active = true
win.Draggable = true
win.ClipsDescendants = true
win.Parent = gui
Instance.new("UICorner", win).CornerRadius = UDim.new(0, 12)

local winStroke = Instance.new("UIStroke", win)
winStroke.Color = T.border
winStroke.Thickness = 1.5

-- Glow effect frame
local glowFrame = Instance.new("Frame", win)
glowFrame.Size = UDim2.new(1, 0, 0, 2)
glowFrame.Position = UDim2.new(0, 0, 0, 0)
glowFrame.BackgroundColor3 = T.accent
glowFrame.BorderSizePixel = 0
glowFrame.ZIndex = 5
local glowGrad = Instance.new("UIGradient", glowFrame)
glowGrad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(100,140,255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(155,85,240)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(55,200,110)),
}

-- ─── Title bar ────────────────────────────────────────────────────────────────
local titleH = 42
local titleBar = Instance.new("Frame", win)
titleBar.Size = UDim2.new(1, 0, 0, titleH)
titleBar.BackgroundColor3 = T.surface
titleBar.BorderSizePixel = 0
titleBar.ZIndex = 4

local tbFix = Instance.new("Frame", titleBar)
tbFix.Size = UDim2.new(1,0,0,12)
tbFix.Position = UDim2.new(0,0,1,-12)
tbFix.BackgroundColor3 = T.surface
tbFix.BorderSizePixel = 0

Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0,12)

-- Pill icon
local pillIcon = Instance.new("Frame", titleBar)
pillIcon.Size = UDim2.new(0, 24, 0, 16)
pillIcon.Position = UDim2.new(0, 12, 0.5, -8)
pillIcon.BackgroundColor3 = T.accent
pillIcon.BorderSizePixel = 0
Instance.new("UICorner", pillIcon).CornerRadius = UDim.new(1,0)
local pillGrad = Instance.new("UIGradient", pillIcon)
pillGrad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, T.accent),
    ColorSequenceKeypoint.new(1, T.purple),
}

local titleLbl = Instance.new("TextLabel", titleBar)
titleLbl.Size = UDim2.new(1,-110,1,0)
titleLbl.Position = UDim2.new(0,44,0,0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "Auto Send Mailbox"
titleLbl.TextColor3 = T.txt
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 14
titleLbl.TextXAlignment = Enum.TextXAlignment.Left

-- Title buttons
local function makeTitleBtn(text, color, xOff)
    local b = Instance.new("TextButton", titleBar)
    b.Size = UDim2.new(0,26,0,26)
    b.Position = UDim2.new(1,xOff,0.5,-13)
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,6)
    b.MouseEnter:Connect(function()
        TweenService:Create(b,TweenInfo.new(0.12),{BackgroundColor3=color:Lerp(Color3.new(1,1,1),0.15)}):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b,TweenInfo.new(0.12),{BackgroundColor3=color}):Play()
    end)
    return b
end

local hideBtn  = makeTitleBtn("−", Color3.fromRGB(60,130,65), -64)
local closeBtn = makeTitleBtn("✕", T.red, -32)
closeBtn.MouseButton1Click:Connect(function() saveConfig() gui:Destroy() end)

-- Mini icon
local miniBtn = Instance.new("TextButton", gui)
miniBtn.Size = UDim2.new(0,40,0,40)
miniBtn.Position = UDim2.new(0,12,0.5,-20)
miniBtn.BackgroundColor3 = T.accent
miniBtn.Text = "📬"
miniBtn.TextSize = 20
miniBtn.Font = Enum.Font.GothamBold
miniBtn.BorderSizePixel = 0
miniBtn.Visible = false
miniBtn.ZIndex = 20
Instance.new("UICorner", miniBtn).CornerRadius = UDim.new(0,10)
local miniStroke = Instance.new("UIStroke", miniBtn)
miniStroke.Color = T.accentGl
miniStroke.Thickness = 1.5

local guiVisible = true
hideBtn.MouseButton1Click:Connect(function()
    guiVisible = not guiVisible
    win.Visible = guiVisible
    miniBtn.Visible = not guiVisible
end)
miniBtn.MouseButton1Click:Connect(function()
    guiVisible = true
    win.Visible = true
    miniBtn.Visible = false
end)

-- ─── Layout: sidebar + content ────────────────────────────────────────────────
local SIDEBAR_W = 130

local sidebar = Instance.new("Frame", win)
sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, -titleH)
sidebar.Position = UDim2.new(0, 0, 0, titleH)
sidebar.BackgroundColor3 = T.sidebar
sidebar.BorderSizePixel = 0
sidebar.ZIndex = 2

local sideStroke = Instance.new("UIStroke", sidebar)
sideStroke.Color = T.border
sideStroke.Thickness = 1

local sideLayout = Instance.new("UIListLayout", sidebar)
sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
sideLayout.Padding = UDim.new(0,4)

local sidePad = Instance.new("UIPadding", sidebar)
sidePad.PaddingTop    = UDim.new(0,10)
sidePad.PaddingLeft   = UDim.new(0,8)
sidePad.PaddingRight  = UDim.new(0,8)
sidePad.PaddingBottom = UDim.new(0,8)

-- Menu label
local menuLbl = Instance.new("TextLabel", sidebar)
menuLbl.Size = UDim2.new(1,0,0,16)
menuLbl.BackgroundTransparency = 1
menuLbl.Text = "MENU"
menuLbl.TextColor3 = T.txtMute
menuLbl.Font = Enum.Font.GothamSemibold
menuLbl.TextSize = 9
menuLbl.TextXAlignment = Enum.TextXAlignment.Left
menuLbl.LayoutOrder = 0

local contentArea = Instance.new("Frame", win)
contentArea.Size = UDim2.new(1,-SIDEBAR_W,1,-titleH)
contentArea.Position = UDim2.new(0,SIDEBAR_W,0,titleH)
contentArea.BackgroundColor3 = T.bg
contentArea.BorderSizePixel = 0
contentArea.ClipsDescendants = true

-- ─── Tab factory ──────────────────────────────────────────────────────────────
local allTabs = {}
local activeTab = nil

local function makeTabBtn(icon, label, order)
    local btn = Instance.new("TextButton", sidebar)
    btn.Size = UDim2.new(1,0,0,40)
    btn.BackgroundColor3 = T.sidebar
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.LayoutOrder = order
    btn.AutoButtonColor = false
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)

    local accentBar = Instance.new("Frame", btn)
    accentBar.Size = UDim2.new(0,3,0,22)
    accentBar.Position = UDim2.new(0,0,0.5,-11)
    accentBar.BackgroundColor3 = T.accent
    accentBar.BorderSizePixel = 0
    accentBar.Visible = false
    Instance.new("UICorner", accentBar).CornerRadius = UDim.new(0,2)

    local iconLbl = Instance.new("TextLabel", btn)
    iconLbl.Size = UDim2.new(0,26,1,0)
    iconLbl.Position = UDim2.new(0,10,0,0)
    iconLbl.BackgroundTransparency = 1
    iconLbl.Text = icon
    iconLbl.TextSize = 15
    iconLbl.Font = Enum.Font.GothamBold
    iconLbl.TextColor3 = T.txtMute

    local nameLbl = Instance.new("TextLabel", btn)
    nameLbl.Size = UDim2.new(1,-40,1,0)
    nameLbl.Position = UDim2.new(0,38,0,0)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = label
    nameLbl.Font = Enum.Font.GothamSemibold
    nameLbl.TextSize = 12
    nameLbl.TextColor3 = T.txtMute
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left

    -- Page
    local page = Instance.new("ScrollingFrame", contentArea)
    page.Size = UDim2.new(1,0,1,0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 6
    page.ScrollBarImageColor3 = T.border
    page.CanvasSize = UDim2.new(0,0,0,0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false

    local pl = Instance.new("UIListLayout", page)
    pl.SortOrder = Enum.SortOrder.LayoutOrder
    pl.Padding = UDim.new(0,10)

    local pp = Instance.new("UIPadding", page)
    pp.PaddingTop    = UDim.new(0,14)
    pp.PaddingBottom = UDim.new(0,20)
    pp.PaddingLeft   = UDim.new(0,12)
    pp.PaddingRight  = UDim.new(0,12)

    local tabData = {btn=btn, page=page, bar=accentBar, icon=iconLbl, name=nameLbl}
    table.insert(allTabs, tabData)

    btn.MouseButton1Click:Connect(function()
        if activeTab then
            TweenService:Create(activeTab.btn,TweenInfo.new(0.18),{BackgroundColor3=T.sidebar}):Play()
            activeTab.bar.Visible = false
            activeTab.icon.TextColor3 = T.txtMute
            activeTab.name.TextColor3 = T.txtMute
            activeTab.page.Visible = false
        end
        activeTab = tabData
        TweenService:Create(btn,TweenInfo.new(0.18),{BackgroundColor3=T.card}):Play()
        accentBar.Visible = true
        iconLbl.TextColor3 = T.txt
        nameLbl.TextColor3 = T.txt
        page.Visible = true
    end)

    return tabData
end

local mailTab    = makeTabBtn("✉️",  "Mail",     1)
local outputTab  = makeTabBtn("📋",  "Output",   2)
local settingTab = makeTabBtn("⚙️",  "Settings", 3)

-- version at sidebar bottom
local verLbl = Instance.new("TextLabel", sidebar)
verLbl.Size = UDim2.new(1,0,0,14)
verLbl.AnchorPoint = Vector2.new(0,1)
verLbl.Position = UDim2.new(0,0,1,-4)
verLbl.BackgroundTransparency = 1
verLbl.Text = "v2.0"
verLbl.TextColor3 = T.txtMute
verLbl.Font = Enum.Font.Gotham
verLbl.TextSize = 9
verLbl.TextXAlignment = Enum.TextXAlignment.Center
verLbl.ZIndex = 3

-- Activate mail tab
mailTab.btn.BackgroundColor3 = T.card
mailTab.bar.Visible = true
mailTab.icon.TextColor3 = T.txt
mailTab.name.TextColor3 = T.txt
mailTab.page.Visible = true
activeTab = mailTab

-- ─── Widget helpers ───────────────────────────────────────────────────────────
local function secLabel(txt, order, page)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1,0,0,16)
    f.BackgroundTransparency = 1
    f.LayoutOrder = order
    f.Parent = page
    local l = Instance.new("TextLabel",f)
    l.Size = UDim2.new(1,0,1,0)
    l.BackgroundTransparency = 1
    l.Text = txt:upper()
    l.TextColor3 = T.txtMute
    l.Font = Enum.Font.GothamSemibold
    l.TextSize = 9
    l.TextXAlignment = Enum.TextXAlignment.Left
    return f
end

local function mkInput(ph, order, page, h)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1,0,0,h or 36)
    box.BackgroundColor3 = T.input
    box.BorderSizePixel = 0
    box.Text = ""
    box.PlaceholderText = ph
    box.PlaceholderColor3 = T.txtMute
    box.TextColor3 = T.txt
    box.Font = Enum.Font.Gotham
    box.TextSize = 13
    box.ClearTextOnFocus = false
    box.LayoutOrder = order
    box.Parent = page
    Instance.new("UICorner", box).CornerRadius = UDim.new(0,8)
    local st = Instance.new("UIStroke",box); st.Color=T.border; st.Thickness=1
    local pd = Instance.new("UIPadding",box); pd.PaddingLeft=UDim.new(0,12)
    box.Focused:Connect(function()
        TweenService:Create(st,TweenInfo.new(0.15),{Color=T.accent}):Play()
    end)
    box.FocusLost:Connect(function()
        TweenService:Create(st,TweenInfo.new(0.15),{Color=T.border}):Play()
    end)
    return box
end

local function mkBtn(txt, color, order, page)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,38)
    btn.BackgroundColor3 = color
    btn.BorderSizePixel = 0
    btn.Text = txt
    btn.TextColor3 = Color3.new(1,1,1)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.LayoutOrder = order
    btn.Parent = page
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,9)
    -- gradient overlay
    local grad = Instance.new("UIGradient", btn)
    grad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.new(1,1,1):Lerp(color,0.7)),
        ColorSequenceKeypoint.new(1, color),
    }
    grad.Rotation = 90
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn,TweenInfo.new(0.15),{BackgroundColor3=color:Lerp(Color3.new(1,1,1),0.1)}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn,TweenInfo.new(0.15),{BackgroundColor3=color}):Play()
    end)
    btn.MouseButton1Down:Connect(function()
        TweenService:Create(btn,TweenInfo.new(0.08),{BackgroundColor3=color:Lerp(Color3.new(0,0,0),0.15)}):Play()
    end)
    btn.MouseButton1Up:Connect(function()
        TweenService:Create(btn,TweenInfo.new(0.08),{BackgroundColor3=color}):Play()
    end)
    return btn
end

local function mkToggle(labelTxt, order, page)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,42)
    row.BackgroundColor3 = T.card
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = page
    Instance.new("UICorner",row).CornerRadius = UDim.new(0,9)
    local st = Instance.new("UIStroke",row); st.Color=T.border; st.Thickness=1

    local lbl = Instance.new("TextLabel",row)
    lbl.Size = UDim2.new(1,-68,1,0)
    lbl.Position = UDim2.new(0,14,0,0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelTxt
    lbl.TextColor3 = T.txt
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local pill = Instance.new("Frame",row)
    pill.Size = UDim2.new(0,46,0,26)
    pill.Position = UDim2.new(1,-56,0.5,-13)
    pill.BackgroundColor3 = T.border
    pill.BorderSizePixel = 0
    Instance.new("UICorner",pill).CornerRadius = UDim.new(1,0)

    local thumb = Instance.new("Frame",pill)
    thumb.Size = UDim2.new(0,20,0,20)
    thumb.Position = UDim2.new(0,3,0.5,-10)
    thumb.BackgroundColor3 = T.txtMute
    thumb.BorderSizePixel = 0
    Instance.new("UICorner",thumb).CornerRadius = UDim.new(1,0)

    local state = false
    local hit = Instance.new("TextButton",row)
    hit.Size = UDim2.new(1,0,1,0)
    hit.BackgroundTransparency = 1
    hit.Text = ""

    local function refresh()
        if state then
            TweenService:Create(pill,TweenInfo.new(0.2),{BackgroundColor3=T.accent}):Play()
            TweenService:Create(thumb,TweenInfo.new(0.2),{Position=UDim2.new(1,-23,0.5,-10),BackgroundColor3=Color3.new(1,1,1)}):Play()
        else
            TweenService:Create(pill,TweenInfo.new(0.2),{BackgroundColor3=T.border}):Play()
            TweenService:Create(thumb,TweenInfo.new(0.2),{Position=UDim2.new(0,3,0.5,-10),BackgroundColor3=T.txtMute}):Play()
        end
    end
    hit.MouseButton1Click:Connect(function() state=not state refresh() end)
    return row, function() return state end, function(v) state=v refresh() end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- MAIL PAGE
-- ═══════════════════════════════════════════════════════════════════════════════
local mp = mailTab.page

secLabel("Recipient", 1, mp)
local usernameBox = mkInput("Roblox username", 2, mp)
usernameBox.FocusLost:Connect(function() cfg.username=usernameBox.Text saveConfig() end)

-- ─── Items card ───────────────────────────────────────────────────────────────
secLabel("Items to send", 3, mp)

local itemCard = Instance.new("Frame")
itemCard.Size = UDim2.new(1,0,0,10)
itemCard.AutomaticSize = Enum.AutomaticSize.Y
itemCard.BackgroundColor3 = T.card
itemCard.BorderSizePixel = 0
itemCard.LayoutOrder = 4
itemCard.Parent = mp
Instance.new("UICorner",itemCard).CornerRadius = UDim.new(0,10)
local icStroke = Instance.new("UIStroke",itemCard); icStroke.Color=T.border; icStroke.Thickness=1

local icInner = Instance.new("UIListLayout",itemCard)
icInner.SortOrder = Enum.SortOrder.LayoutOrder
icInner.Padding = UDim.new(0,0)

-- Input row
local addRow = Instance.new("Frame",itemCard)
addRow.Size = UDim2.new(1,0,0,50)
addRow.BackgroundTransparency = 1
addRow.LayoutOrder = 1

local nameIn = Instance.new("TextBox",addRow)
nameIn.Size = UDim2.new(1,-96,0,32)
nameIn.Position = UDim2.new(0,10,0.5,-16)
nameIn.BackgroundColor3 = T.input
nameIn.BorderSizePixel = 0
nameIn.PlaceholderText = "Item name"
nameIn.PlaceholderColor3 = T.txtMute
nameIn.Text = ""
nameIn.TextColor3 = T.txt
nameIn.Font = Enum.Font.Gotham
nameIn.TextSize = 13
nameIn.ClearTextOnFocus = false
Instance.new("UICorner",nameIn).CornerRadius = UDim.new(0,7)
local ns = Instance.new("UIStroke",nameIn); ns.Color=T.border; ns.Thickness=1
local np = Instance.new("UIPadding",nameIn); np.PaddingLeft=UDim.new(0,10)
nameIn.Focused:Connect(function() TweenService:Create(ns,TweenInfo.new(0.15),{Color=T.accent}):Play() end)
nameIn.FocusLost:Connect(function() TweenService:Create(ns,TweenInfo.new(0.15),{Color=T.border}):Play() end)

local amtIn = Instance.new("TextBox",addRow)
amtIn.Size = UDim2.new(0,48,0,32)
amtIn.Position = UDim2.new(1,-82,0.5,-16)
amtIn.BackgroundColor3 = T.input
amtIn.BorderSizePixel = 0
amtIn.PlaceholderText = "Qty"
amtIn.PlaceholderColor3 = T.txtMute
amtIn.Text = ""
amtIn.TextColor3 = T.txt
amtIn.Font = Enum.Font.GothamBold
amtIn.TextSize = 13
amtIn.ClearTextOnFocus = false
Instance.new("UICorner",amtIn).CornerRadius = UDim.new(0,7)
local as_ = Instance.new("UIStroke",amtIn); as_.Color=T.border; as_.Thickness=1
local ap = Instance.new("UIPadding",amtIn); ap.PaddingLeft=UDim.new(0,8)
amtIn.Focused:Connect(function() TweenService:Create(as_,TweenInfo.new(0.15),{Color=T.accent}):Play() end)
amtIn.FocusLost:Connect(function() TweenService:Create(as_,TweenInfo.new(0.15),{Color=T.border}):Play() end)

local addBtn = Instance.new("TextButton",addRow)
addBtn.Size = UDim2.new(0,32,0,32)
addBtn.Position = UDim2.new(1,-38,0.5,-16)
addBtn.BackgroundColor3 = T.green
addBtn.Text = "+"
addBtn.TextColor3 = Color3.new(1,1,1)
addBtn.Font = Enum.Font.GothamBold
addBtn.TextSize = 18
addBtn.BorderSizePixel = 0
Instance.new("UICorner",addBtn).CornerRadius = UDim.new(0,7)

-- divider
local addDiv = Instance.new("Frame",itemCard)
addDiv.Size = UDim2.new(1,-20,0,1)
addDiv.Position = UDim2.new(0,10,0,0)
addDiv.BackgroundColor3 = T.border
addDiv.BorderSizePixel = 0
addDiv.LayoutOrder = 2

-- Item list
local itemList = Instance.new("Frame",itemCard)
itemList.Name = "ItemList"
itemList.Size = UDim2.new(1,0,0,0)
itemList.AutomaticSize = Enum.AutomaticSize.Y
itemList.BackgroundTransparency = 1
itemList.BorderSizePixel = 0
itemList.LayoutOrder = 3

local ilLayout = Instance.new("UIListLayout",itemList)
ilLayout.SortOrder = Enum.SortOrder.LayoutOrder
ilLayout.Padding = UDim.new(0,0)

local emptyLbl = Instance.new("TextLabel",itemList)
emptyLbl.Size = UDim2.new(1,0,0,34)
emptyLbl.BackgroundTransparency = 1
emptyLbl.Text = "No items added yet."
emptyLbl.TextColor3 = T.txtMute
emptyLbl.Font = Enum.Font.Gotham
emptyLbl.TextSize = 12
emptyLbl.LayoutOrder = 0

local itemEntries = {}

local statusDots = {}  -- { frame, itemName } for live status

local function refreshEmpty()
    emptyLbl.Visible = #itemEntries==0
end

local function rebuildCfg()
    cfg.items = {}
    for _,e in ipairs(itemEntries) do
        table.insert(cfg.items,{name=e.name,amount=math.min(tonumber(e.amt) or 1, cfg.maxItems)})
    end
end

local function updateItemStatuses(inv)
    for _,sd in ipairs(statusDots) do
        if sd.dot and sd.dot.Parent then
            local has = inv and hasItemInInv(inv, sd.name)
            sd.dot.BackgroundColor3 = has and T.green or T.red
        end
    end
end

local function addItemEntry(name, amt)
    if name=="" then return end
    amt = math.min(math.max(1,math.floor(tonumber(amt) or 1)), cfg.maxItems)

    local idx = #itemEntries+1
    local row = Instance.new("Frame",itemList)
    row.Size = UDim2.new(1,0,0,36)
    row.BackgroundColor3 = (idx%2==0) and T.card or T.tagBg
    row.BorderSizePixel = 0
    row.LayoutOrder = idx

    -- number
    local numLbl = Instance.new("TextLabel",row)
    numLbl.Size = UDim2.new(0,22,1,0)
    numLbl.Position = UDim2.new(0,8,0,0)
    numLbl.BackgroundTransparency = 1
    numLbl.Text = tostring(idx).."."
    numLbl.TextColor3 = T.txtMute
    numLbl.Font = Enum.Font.GothamSemibold
    numLbl.TextSize = 11
    numLbl.TextXAlignment = Enum.TextXAlignment.Right

    -- status dot (green/red depending on inventory)
    local dot = Instance.new("Frame",row)
    dot.Size = UDim2.new(0,7,0,7)
    dot.Position = UDim2.new(0,34,0.5,-3.5)
    dot.BackgroundColor3 = T.txtMute
    dot.BorderSizePixel = 0
    Instance.new("UICorner",dot).CornerRadius = UDim.new(1,0)

    local nameLbl2 = Instance.new("TextLabel",row)
    nameLbl2.Size = UDim2.new(1,-120,1,0)
    nameLbl2.Position = UDim2.new(0,46,0,0)
    nameLbl2.BackgroundTransparency = 1
    nameLbl2.Text = name
    nameLbl2.TextColor3 = T.txt
    nameLbl2.Font = Enum.Font.GothamSemibold
    nameLbl2.TextSize = 13
    nameLbl2.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl2.TextTruncate = Enum.TextTruncate.AtEnd

    local badge = Instance.new("Frame",row)
    badge.Size = UDim2.new(0,44,0,22)
    badge.Position = UDim2.new(1,-72,0.5,-11)
    badge.BackgroundColor3 = T.badgeBg
    badge.BorderSizePixel = 0
    Instance.new("UICorner",badge).CornerRadius = UDim.new(0,5)

    local badgeLbl = Instance.new("TextLabel",badge)
    badgeLbl.Size = UDim2.new(1,0,1,0)
    badgeLbl.BackgroundTransparency = 1
    badgeLbl.Text = "×"..tostring(amt)
    badgeLbl.TextColor3 = T.badgeTxt
    badgeLbl.Font = Enum.Font.GothamBold
    badgeLbl.TextSize = 11

    local remBtn = Instance.new("TextButton",row)
    remBtn.Size = UDim2.new(0,24,0,24)
    remBtn.Position = UDim2.new(1,-26,0.5,-12)
    remBtn.BackgroundColor3 = Color3.fromRGB(70,25,25)
    remBtn.Text = "✕"
    remBtn.TextColor3 = Color3.fromRGB(220,90,90)
    remBtn.Font = Enum.Font.GothamBold
    remBtn.TextSize = 10
    remBtn.BorderSizePixel = 0
    Instance.new("UICorner",remBtn).CornerRadius = UDim.new(0,5)

    local entry = {frame=row, name=name, amt=amt, dot=dot}
    table.insert(itemEntries, entry)
    table.insert(statusDots, {dot=dot, name=name})
    refreshEmpty()
    rebuildCfg()

    remBtn.MouseButton1Click:Connect(function()
        row:Destroy()
        for i,e in ipairs(itemEntries) do if e==entry then table.remove(itemEntries,i) break end end
        for i,sd in ipairs(statusDots) do if sd.dot==dot then table.remove(statusDots,i) break end end
        -- renumber remaining
        for i2,e2 in ipairs(itemEntries) do
            if e2.frame and e2.frame:FindFirstChildWhichIsA("TextLabel") then
                local nl = e2.frame:FindFirstChild("TextLabel") -- numLbl
                -- find via children
                for _,ch in ipairs(e2.frame:GetChildren()) do
                    if ch:IsA("TextLabel") and ch.TextXAlignment==Enum.TextXAlignment.Right then
                        ch.Text = tostring(i2).."."
                        break
                    end
                end
            end
        end
        rebuildCfg()
        refreshEmpty()
        saveConfig()
    end)

    saveConfig()
    return entry
end

addBtn.MouseButton1Click:Connect(function()
    local n = nameIn.Text:match("^%s*(.-)%s*$")
    local a = amtIn.Text
    if n~="" then
        addItemEntry(n,a)
        nameIn.Text=""
        amtIn.Text=""
    end
end)
nameIn.FocusLost:Connect(function(enter)
    if enter then
        local n=nameIn.Text:match("^%s*(.-)%s*$")
        if n~="" then addItemEntry(n,amtIn.Text) nameIn.Text="" amtIn.Text="" end
    end
end)

-- Note
secLabel("Note (optional)", 5, mp)
local noteBox = mkInput("Mail note...", 6, mp)
noteBox.FocusLost:Connect(function() cfg.note=noteBox.Text saveConfig() end)

-- Interval
secLabel("Auto send interval", 7, mp)
local intRow = Instance.new("Frame")
intRow.Size = UDim2.new(1,0,0,36)
intRow.BackgroundTransparency = 1
intRow.LayoutOrder = 8
intRow.Parent = mp

local intBox = Instance.new("TextBox",intRow)
intBox.Size = UDim2.new(0,80,1,0)
intBox.BackgroundColor3 = T.input
intBox.BorderSizePixel = 0
intBox.Text = "10"
intBox.TextColor3 = T.txt
intBox.Font = Enum.Font.GothamBold
intBox.TextSize = 14
intBox.ClearTextOnFocus = false
Instance.new("UICorner",intBox).CornerRadius = UDim.new(0,8)
local intSt = Instance.new("UIStroke",intBox); intSt.Color=T.border; intSt.Thickness=1
local intPd = Instance.new("UIPadding",intBox); intPd.PaddingLeft=UDim.new(0,12)
intBox.Focused:Connect(function() TweenService:Create(intSt,TweenInfo.new(0.15),{Color=T.accent}):Play() end)
intBox.FocusLost:Connect(function()
    TweenService:Create(intSt,TweenInfo.new(0.15),{Color=T.border}):Play()
    local v=tonumber(intBox.Text)
    if v and v>=1 then cfg.interval=v else intBox.Text=tostring(cfg.interval) end
    saveConfig()
end)

local intLbl = Instance.new("TextLabel",intRow)
intLbl.Size = UDim2.new(1,-90,1,0)
intLbl.Position = UDim2.new(0,88,0,0)
intLbl.BackgroundTransparency = 1
intLbl.Text = "seconds between sends"
intLbl.TextColor3 = T.txtMute
intLbl.Font = Enum.Font.Gotham
intLbl.TextSize = 12
intLbl.TextXAlignment = Enum.TextXAlignment.Left

-- Toggle
local _, getAutoSend, setAutoSend = mkToggle("Auto Send", 9, mp)

-- Buttons
local sendOnceBtn = mkBtn("▶   Send Once",       T.accent, 10, mp)
local autoSendBtn = mkBtn("⏵   Start Auto Send", T.green,  11, mp)
local claimNowBtn = mkBtn("📥   Claim Mail Now",  T.purple, 12, mp)

-- Log bar
local logBar = Instance.new("Frame")
logBar.Size = UDim2.new(1,0,0,36)
logBar.BackgroundColor3 = T.card
logBar.BorderSizePixel = 0
logBar.LayoutOrder = 13
logBar.Parent = mp
Instance.new("UICorner",logBar).CornerRadius = UDim.new(0,8)
Instance.new("UIStroke",logBar).Color = T.border

local logDot = Instance.new("Frame",logBar)
logDot.Size = UDim2.new(0,8,0,8)
logDot.Position = UDim2.new(0,12,0.5,-4)
logDot.BackgroundColor3 = T.green
logDot.BorderSizePixel = 0
Instance.new("UICorner",logDot).CornerRadius = UDim.new(1,0)

local logLbl = Instance.new("TextLabel",logBar)
logLbl.Size = UDim2.new(1,-30,1,0)
logLbl.Position = UDim2.new(0,28,0,0)
logLbl.BackgroundTransparency = 1
logLbl.Text = "Idle — ready."
logLbl.TextColor3 = T.txtSub
logLbl.Font = Enum.Font.Gotham
logLbl.TextSize = 12
logLbl.TextXAlignment = Enum.TextXAlignment.Left
logLbl.TextTruncate = Enum.TextTruncate.AtEnd

local function log(msg, isErr)
    logLbl.Text = msg
    local col = isErr and T.red or T.green
    TweenService:Create(logDot,TweenInfo.new(0.2),{BackgroundColor3=col}):Play()
    logLbl.TextColor3 = isErr and Color3.fromRGB(240,140,140) or T.txtSub
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- OUTPUT PAGE
-- ═══════════════════════════════════════════════════════════════════════════════
local op = outputTab.page

secLabel("Send history (last 10)", 1, op)

local outListFrame = Instance.new("Frame")
outListFrame.Size = UDim2.new(1,0,0,0)
outListFrame.AutomaticSize = Enum.AutomaticSize.Y
outListFrame.BackgroundTransparency = 1
outListFrame.BorderSizePixel = 0
outListFrame.LayoutOrder = 2
outListFrame.Parent = op

local outLayout = Instance.new("UIListLayout",outListFrame)
outLayout.SortOrder = Enum.SortOrder.LayoutOrder
outLayout.Padding = UDim.new(0,6)

local noHistLbl = Instance.new("TextLabel",outListFrame)
noHistLbl.Size = UDim2.new(1,0,0,40)
noHistLbl.BackgroundTransparency = 1
noHistLbl.Text = "No sends yet."
noHistLbl.TextColor3 = T.txtMute
noHistLbl.Font = Enum.Font.Gotham
noHistLbl.TextSize = 12
noHistLbl.LayoutOrder = 0

local outEntryFrames = {}

local function rebuildOutput()
    for _,f in ipairs(outEntryFrames) do f:Destroy() end
    outEntryFrames = {}
    noHistLbl.Visible = #outputLog==0

    for idx,entry in ipairs(outputLog) do
        local card = Instance.new("Frame",outListFrame)
        card.Size = UDim2.new(1,0,0,0)
        card.AutomaticSize = Enum.AutomaticSize.Y
        card.BackgroundColor3 = T.card
        card.BorderSizePixel = 0
        card.LayoutOrder = idx
        Instance.new("UICorner",card).CornerRadius = UDim.new(0,9)
        local cst = Instance.new("UIStroke",card)
        cst.Color = entry.success and Color3.fromRGB(40,80,50) or Color3.fromRGB(80,30,30)
        cst.Thickness = 1

        local cLayout = Instance.new("UIListLayout",card)
        cLayout.SortOrder = Enum.SortOrder.LayoutOrder
        cLayout.Padding = UDim.new(0,0)

        local cPad = Instance.new("UIPadding",card)
        cPad.PaddingLeft=UDim.new(0,12) cPad.PaddingRight=UDim.new(0,12)
        cPad.PaddingTop=UDim.new(0,8) cPad.PaddingBottom=UDim.new(0,8)

        -- Header row: dot + to + time
        local hdr = Instance.new("Frame",card)
        hdr.Size = UDim2.new(1,0,0,20)
        hdr.BackgroundTransparency = 1
        hdr.LayoutOrder = 1

        local statusDot2 = Instance.new("Frame",hdr)
        statusDot2.Size = UDim2.new(0,9,0,9)
        statusDot2.Position = UDim2.new(0,0,0.5,-4.5)
        statusDot2.BackgroundColor3 = entry.success and T.green or T.red
        statusDot2.BorderSizePixel = 0
        Instance.new("UICorner",statusDot2).CornerRadius = UDim.new(1,0)

        local toLabel = Instance.new("TextLabel",hdr)
        toLabel.Size = UDim2.new(1,-80,1,0)
        toLabel.Position = UDim2.new(0,16,0,0)
        toLabel.BackgroundTransparency = 1
        toLabel.Text = "→ "..entry.to
        toLabel.TextColor3 = T.txt
        toLabel.Font = Enum.Font.GothamBold
        toLabel.TextSize = 13
        toLabel.TextXAlignment = Enum.TextXAlignment.Left

        local timeLbl2 = Instance.new("TextLabel",hdr)
        timeLbl2.Size = UDim2.new(0,70,1,0)
        timeLbl2.Position = UDim2.new(1,-70,0,0)
        timeLbl2.BackgroundTransparency = 1
        timeLbl2.Text = entry.time
        timeLbl2.TextColor3 = T.txtMute
        timeLbl2.Font = Enum.Font.Code
        timeLbl2.TextSize = 11
        timeLbl2.TextXAlignment = Enum.TextXAlignment.Right

        -- Items sent
        if #entry.items > 0 then
            local itemsStr = ""
            for i2,it in ipairs(entry.items) do
                itemsStr = itemsStr..(i2>1 and "  ·  " or "").."  "..it.name.." ×"..it.amount
            end
            local iLbl = Instance.new("TextLabel",card)
            iLbl.Size = UDim2.new(1,0,0,16)
            iLbl.BackgroundTransparency = 1
            iLbl.Text = itemsStr
            iLbl.TextColor3 = T.txtSub
            iLbl.Font = Enum.Font.Gotham
            iLbl.TextSize = 11
            iLbl.TextXAlignment = Enum.TextXAlignment.Left
            iLbl.TextTruncate = Enum.TextTruncate.AtEnd
            iLbl.LayoutOrder = 2
        end

        -- Skipped
        if #entry.skipped > 0 then
            local skLbl = Instance.new("TextLabel",card)
            skLbl.Size = UDim2.new(1,0,0,15)
            skLbl.BackgroundTransparency = 1
            skLbl.Text = "Skipped (not in inv): "..table.concat(entry.skipped,", ")
            skLbl.TextColor3 = T.orange
            skLbl.Font = Enum.Font.Gotham
            skLbl.TextSize = 10
            skLbl.TextXAlignment = Enum.TextXAlignment.Left
            skLbl.TextTruncate = Enum.TextTruncate.AtEnd
            skLbl.LayoutOrder = 3
        end

        table.insert(outEntryFrames, card)
    end
end

outputUpdateFn = rebuildOutput
rebuildOutput()

-- Clear button
local clearOutBtn = mkBtn("🗑   Clear History", T.redDk, 3, op)
clearOutBtn.MouseButton1Click:Connect(function()
    outputLog = {}
    rebuildOutput()
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- SETTINGS PAGE
-- ═══════════════════════════════════════════════════════════════════════════════
local sp = settingTab.page

-- ── Window size ───────────────────────────────────────────────────────────────
secLabel("Window size", 1, sp)

local sizeCard = Instance.new("Frame")
sizeCard.Size = UDim2.new(1,0,0,0)
sizeCard.AutomaticSize = Enum.AutomaticSize.Y
sizeCard.BackgroundColor3 = T.card
sizeCard.BorderSizePixel = 0
sizeCard.LayoutOrder = 2
sizeCard.Parent = sp
Instance.new("UICorner",sizeCard).CornerRadius = UDim.new(0,9)
Instance.new("UIStroke",sizeCard).Color = T.border

local scPad = Instance.new("UIPadding",sizeCard)
scPad.PaddingLeft=UDim.new(0,12) scPad.PaddingRight=UDim.new(0,12)
scPad.PaddingTop=UDim.new(0,10) scPad.PaddingBottom=UDim.new(0,10)

local scLayout = Instance.new("UIListLayout",sizeCard)
scLayout.SortOrder = Enum.SortOrder.LayoutOrder
scLayout.Padding = UDim.new(0,8)

local function sizeRow(labelTxt, minV, maxV, defaultV, order, onChange)
    local row = Instance.new("Frame",sizeCard)
    row.Size = UDim2.new(1,0,0,30)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order

    local lbl = Instance.new("TextLabel",row)
    lbl.Size = UDim2.new(0.45,0,1,0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelTxt
    lbl.TextColor3 = T.txt
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local box = Instance.new("TextBox",row)
    box.Size = UDim2.new(0,70,0,28)
    box.Position = UDim2.new(0.5,0,0.5,-14)
    box.BackgroundColor3 = T.input
    box.BorderSizePixel = 0
    box.Text = tostring(defaultV)
    box.TextColor3 = T.txt
    box.Font = Enum.Font.GothamBold
    box.TextSize = 13
    box.ClearTextOnFocus = false
    Instance.new("UICorner",box).CornerRadius = UDim.new(0,6)
    local bst = Instance.new("UIStroke",box); bst.Color=T.border; bst.Thickness=1
    local bpd = Instance.new("UIPadding",box); bpd.PaddingLeft=UDim.new(0,8)
    box.Focused:Connect(function() TweenService:Create(bst,TweenInfo.new(0.15),{Color=T.accent}):Play() end)
    box.FocusLost:Connect(function()
        TweenService:Create(bst,TweenInfo.new(0.15),{Color=T.border}):Play()
        local v=tonumber(box.Text)
        if v then
            v = math.clamp(v,minV,maxV)
            box.Text = tostring(v)
            onChange(v)
        else
            box.Text = tostring(defaultV)
        end
    end)

    local applyBtn = Instance.new("TextButton",row)
    applyBtn.Size = UDim2.new(0,54,0,28)
    applyBtn.Position = UDim2.new(1,-54,0.5,-14)
    applyBtn.BackgroundColor3 = T.accent
    applyBtn.Text = "Apply"
    applyBtn.TextColor3 = Color3.new(1,1,1)
    applyBtn.Font = Enum.Font.GothamBold
    applyBtn.TextSize = 11
    applyBtn.BorderSizePixel = 0
    Instance.new("UICorner",applyBtn).CornerRadius = UDim.new(0,6)
    applyBtn.MouseButton1Click:Connect(function()
        local v=tonumber(box.Text)
        if v then v=math.clamp(v,minV,maxV) box.Text=tostring(v) onChange(v) end
    end)

    return row, box
end

sizeRow("Width  (340–700)", 340, 700, cfg.winW, 1, function(v)
    cfg.winW = v
    win.Size = UDim2.new(0,cfg.winW,0,cfg.winH)
    saveConfig()
end)
sizeRow("Height  (380–700)", 380, 700, cfg.winH, 2, function(v)
    cfg.winH = v
    win.Size = UDim2.new(0,cfg.winW,0,cfg.winH)
    saveConfig()
end)

-- ── Item limit ────────────────────────────────────────────────────────────────
secLabel("Send limit", 3, sp)

local limitCard = Instance.new("Frame")
limitCard.Size = UDim2.new(1,0,0,52)
limitCard.BackgroundColor3 = T.card
limitCard.BorderSizePixel = 0
limitCard.LayoutOrder = 4
limitCard.Parent = sp
Instance.new("UICorner",limitCard).CornerRadius = UDim.new(0,9)
Instance.new("UIStroke",limitCard).Color = T.border

local limLbl = Instance.new("TextLabel",limitCard)
limLbl.Size = UDim2.new(1,-90,0,22)
limLbl.Position = UDim2.new(0,12,0,8)
limLbl.BackgroundTransparency = 1
limLbl.Text = "Max items per entry"
limLbl.TextColor3 = T.txt
limLbl.Font = Enum.Font.GothamSemibold
limLbl.TextSize = 13
limLbl.TextXAlignment = Enum.TextXAlignment.Left

local limDesc = Instance.new("TextLabel",limitCard)
limDesc.Size = UDim2.new(1,-90,0,14)
limDesc.Position = UDim2.new(0,12,0,30)
limDesc.BackgroundTransparency = 1
limDesc.Text = "Hard cap: 100 (safety limit)"
limDesc.TextColor3 = T.txtMute
limDesc.Font = Enum.Font.Gotham
limDesc.TextSize = 10
limDesc.TextXAlignment = Enum.TextXAlignment.Left

local limBox = Instance.new("TextBox",limitCard)
limBox.Size = UDim2.new(0,60,0,28)
limBox.Position = UDim2.new(1,-72,0.5,-14)
limBox.BackgroundColor3 = T.input
limBox.BorderSizePixel = 0
limBox.Text = tostring(cfg.maxItems)
limBox.TextColor3 = T.txt
limBox.Font = Enum.Font.GothamBold
limBox.TextSize = 13
limBox.ClearTextOnFocus = false
Instance.new("UICorner",limBox).CornerRadius = UDim.new(0,6)
local lst = Instance.new("UIStroke",limBox); lst.Color=T.border; lst.Thickness=1
Instance.new("UIPadding",limBox).PaddingLeft = UDim.new(0,8)
limBox.Focused:Connect(function() TweenService:Create(lst,TweenInfo.new(0.15),{Color=T.accent}):Play() end)
limBox.FocusLost:Connect(function()
    TweenService:Create(lst,TweenInfo.new(0.15),{Color=T.border}):Play()
    local v=tonumber(limBox.Text)
    if v then cfg.maxItems=math.clamp(v,1,100) limBox.Text=tostring(cfg.maxItems) end
    saveConfig()
end)

-- ── Webhook ───────────────────────────────────────────────────────────────────
secLabel("Discord Webhook (sends log)", 5, sp)

local webhookBox = mkInput("https://discord.com/api/webhooks/...", 6, sp)
webhookBox.Text = cfg.webhook
webhookBox.FocusLost:Connect(function() cfg.webhook=webhookBox.Text saveConfig() end)

local testWebhookBtn = mkBtn("🔔   Test Webhook", Color3.fromRGB(88,101,242), 7, sp)
testWebhookBtn.MouseButton1Click:Connect(function()
    if cfg.webhook=="" then return end
    pcall(function()
        local body = HttpService:JSONEncode({content="✅ Auto Send Mailbox webhook test!"})
        local req = (syn and syn.request) or (http and http.request) or request
        if req then req({Url=cfg.webhook,Method="POST",Headers={["Content-Type"]="application/json"},Body=body}) end
    end)
end)

-- ── Auto Save ─────────────────────────────────────────────────────────────────
secLabel("Auto Save", 8, sp)

local _, getAutoSave2, setAutoSave2 = mkToggle("Auto Save (saves to getgenv on send)", 9, sp)
setAutoSave2(cfg.autoSave)

local saveNowBtn = mkBtn("💾   Save Now", T.green, 10, sp)
saveNowBtn.MouseButton1Click:Connect(function()
    cfg.autoSave = true
    setAutoSave2(true)
    saveConfig()
    -- flash feedback
    local orig = saveNowBtn.Text
    saveNowBtn.Text = "✓  Saved!"
    task.delay(1.5, function() if saveNowBtn and saveNowBtn.Parent then saveNowBtn.Text=orig end end)
end)

local _, _, _set = mkToggle("", 0, sp) -- dummy, ignore
-- wire toggle to cfg
task.spawn(function()
    while gui.Parent do
        cfg.autoSave = getAutoSave2()
        task.wait(0.5)
    end
end)

-- ── About ─────────────────────────────────────────────────────────────────────
secLabel("About", 11, sp)

local aboutCard = Instance.new("Frame")
aboutCard.Size = UDim2.new(1,0,0,66)
aboutCard.BackgroundColor3 = T.card
aboutCard.BorderSizePixel = 0
aboutCard.LayoutOrder = 12
aboutCard.Parent = sp
Instance.new("UICorner",aboutCard).CornerRadius = UDim.new(0,9)
Instance.new("UIStroke",aboutCard).Color = T.border

local aboutLbl = Instance.new("TextLabel",aboutCard)
aboutLbl.Size = UDim2.new(1,-20,1,0)
aboutLbl.Position = UDim2.new(0,12,0,0)
aboutLbl.BackgroundTransparency = 1
aboutLbl.Text = "Auto Send Mailbox  v2.0\nBatch sends items through the Mailbox network.\nMax 20 unique entries per batch · Hard cap 100/item."
aboutLbl.TextColor3 = T.txtMute
aboutLbl.Font = Enum.Font.Gotham
aboutLbl.TextSize = 11
aboutLbl.TextXAlignment = Enum.TextXAlignment.Left
aboutLbl.TextYAlignment = Enum.TextYAlignment.Center

-- ═══════════════════════════════════════════════════════════════════════════════
-- BUTTON LOGIC
-- ═══════════════════════════════════════════════════════════════════════════════
local autoSendRunning = false
local autoSendThread  = nil

sendOnceBtn.MouseButton1Click:Connect(function()
    rebuildCfg()
    cfg.username = usernameBox.Text
    cfg.note     = noteBox.Text
    log("Sending...")
    task.spawn(function()
        local ok,err = pcall(function() doSend(log) end)
        if not ok then log("Error: "..tostring(err),true) end
    end)
end)

local function stopAutoSend()
    autoSendRunning = false
    if autoSendThread then task.cancel(autoSendThread) autoSendThread=nil end
    autoSendBtn.Text = "⏵   Start Auto Send"
    TweenService:Create(autoSendBtn,TweenInfo.new(0.2),{BackgroundColor3=T.green}):Play()
    log("Auto send stopped.")
end

local function startAutoSend()
    autoSendRunning = true
    autoSendBtn.Text = "⏹   Stop Auto Send"
    TweenService:Create(autoSendBtn,TweenInfo.new(0.2),{BackgroundColor3=T.red}):Play()
    autoSendThread = task.spawn(function()
        while autoSendRunning do
            rebuildCfg()
            cfg.username = usernameBox.Text
            cfg.note     = noteBox.Text
            cfg.interval = tonumber(intBox.Text) or 10

            -- update item status dots before sending
            local inv = getInv()
            if inv then updateItemStatuses(inv) end

            pcall(function() doSend(log) end)
            task.wait(cfg.interval)
        end
    end)
end

autoSendBtn.MouseButton1Click:Connect(function()
    if autoSendRunning then stopAutoSend() setAutoSend(false)
    else startAutoSend() setAutoSend(true) end
end)

local function doClaim2(logFn)
    local ok = pcall(function() return getNet().Mailbox.ClaimAll:Fire() end)
    logFn(ok and "✓  Mail claimed." or "✗  Claim failed.", not ok)
end

claimNowBtn.MouseButton1Click:Connect(function()
    log("Claiming mail...")
    task.spawn(function() pcall(function() doClaim2(log) end) end)
end)

-- Sync toggle → auto send
task.spawn(function()
    while gui.Parent do
        if getAutoSend() and not autoSendRunning then startAutoSend()
        elseif not getAutoSend() and autoSendRunning then stopAutoSend() end
        task.wait(0.5)
    end
end)

-- Periodic inventory status dot refresh
task.spawn(function()
    while gui.Parent do
        task.wait(5)
        local ok,inv = pcall(getInv)
        if ok and inv then updateItemStatuses(inv) end
    end
end)

-- ─── Load saved config on start ───────────────────────────────────────────────
if loadConfig() then
    usernameBox.Text = cfg.username
    noteBox.Text     = cfg.note
    intBox.Text      = tostring(cfg.interval)
    limBox.Text      = tostring(cfg.maxItems)
    webhookBox.Text  = cfg.webhook
    win.Size = UDim2.new(0, cfg.winW, 0, cfg.winH)
    win.Position = UDim2.new(0.5,-cfg.winW/2,0.5,-cfg.winH/2)
    for _,it in ipairs(cfg.items) do
        addItemEntry(it.name, it.amount)
    end
    log("Config loaded from last session.")
else
    log("Ready — fill in details and send.")
end
