-- Auto Send Mailbox GUI v4.0
-- Paste into your executor

local RS           = game:GetService("ReplicatedStorage")
local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local HttpService  = game:GetService("HttpService")
local LocalPlayer  = Players.LocalPlayer

-- ═══════════════════════════════════════════════════════════════════════
-- PERSISTENT SAVE  (survives rejoin as long as executor keeps getgenv)
-- ═══════════════════════════════════════════════════════════════════════
local SAVE_KEY = "ASM_Config_v4"

local cfg = {
    username     = "",
    items        = {},   -- { name, amount, enabled }
    note         = "",
    interval     = 10,
    maxAmt       = 100,
    webhook      = "",
    webhookOn    = false,
    autoLoad     = false,   -- auto-load selected config on start
    selectedCfg  = "",      -- name of currently selected config
    winW         = 540,
    winH         = 480,
}

local configs = {}   -- { [name] = { username, note, interval, items } }

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = deepCopy(v) end
    return c
end

-- Always saves everything, regardless of any toggle
local function saveAll()
    getgenv()[SAVE_KEY] = {
        cfg     = deepCopy(cfg),
        configs = deepCopy(configs),
    }
end

local function loadAll()
    local d = getgenv()[SAVE_KEY]
    if type(d) ~= "table" then return false end
    if type(d.cfg) == "table" then
        for k, v in pairs(d.cfg) do cfg[k] = v end
    end
    if type(d.configs) == "table" then
        configs = deepCopy(d.configs)
    end
    return true
end

-- ═══════════════════════════════════════════════════════════════════════
-- GAME LOGIC
-- ═══════════════════════════════════════════════════════════════════════
local STACK = {
    Sprinklers=1, WateringCans=1, Mushrooms=1, Gnomes=1, Raccoons=1, Crates=1,
    SeedPacks=1, Trowels=1, Props=1, Seeds=1, HarvestedFruits=1, Flashbangs=1, EmptyPots=1,
}

local function safeNet()
    return require(RS:WaitForChild("SharedModules"):WaitForChild("Networking"))
end
local function safePS()
    return require(RS:WaitForChild("ClientModules"):WaitForChild("PlayerStateClient"))
end
local function getInv()
    local ok, r = pcall(function() return safePS():WaitForLocalReplica(5) end)
    return ok and r and r.Data and type(r.Data.Inventory) == "table" and r.Data.Inventory
end

local function hasItem(inv, name)
    if type(inv.Pets) == "table" then
        for _, p in pairs(inv.Pets) do
            if type(p) == "table" and p.Id and not p.Equipped and tostring(p.Name) == name then
                return true
            end
        end
    end
    for cat in pairs(STACK) do
        local t = inv[cat]
        if type(t) == "table" and type(t[name]) == "number" and t[name] > 0 then return true end
    end
    return false
end

local function buildBatch(inv, entry)
    local out  = {}
    local want = math.clamp(math.floor(entry.amount or 1), 1, cfg.maxAmt)
    if type(inv.Pets) == "table" then
        for key, p in pairs(inv.Pets) do
            if want <= 0 then break end
            if type(p) == "table" and p.Id and not p.Equipped and tostring(p.Name) == entry.name then
                out[#out+1] = { Category = "Pets", ItemKey = key, Count = 1 }
                want -= 1
            end
        end
    end
    if want > 0 then
        for cat in pairs(STACK) do
            local t = inv[cat]
            if type(t) == "table" and type(t[entry.name]) == "number" and t[entry.name] > 0 then
                out[#out+1] = { Category = cat, ItemKey = entry.name, Count = math.min(want, t[entry.name]) }
                break
            end
        end
    end
    return out
end

-- ═══════════════════════════════════════════════════════════════════════
-- DISCORD WEBHOOK  (rich embed)
-- ═══════════════════════════════════════════════════════════════════════
local function sendWebhook(to, sentItems, skippedNames, success)
    if cfg.webhook == "" or not cfg.webhookOn then return end
    local sender = LocalPlayer.Name
    local now    = os.date("%Y-%m-%d %H:%M:%S")
    local color  = success and 3066993 or 15158332

    local itemLines = {}
    for _, e in ipairs(sentItems) do
        table.insert(itemLines, "• **" .. e.name .. "** ×" .. tostring(e.amount))
    end
    local itemBlock = #itemLines > 0 and table.concat(itemLines, "\n") or "_nothing_"
    local skipBlock = #skippedNames > 0 and table.concat(skippedNames, ", ") or "_none_"

    local embed = {
        title       = (success and "✅  Items Sent" or "❌  Send Failed") .. " — Auto Send Mailbox",
        color       = color,
        description = "**→ Profile**\n```\nSender  :  " .. sender .. "\nTarget  :  " .. to .. "\n```",
        fields = {
            { name = "📦  Items Sent",              value = itemBlock, inline = false },
            { name = "⏭  Skipped (not in inv)",    value = skipBlock, inline = false },
        },
        footer    = { text = "Auto Send Mailbox  •  " .. now },
        thumbnail = { url  = "https://www.roblox.com/headshot-thumbnail/image?userId="
                            .. tostring(LocalPlayer.UserId) .. "&width=48&height=48&format=png" },
    }

    pcall(function()
        local body = HttpService:JSONEncode({ embeds = { embed } })
        local req  = (syn and syn.request) or (http and http.request) or request
        if req then
            req({ Url = cfg.webhook, Method = "POST",
                  Headers = { ["Content-Type"] = "application/json" }, Body = body })
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════
-- OUTPUT LOG
-- ═══════════════════════════════════════════════════════════════════════
local outputLog       = {}
local MAX_LOG         = 10
local rebuildOutputFn = nil

local function pushLog(to, sent, skipped, success)
    table.insert(outputLog, 1, {
        time = os.date("%H:%M:%S"), to = to,
        items = deepCopy(sent), skipped = deepCopy(skipped), success = success,
    })
    while #outputLog > MAX_LOG do table.remove(outputLog) end
    if rebuildOutputFn then rebuildOutputFn() end
end

-- ═══════════════════════════════════════════════════════════════════════
-- SEND — single entry (used by auto-loop)
-- ═══════════════════════════════════════════════════════════════════════
local function doSendEntry(entry, logFn)
    -- returns: worked(bool), wasSkipped(bool)
    if cfg.username == "" then logFn("⚠  No username set.", true) return false, false end
    local inv = getInv()
    if not inv then logFn("⚠  Could not read inventory.", true) return false, false end
    if not hasItem(inv, entry.name) then
        return false, true   -- skip silently; caller handles UI
    end
    local batch = buildBatch(inv, entry)
    if #batch == 0 then return false, true end
    local Net    = safeNet()
    local ok, uid = pcall(function() return Net.Mailbox.LookupPlayer:Fire(cfg.username) end)
    if not ok or type(uid) ~= "number" or uid <= 0 then
        logFn("⚠  Player lookup failed.", true) return false, false
    end
    local ok2, suc = pcall(function() return Net.Mailbox.SendBatch:Fire(uid, batch, cfg.note or "") end)
    return suc == true, false
end

-- SEND — all enabled items at once (Send Once button)
local function doSendAll(logFn)
    if cfg.username == "" then logFn("⚠  No username set.", true) return end
    local inv = getInv()
    if not inv then logFn("⚠  Could not read inventory.", true) return end

    local sent, skipped = {}, {}
    for _, e in ipairs(cfg.items) do
        if not e.enabled then continue end
        if not hasItem(inv, e.name) then
            table.insert(skipped, e.name)
        else
            local batch = buildBatch(inv, e)
            if #batch > 0 then
                local Net     = safeNet()
                local ok, uid = pcall(function() return Net.Mailbox.LookupPlayer:Fire(cfg.username) end)
                if ok and type(uid) == "number" and uid > 0 then
                    local _, suc = pcall(function() return Net.Mailbox.SendBatch:Fire(uid, batch, cfg.note or "") end)
                    if suc == true then table.insert(sent, e) end
                end
            end
        end
    end

    local success = #sent > 0
    if success then
        logFn("✓  Sent " .. #sent .. " item(s) to " .. cfg.username
              .. (#skipped > 0 and "  (skipped " .. #skipped .. ")" or ""))
    else
        logFn("✗  Nothing sent" .. (#skipped > 0 and " — all skipped." or "."), true)
    end
    pushLog(cfg.username, sent, skipped, success)
    sendWebhook(cfg.username, sent, skipped, success)
    saveAll()
end

-- ═══════════════════════════════════════════════════════════════════════
-- THEME
-- ═══════════════════════════════════════════════════════════════════════
local T = {
    bg      = Color3.fromRGB(12, 12, 19),
    sidebar = Color3.fromRGB(16, 16, 26),
    surface = Color3.fromRGB(21, 21, 34),
    card    = Color3.fromRGB(26, 26, 42),
    cardAlt = Color3.fromRGB(22, 22, 36),
    input   = Color3.fromRGB(15, 15, 26),
    border  = Color3.fromRGB(45, 45, 70),
    accent  = Color3.fromRGB(100, 140, 255),
    accentL = Color3.fromRGB(140, 175, 255),
    green   = Color3.fromRGB(52, 195, 105),
    greenDk = Color3.fromRGB(32, 140, 70),
    red     = Color3.fromRGB(215, 60, 60),
    redDk   = Color3.fromRGB(150, 35, 35),
    orange  = Color3.fromRGB(230, 148, 48),
    purple  = Color3.fromRGB(150, 80, 235),
    txt     = Color3.fromRGB(228, 228, 248),
    txtSub  = Color3.fromRGB(155, 155, 195),
    txtMute = Color3.fromRGB(82, 82, 122),
    tagBg   = Color3.fromRGB(28, 28, 48),
    badgeBg = Color3.fromRGB(26, 45, 95),
    badgeTx = Color3.fromRGB(125, 180, 255),
}

-- ═══════════════════════════════════════════════════════════════════════
-- GUI ROOT
-- ═══════════════════════════════════════════════════════════════════════
local gui = Instance.new("ScreenGui")
gui.Name           = "AutoSendMailbox"
gui.ResetOnSpawn   = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent         = LocalPlayer:WaitForChild("PlayerGui")

-- ── Main window ──────────────────────────────────────────────────────
local win = Instance.new("Frame")
win.Name             = "Window"
win.Size             = UDim2.new(0, cfg.winW, 0, cfg.winH)
win.Position         = UDim2.new(0.5, -cfg.winW/2, 0.5, -cfg.winH/2)
win.BackgroundColor3 = T.bg
win.BorderSizePixel  = 0
win.Active           = true
win.Draggable        = true
win.ClipsDescendants = true
win.Parent           = gui
Instance.new("UICorner", win).CornerRadius = UDim.new(0, 13)

local winStroke = Instance.new("UIStroke", win)
winStroke.Color = T.border; winStroke.Thickness = 1.5

-- Animated rainbow top-bar
local topBar = Instance.new("Frame", win)
topBar.Size             = UDim2.new(1, 0, 0, 3)
topBar.BackgroundColor3 = T.accent
topBar.BorderSizePixel  = 0
topBar.ZIndex           = 10
local topGrad = Instance.new("UIGradient", topBar)
topGrad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(100,140,255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150,80,235)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(52,195,105)),
}
task.spawn(function()
    local t = 0
    while gui.Parent do
        t += task.wait(0.016)
        topGrad.Offset = Vector2.new(math.sin(t * 0.4) * 0.5, 0)
    end
end)

-- ── Title bar ────────────────────────────────────────────────────────
local TH = 44
local titleBar = Instance.new("Frame", win)
titleBar.Size             = UDim2.new(1, 0, 0, TH)
titleBar.Position         = UDim2.new(0, 0, 0, 3)
titleBar.BackgroundColor3 = T.surface
titleBar.BorderSizePixel  = 0
titleBar.ZIndex           = 4
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 13)
local tbFix = Instance.new("Frame", titleBar)
tbFix.Size             = UDim2.new(1, 0, 0, 13)
tbFix.Position         = UDim2.new(0, 0, 1, -13)
tbFix.BackgroundColor3 = T.surface; tbFix.BorderSizePixel = 0

local pill = Instance.new("Frame", titleBar)
pill.Size             = UDim2.new(0, 22, 0, 14)
pill.Position         = UDim2.new(0, 14, 0.5, -7)
pill.BackgroundColor3 = T.accent; pill.BorderSizePixel = 0
Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
local pillG = Instance.new("UIGradient", pill)
pillG.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, T.accent),
    ColorSequenceKeypoint.new(1, T.purple),
}

local titleLbl = Instance.new("TextLabel", titleBar)
titleLbl.Size               = UDim2.new(1, -120, 1, 0)
titleLbl.Position           = UDim2.new(0, 44, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text               = "Auto Send Mailbox"
titleLbl.TextColor3         = T.txt
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 14
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left

local function mkTitleBtn(lbl, col, ox)
    local b = Instance.new("TextButton", titleBar)
    b.Size             = UDim2.new(0, 26, 0, 26)
    b.Position         = UDim2.new(1, ox, 0.5, -13)
    b.BackgroundColor3 = col; b.Text = lbl
    b.TextColor3       = Color3.new(1,1,1); b.Font = Enum.Font.GothamBold
    b.TextSize         = 13; b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = col:Lerp(Color3.new(1,1,1), 0.18)}):Play() end)
    b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = col}):Play() end)
    return b
end

local hideBtn  = mkTitleBtn("−", Color3.fromRGB(55, 125, 60), -64)
local closeBtn = mkTitleBtn("✕", T.red, -32)
closeBtn.MouseButton1Click:Connect(function() saveAll() gui:Destroy() end)

-- ── Mini restore button (draggable) ──────────────────────────────────
local miniBtn = Instance.new("TextButton", gui)
miniBtn.Size             = UDim2.new(0, 46, 0, 46)
miniBtn.Position         = UDim2.new(0, 20, 0.5, -23)
miniBtn.BackgroundColor3 = T.accent
miniBtn.Text             = "📬"
miniBtn.TextSize         = 22
miniBtn.Font             = Enum.Font.GothamBold
miniBtn.BorderSizePixel  = 0
miniBtn.Visible          = false
miniBtn.ZIndex           = 20
Instance.new("UICorner", miniBtn).CornerRadius = UDim.new(0, 12)
local miniStroke = Instance.new("UIStroke", miniBtn)
miniStroke.Color = T.accentL; miniStroke.Thickness = 1.5

-- Make mini button draggable
do
    local dragging, dragStart, startPos = false, nil, nil
    miniBtn.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging  = true
            dragStart = inp.Position
            startPos  = miniBtn.Position
        end
    end)
    UIS.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = inp.Position - dragStart
            miniBtn.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    UIS.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

local guiVisible = true
hideBtn.MouseButton1Click:Connect(function()
    guiVisible     = not guiVisible
    win.Visible    = guiVisible
    miniBtn.Visible = not guiVisible
end)
miniBtn.MouseButton1Click:Connect(function()
    -- only restore on single click, not after drag
    guiVisible      = true
    win.Visible     = true
    miniBtn.Visible = false
end)

-- ── Sidebar ──────────────────────────────────────────────────────────
local SW      = 130
local sidebar = Instance.new("Frame", win)
sidebar.Size             = UDim2.new(0, SW, 1, -TH-3)
sidebar.Position         = UDim2.new(0, 0, 0, TH+3)
sidebar.BackgroundColor3 = T.sidebar
sidebar.BorderSizePixel  = 0; sidebar.ZIndex = 2
local sideStk = Instance.new("UIStroke", sidebar)
sideStk.Color = T.border; sideStk.Thickness = 1

local sideL = Instance.new("UIListLayout", sidebar)
sideL.SortOrder = Enum.SortOrder.LayoutOrder; sideL.Padding = UDim.new(0, 3)
local sideP = Instance.new("UIPadding", sidebar)
sideP.PaddingTop = UDim.new(0,10); sideP.PaddingLeft = UDim.new(0,7)
sideP.PaddingRight = UDim.new(0,7); sideP.PaddingBottom = UDim.new(0,8)

local menuHdr = Instance.new("TextLabel", sidebar)
menuHdr.Size = UDim2.new(1,0,0,14); menuHdr.BackgroundTransparency = 1
menuHdr.Text = "MENU"; menuHdr.TextColor3 = T.txtMute
menuHdr.Font = Enum.Font.GothamSemibold; menuHdr.TextSize = 8
menuHdr.TextXAlignment = Enum.TextXAlignment.Left; menuHdr.LayoutOrder = 0

local verLbl = Instance.new("TextLabel", sidebar)
verLbl.Size = UDim2.new(1,0,0,12); verLbl.AnchorPoint = Vector2.new(0,1)
verLbl.Position = UDim2.new(0,0,1,-4); verLbl.BackgroundTransparency = 1
verLbl.Text = "v4.0"; verLbl.TextColor3 = T.txtMute
verLbl.Font = Enum.Font.Gotham; verLbl.TextSize = 9
verLbl.TextXAlignment = Enum.TextXAlignment.Center; verLbl.ZIndex = 3

-- ── Content area ─────────────────────────────────────────────────────
local content = Instance.new("Frame", win)
content.Size             = UDim2.new(1, -SW, 1, -TH-3)
content.Position         = UDim2.new(0, SW, 0, TH+3)
content.BackgroundColor3 = T.bg
content.BorderSizePixel  = 0; content.ClipsDescendants = true

-- ═══════════════════════════════════════════════════════════════════════
-- TAB FACTORY
-- ═══════════════════════════════════════════════════════════════════════
local allTabs   = {}
local activeTab = nil

local function makeTab(icon, label, order)
    local btn = Instance.new("TextButton", sidebar)
    btn.Size = UDim2.new(1,0,0,38); btn.BackgroundColor3 = T.sidebar
    btn.BorderSizePixel = 0; btn.Text = ""; btn.LayoutOrder = order
    btn.AutoButtonColor = false
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

    local bar = Instance.new("Frame", btn)
    bar.Size = UDim2.new(0,3,0,20); bar.Position = UDim2.new(0,0,0.5,-10)
    bar.BackgroundColor3 = T.accent; bar.BorderSizePixel = 0; bar.Visible = false
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)

    local ic = Instance.new("TextLabel", btn)
    ic.Size = UDim2.new(0,24,1,0); ic.Position = UDim2.new(0,8,0,0)
    ic.BackgroundTransparency = 1; ic.Text = icon; ic.TextSize = 14
    ic.Font = Enum.Font.GothamBold; ic.TextColor3 = T.txtMute

    local nm = Instance.new("TextLabel", btn)
    nm.Size = UDim2.new(1,-36,1,0); nm.Position = UDim2.new(0,34,0,0)
    nm.BackgroundTransparency = 1; nm.Text = label
    nm.Font = Enum.Font.GothamSemibold; nm.TextSize = 12
    nm.TextColor3 = T.txtMute; nm.TextXAlignment = Enum.TextXAlignment.Left

    local page = Instance.new("ScrollingFrame", content)
    page.Size = UDim2.new(1,0,1,0); page.BackgroundTransparency = 1
    page.BorderSizePixel = 0; page.ScrollBarThickness = 6
    page.ScrollBarImageColor3 = Color3.fromRGB(60,60,95)
    page.CanvasSize = UDim2.new(0,0,0,0); page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false

    local pl = Instance.new("UIListLayout", page)
    pl.SortOrder = Enum.SortOrder.LayoutOrder; pl.Padding = UDim.new(0,10)
    local pp = Instance.new("UIPadding", page)
    pp.PaddingTop = UDim.new(0,14); pp.PaddingBottom = UDim.new(0,20)
    pp.PaddingLeft = UDim.new(0,12); pp.PaddingRight = UDim.new(0,12)

    local td = {btn=btn, page=page, bar=bar, ic=ic, nm=nm}
    table.insert(allTabs, td)

    btn.MouseButton1Click:Connect(function()
        if activeTab then
            TweenService:Create(activeTab.btn, TweenInfo.new(0.18), {BackgroundColor3 = T.sidebar}):Play()
            activeTab.bar.Visible = false
            activeTab.ic.TextColor3 = T.txtMute; activeTab.nm.TextColor3 = T.txtMute
            activeTab.page.Visible = false
        end
        activeTab = td
        TweenService:Create(btn, TweenInfo.new(0.18), {BackgroundColor3 = T.card}):Play()
        bar.Visible = true; ic.TextColor3 = T.txt; nm.TextColor3 = T.txt; page.Visible = true
    end)
    return td
end

local mailTab    = makeTab("✉️",  "Mail",     1)
local outputTab  = makeTab("📋", "Output",   2)
local settingTab = makeTab("⚙️", "Settings", 3)

mailTab.btn.BackgroundColor3 = T.card; mailTab.bar.Visible = true
mailTab.ic.TextColor3 = T.txt; mailTab.nm.TextColor3 = T.txt
mailTab.page.Visible = true; activeTab = mailTab

-- ═══════════════════════════════════════════════════════════════════════
-- WIDGET HELPERS
-- ═══════════════════════════════════════════════════════════════════════
local function secLbl(txt, order, page)
    local f = Instance.new("Frame"); f.Size = UDim2.new(1,0,0,14)
    f.BackgroundTransparency = 1; f.LayoutOrder = order; f.Parent = page
    local l = Instance.new("TextLabel", f); l.Size = UDim2.new(1,0,1,0)
    l.BackgroundTransparency = 1; l.Text = txt:upper()
    l.TextColor3 = T.txtMute; l.Font = Enum.Font.GothamSemibold
    l.TextSize = 9; l.TextXAlignment = Enum.TextXAlignment.Left
    return f
end

local function mkIn(ph, order, page, h)
    local b = Instance.new("TextBox"); b.Size = UDim2.new(1,0,0,h or 36)
    b.BackgroundColor3 = T.input; b.BorderSizePixel = 0; b.Text = ""
    b.PlaceholderText = ph; b.PlaceholderColor3 = T.txtMute
    b.TextColor3 = T.txt; b.Font = Enum.Font.Gotham; b.TextSize = 13
    b.ClearTextOnFocus = false; b.LayoutOrder = order; b.Parent = page
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    local st = Instance.new("UIStroke", b); st.Color = T.border; st.Thickness = 1
    Instance.new("UIPadding", b).PaddingLeft = UDim.new(0, 12)
    b.Focused:Connect(function()  TweenService:Create(st, TweenInfo.new(0.15), {Color = T.accent}):Play() end)
    b.FocusLost:Connect(function() TweenService:Create(st, TweenInfo.new(0.15), {Color = T.border}):Play() end)
    return b
end

local function mkBtn(txt, col, order, page)
    local b = Instance.new("TextButton"); b.Size = UDim2.new(1,0,0,38)
    b.BackgroundColor3 = col; b.BorderSizePixel = 0; b.Text = txt
    b.TextColor3 = Color3.new(1,1,1); b.Font = Enum.Font.GothamBold
    b.TextSize = 13; b.LayoutOrder = order; b.Parent = page
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 9)
    local g = Instance.new("UIGradient", b)
    g.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.new(1,1,1):Lerp(col, 0.72)),
        ColorSequenceKeypoint.new(1, col),
    }; g.Rotation = 90
    b.MouseEnter:Connect(function()    TweenService:Create(b,TweenInfo.new(0.13),{BackgroundColor3=col:Lerp(Color3.new(1,1,1),0.1)}):Play() end)
    b.MouseLeave:Connect(function()    TweenService:Create(b,TweenInfo.new(0.13),{BackgroundColor3=col}):Play() end)
    b.MouseButton1Down:Connect(function() TweenService:Create(b,TweenInfo.new(0.07),{BackgroundColor3=col:Lerp(Color3.new(0,0,0),0.12)}):Play() end)
    b.MouseButton1Up:Connect(function()   TweenService:Create(b,TweenInfo.new(0.07),{BackgroundColor3=col}):Play() end)
    return b
end

local function mkToggle(lbl, order, page)
    local row = Instance.new("Frame"); row.Size = UDim2.new(1,0,0,40)
    row.BackgroundColor3 = T.card; row.BorderSizePixel = 0
    row.LayoutOrder = order; row.Parent = page
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 9)
    local st = Instance.new("UIStroke", row); st.Color = T.border; st.Thickness = 1

    local l = Instance.new("TextLabel", row); l.Size = UDim2.new(1,-68,1,0)
    l.Position = UDim2.new(0,14,0,0); l.BackgroundTransparency = 1
    l.Text = lbl; l.TextColor3 = T.txt; l.Font = Enum.Font.Gotham
    l.TextSize = 13; l.TextXAlignment = Enum.TextXAlignment.Left

    local pill2 = Instance.new("Frame", row); pill2.Size = UDim2.new(0,44,0,24)
    pill2.Position = UDim2.new(1,-54,0.5,-12); pill2.BackgroundColor3 = T.border
    pill2.BorderSizePixel = 0
    Instance.new("UICorner", pill2).CornerRadius = UDim.new(1, 0)

    local thumb = Instance.new("Frame", pill2); thumb.Size = UDim2.new(0,18,0,18)
    thumb.Position = UDim2.new(0,3,0.5,-9); thumb.BackgroundColor3 = T.txtMute
    thumb.BorderSizePixel = 0
    Instance.new("UICorner", thumb).CornerRadius = UDim.new(1, 0)

    local state = false
    local hit   = Instance.new("TextButton", row); hit.Size = UDim2.new(1,0,1,0)
    hit.BackgroundTransparency = 1; hit.Text = ""

    local function refresh()
        if state then
            TweenService:Create(pill2, TweenInfo.new(0.2), {BackgroundColor3 = T.accent}):Play()
            TweenService:Create(thumb, TweenInfo.new(0.2), {Position = UDim2.new(1,-21,0.5,-9), BackgroundColor3 = Color3.new(1,1,1)}):Play()
        else
            TweenService:Create(pill2, TweenInfo.new(0.2), {BackgroundColor3 = T.border}):Play()
            TweenService:Create(thumb, TweenInfo.new(0.2), {Position = UDim2.new(0,3,0.5,-9), BackgroundColor3 = T.txtMute}):Play()
        end
    end
    hit.MouseButton1Click:Connect(function() state = not state; refresh() end)
    return row, function() return state end, function(v) state = v; refresh() end
end

-- ═══════════════════════════════════════════════════════════════════════
-- MAIL PAGE
-- ═══════════════════════════════════════════════════════════════════════
local mp = mailTab.page

secLbl("Recipient", 1, mp)
local usernameBox = mkIn("Roblox username", 2, mp)
usernameBox.FocusLost:Connect(function() cfg.username = usernameBox.Text end)

-- ── Items card ───────────────────────────────────────────────────────
secLbl("Items to send", 3, mp)

local itemCard = Instance.new("Frame"); itemCard.Size = UDim2.new(1,0,0,10)
itemCard.AutomaticSize = Enum.AutomaticSize.Y; itemCard.BackgroundColor3 = T.card
itemCard.BorderSizePixel = 0; itemCard.LayoutOrder = 4; itemCard.Parent = mp
Instance.new("UICorner", itemCard).CornerRadius = UDim.new(0, 10)
local icStk = Instance.new("UIStroke", itemCard); icStk.Color = T.border; icStk.Thickness = 1

local icL = Instance.new("UIListLayout", itemCard)
icL.SortOrder = Enum.SortOrder.LayoutOrder; icL.Padding = UDim.new(0, 0)

-- Column header row inside the card
local colHdr = Instance.new("Frame", itemCard); colHdr.Size = UDim2.new(1,0,0,28)
colHdr.BackgroundTransparency = 1; colHdr.LayoutOrder = 1

local colItemLbl = Instance.new("TextLabel", colHdr)
colItemLbl.Size = UDim2.new(1,-198,1,0); colItemLbl.Position = UDim2.new(0,46,0,0)
colItemLbl.BackgroundTransparency = 1; colItemLbl.Text = "Item name"
colItemLbl.TextColor3 = T.txtMute; colItemLbl.Font = Enum.Font.GothamSemibold
colItemLbl.TextSize = 10; colItemLbl.TextXAlignment = Enum.TextXAlignment.Left

local colQtyLbl = Instance.new("TextLabel", colHdr)
colQtyLbl.Size = UDim2.new(0,44,1,0); colQtyLbl.Position = UDim2.new(1,-152,0,0)
colQtyLbl.BackgroundTransparency = 1; colQtyLbl.Text = "Qty"
colQtyLbl.TextColor3 = T.txtMute; colQtyLbl.Font = Enum.Font.GothamSemibold
colQtyLbl.TextSize = 10; colQtyLbl.TextXAlignment = Enum.TextXAlignment.Center

local colAutoLbl = Instance.new("TextLabel", colHdr)
colAutoLbl.Size = UDim2.new(0,46,1,0); colAutoLbl.Position = UDim2.new(1,-102,0,0)
colAutoLbl.BackgroundTransparency = 1; colAutoLbl.Text = "Auto Send"
colAutoLbl.TextColor3 = T.txtMute; colAutoLbl.Font = Enum.Font.GothamSemibold
colAutoLbl.TextSize = 9; colAutoLbl.TextXAlignment = Enum.TextXAlignment.Center

-- add-input row
local addRowF = Instance.new("Frame", itemCard); addRowF.Size = UDim2.new(1,0,0,44)
addRowF.BackgroundTransparency = 1; addRowF.LayoutOrder = 2

local nameIn = Instance.new("TextBox", addRowF); nameIn.Size = UDim2.new(1,-98,0,30)
nameIn.Position = UDim2.new(0,10,0.5,-15); nameIn.BackgroundColor3 = T.input
nameIn.BorderSizePixel = 0; nameIn.PlaceholderText = "Item name"
nameIn.PlaceholderColor3 = T.txtMute; nameIn.Text = ""; nameIn.TextColor3 = T.txt
nameIn.Font = Enum.Font.Gotham; nameIn.TextSize = 12; nameIn.ClearTextOnFocus = false
Instance.new("UICorner", nameIn).CornerRadius = UDim.new(0, 7)
local nsSt = Instance.new("UIStroke", nameIn); nsSt.Color = T.border; nsSt.Thickness = 1
Instance.new("UIPadding", nameIn).PaddingLeft = UDim.new(0, 9)
nameIn.Focused:Connect(function()  TweenService:Create(nsSt, TweenInfo.new(0.15), {Color = T.accent}):Play() end)
nameIn.FocusLost:Connect(function() TweenService:Create(nsSt, TweenInfo.new(0.15), {Color = T.border}):Play() end)

local amtIn = Instance.new("TextBox", addRowF); amtIn.Size = UDim2.new(0,46,0,30)
amtIn.Position = UDim2.new(1,-84,0.5,-15); amtIn.BackgroundColor3 = T.input
amtIn.BorderSizePixel = 0; amtIn.PlaceholderText = "Qty"; amtIn.PlaceholderColor3 = T.txtMute
amtIn.Text = ""; amtIn.TextColor3 = T.txt; amtIn.Font = Enum.Font.GothamBold
amtIn.TextSize = 12; amtIn.ClearTextOnFocus = false
Instance.new("UICorner", amtIn).CornerRadius = UDim.new(0, 7)
local amSt = Instance.new("UIStroke", amtIn); amSt.Color = T.border; amSt.Thickness = 1
Instance.new("UIPadding", amtIn).PaddingLeft = UDim.new(0, 7)
amtIn.Focused:Connect(function()  TweenService:Create(amSt, TweenInfo.new(0.15), {Color = T.accent}):Play() end)
amtIn.FocusLost:Connect(function() TweenService:Create(amSt, TweenInfo.new(0.15), {Color = T.border}):Play() end)

local addBtn = Instance.new("TextButton", addRowF); addBtn.Size = UDim2.new(0,30,0,30)
addBtn.Position = UDim2.new(1,-36,0.5,-15); addBtn.BackgroundColor3 = T.green
addBtn.Text = "+"; addBtn.TextColor3 = Color3.new(1,1,1)
addBtn.Font = Enum.Font.GothamBold; addBtn.TextSize = 18; addBtn.BorderSizePixel = 0
Instance.new("UICorner", addBtn).CornerRadius = UDim.new(0, 7)

-- thin divider
local addDiv = Instance.new("Frame", itemCard); addDiv.Size = UDim2.new(1,-20,0,1)
addDiv.BackgroundColor3 = T.border; addDiv.BorderSizePixel = 0; addDiv.LayoutOrder = 3

-- error label
local errLbl = Instance.new("TextLabel", itemCard); errLbl.Size = UDim2.new(1,-20,0,16)
errLbl.BackgroundTransparency = 1; errLbl.Text = ""
errLbl.TextColor3 = T.red; errLbl.Font = Enum.Font.GothamSemibold
errLbl.TextSize = 10; errLbl.LayoutOrder = 4
Instance.new("UIPadding", errLbl).PaddingLeft = UDim.new(0, 10)

local function showErr(msg)
    errLbl.Text = msg
    task.delay(2.5, function() if errLbl and errLbl.Parent then errLbl.Text = "" end end)
end

-- item list
local itemList = Instance.new("Frame", itemCard); itemList.Name = "ItemList"
itemList.Size = UDim2.new(1,0,0,0); itemList.AutomaticSize = Enum.AutomaticSize.Y
itemList.BackgroundTransparency = 1; itemList.BorderSizePixel = 0; itemList.LayoutOrder = 5

local ilL = Instance.new("UIListLayout", itemList)
ilL.SortOrder = Enum.SortOrder.LayoutOrder; ilL.Padding = UDim.new(0, 0)

local emptyLbl = Instance.new("TextLabel", itemList); emptyLbl.Size = UDim2.new(1,0,0,32)
emptyLbl.BackgroundTransparency = 1; emptyLbl.Text = "No items added yet."
emptyLbl.TextColor3 = T.txtMute; emptyLbl.Font = Enum.Font.Gotham
emptyLbl.TextSize = 12; emptyLbl.LayoutOrder = 0

local itemEntries = {}   -- { cfgEntry={name,amount,enabled}, frame, dot, qtyBox, enBtn, numLbl }

local function refreshEmpty() emptyLbl.Visible = #itemEntries == 0 end

local function syncCfgItems()
    cfg.items = {}
    for _, e in ipairs(itemEntries) do
        table.insert(cfg.items, { name = e.cfgEntry.name, amount = e.cfgEntry.amount, enabled = e.cfgEntry.enabled })
    end
end

local function updateDots(inv)
    for _, e in ipairs(itemEntries) do
        if e.dot and e.dot.Parent then
            local has = inv and hasItem(inv, e.cfgEntry.name)
            TweenService:Create(e.dot, TweenInfo.new(0.3), {BackgroundColor3 = has and T.green or T.red}):Play()
        end
    end
end

local function addItemRow(name, amount, enabled)
    if name == "" then return end
    amount  = math.clamp(math.floor(tonumber(amount) or 1), 1, cfg.maxAmt)
    if enabled == nil then enabled = true end

    local idx = #itemEntries + 1
    local row = Instance.new("Frame", itemList)
    row.Size             = UDim2.new(1, 0, 0, 38)
    row.BackgroundColor3 = (idx % 2 == 0) and T.card or T.tagBg
    row.BorderSizePixel  = 0; row.LayoutOrder = idx

    -- left accent bar (green=enabled, red=disabled)
    local abar = Instance.new("Frame", row); abar.Size = UDim2.new(0,3,0,22)
    abar.Position = UDim2.new(0,0,0.5,-11); abar.BorderSizePixel = 0
    Instance.new("UICorner", abar).CornerRadius = UDim.new(0, 2)

    local numL = Instance.new("TextLabel", row); numL.Size = UDim2.new(0,20,1,0)
    numL.Position = UDim2.new(0,6,0,0); numL.BackgroundTransparency = 1
    numL.Text = tostring(idx) .. "."; numL.TextColor3 = T.txtMute
    numL.Font = Enum.Font.GothamSemibold; numL.TextSize = 10
    numL.TextXAlignment = Enum.TextXAlignment.Right

    -- inventory dot
    local dot = Instance.new("Frame", row); dot.Size = UDim2.new(0,7,0,7)
    dot.Position = UDim2.new(0,30,0.5,-3.5); dot.BackgroundColor3 = T.txtMute
    dot.BorderSizePixel = 0
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    local nmL = Instance.new("TextLabel", row); nmL.Size = UDim2.new(1,-198,1,0)
    nmL.Position = UDim2.new(0,42,0,0); nmL.BackgroundTransparency = 1
    nmL.Text = name; nmL.TextColor3 = T.txt; nmL.Font = Enum.Font.GothamSemibold
    nmL.TextSize = 12; nmL.TextXAlignment = Enum.TextXAlignment.Left
    nmL.TextTruncate = Enum.TextTruncate.AtEnd

    -- editable qty box
    local qtyBox = Instance.new("TextBox", row); qtyBox.Size = UDim2.new(0,44,0,26)
    qtyBox.Position = UDim2.new(1,-152,0.5,-13); qtyBox.BackgroundColor3 = T.badgeBg
    qtyBox.BorderSizePixel = 0; qtyBox.Text = tostring(amount)
    qtyBox.TextColor3 = T.badgeTx; qtyBox.Font = Enum.Font.GothamBold
    qtyBox.TextSize = 11; qtyBox.ClearTextOnFocus = false
    Instance.new("UICorner", qtyBox).CornerRadius = UDim.new(0, 5)
    Instance.new("UIPadding", qtyBox).PaddingLeft = UDim.new(0, 6)
    local qSt = Instance.new("UIStroke", qtyBox); qSt.Color = T.border; qSt.Thickness = 1
    qtyBox.Focused:Connect(function()  TweenService:Create(qSt, TweenInfo.new(0.15), {Color = T.accent}):Play() end)
    qtyBox.FocusLost:Connect(function()
        TweenService:Create(qSt, TweenInfo.new(0.15), {Color = T.border}):Play()
        local v = tonumber(qtyBox.Text)
        if v then
            v = math.clamp(math.floor(v), 1, cfg.maxAmt)
            qtyBox.Text = tostring(v)
        end
        for _, e in ipairs(itemEntries) do
            if e.qtyBox == qtyBox then e.cfgEntry.amount = tonumber(qtyBox.Text) or 1; break end
        end
        syncCfgItems(); saveAll()
    end)

    -- enable checkbox (Auto Send column, on the LEFT inside the row)
    local enBtn = Instance.new("TextButton", row); enBtn.Size = UDim2.new(0,30,0,26)
    enBtn.Position = UDim2.new(1,-100,0.5,-13); enBtn.BorderSizePixel = 0
    enBtn.Font = Enum.Font.GothamBold; enBtn.TextSize = 14
    Instance.new("UICorner", enBtn).CornerRadius = UDim.new(0, 6)

    local enState = enabled
    local function refreshEn()
        if enState then
            enBtn.BackgroundColor3 = Color3.fromRGB(28,65,38); enBtn.TextColor3 = T.green; enBtn.Text = "✓"
            abar.BackgroundColor3  = T.green
        else
            enBtn.BackgroundColor3 = Color3.fromRGB(58,24,24); enBtn.TextColor3 = T.red;   enBtn.Text = "✕"
            abar.BackgroundColor3  = T.red
        end
    end
    refreshEn()
    enBtn.MouseButton1Click:Connect(function()
        enState = not enState; refreshEn()
        for _, e in ipairs(itemEntries) do
            if e.enBtn == enBtn then e.cfgEntry.enabled = enState; break end
        end
        syncCfgItems(); saveAll()
    end)

    -- remove button
    local remBtn = Instance.new("TextButton", row); remBtn.Size = UDim2.new(0,26,0,26)
    remBtn.Position = UDim2.new(1,-28,0.5,-13); remBtn.BackgroundColor3 = Color3.fromRGB(62,20,20)
    remBtn.Text = "✕"; remBtn.TextColor3 = Color3.fromRGB(210,80,80)
    remBtn.Font = Enum.Font.GothamBold; remBtn.TextSize = 10; remBtn.BorderSizePixel = 0
    Instance.new("UICorner", remBtn).CornerRadius = UDim.new(0, 5)

    local cfgEntry = { name = name, amount = amount, enabled = enState }
    local entryData = { frame = row, dot = dot, qtyBox = qtyBox, enBtn = enBtn, numLbl = numL, cfgEntry = cfgEntry }
    table.insert(itemEntries, entryData)
    syncCfgItems(); refreshEmpty()

    remBtn.MouseButton1Click:Connect(function()
        row:Destroy()
        for i, e in ipairs(itemEntries) do if e == entryData then table.remove(itemEntries, i); break end end
        for i2, e2 in ipairs(itemEntries) do e2.numLbl.Text = tostring(i2) .. "." end
        syncCfgItems(); refreshEmpty(); saveAll()
    end)
    return entryData
end

local function tryAdd()
    local n = nameIn.Text:match("^%s*(.-)%s*$")
    local a = amtIn.Text
    if n == "" then showErr("⚠  Enter an item name."); return end
    local numA = tonumber(a)
    if not numA or a == "" then showErr("⚠  Enter a valid quantity."); return end
    if numA > 100 then showErr("⚠  Max quantity is 100."); return end
    addItemRow(n, a, true); nameIn.Text = ""; amtIn.Text = ""; saveAll()
end
addBtn.MouseButton1Click:Connect(tryAdd)
nameIn.FocusLost:Connect(function(enter) if enter then tryAdd() end end)

-- ── Note ─────────────────────────────────────────────────────────────
secLbl("Note (optional)", 6, mp)
local noteBox = mkIn("Mail note...", 7, mp)
noteBox.FocusLost:Connect(function() cfg.note = noteBox.Text end)

-- ── Interval ─────────────────────────────────────────────────────────
secLbl("Auto send interval", 8, mp)
local intRowF = Instance.new("Frame"); intRowF.Size = UDim2.new(1,0,0,34)
intRowF.BackgroundTransparency = 1; intRowF.LayoutOrder = 9; intRowF.Parent = mp

local intBox = Instance.new("TextBox", intRowF); intBox.Size = UDim2.new(0,76,1,0)
intBox.BackgroundColor3 = T.input; intBox.BorderSizePixel = 0; intBox.Text = "10"
intBox.TextColor3 = T.txt; intBox.Font = Enum.Font.GothamBold; intBox.TextSize = 14
intBox.ClearTextOnFocus = false
Instance.new("UICorner", intBox).CornerRadius = UDim.new(0, 8)
local iSt = Instance.new("UIStroke", intBox); iSt.Color = T.border; iSt.Thickness = 1
Instance.new("UIPadding", intBox).PaddingLeft = UDim.new(0, 12)
intBox.Focused:Connect(function()  TweenService:Create(iSt, TweenInfo.new(0.15), {Color = T.accent}):Play() end)
intBox.FocusLost:Connect(function()
    TweenService:Create(iSt, TweenInfo.new(0.15), {Color = T.border}):Play()
    local v = tonumber(intBox.Text)
    if v and v >= 1 then cfg.interval = v else intBox.Text = tostring(cfg.interval) end
end)

local intSL = Instance.new("TextLabel", intRowF); intSL.Size = UDim2.new(1,-86,1,0)
intSL.Position = UDim2.new(0,84,0,0); intSL.BackgroundTransparency = 1
intSL.Text = "seconds between sends"; intSL.TextColor3 = T.txtMute
intSL.Font = Enum.Font.Gotham; intSL.TextSize = 12; intSL.TextXAlignment = Enum.TextXAlignment.Left

-- ── Auto Send toggle ─────────────────────────────────────────────────
local _, getAutoSend, setAutoSend = mkToggle("Auto Send", 10, mp)

-- ── Send Once ────────────────────────────────────────────────────────
local sendOnceBtn = mkBtn("▶   Send Once", T.accent, 11, mp)

-- ── Log bar ──────────────────────────────────────────────────────────
local logBar = Instance.new("Frame"); logBar.Size = UDim2.new(1,0,0,34)
logBar.BackgroundColor3 = T.card; logBar.BorderSizePixel = 0
logBar.LayoutOrder = 12; logBar.Parent = mp
Instance.new("UICorner", logBar).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", logBar).Color = T.border

local logDot = Instance.new("Frame", logBar); logDot.Size = UDim2.new(0,8,0,8)
logDot.Position = UDim2.new(0,12,0.5,-4); logDot.BackgroundColor3 = T.green
logDot.BorderSizePixel = 0
Instance.new("UICorner", logDot).CornerRadius = UDim.new(1, 0)

local logLbl = Instance.new("TextLabel", logBar); logLbl.Size = UDim2.new(1,-30,1,0)
logLbl.Position = UDim2.new(0,28,0,0); logLbl.BackgroundTransparency = 1
logLbl.Text = "Idle — ready."; logLbl.TextColor3 = T.txtSub
logLbl.Font = Enum.Font.Gotham; logLbl.TextSize = 12
logLbl.TextXAlignment = Enum.TextXAlignment.Left; logLbl.TextTruncate = Enum.TextTruncate.AtEnd

local function setLog(msg, isErr)
    logLbl.Text = msg
    TweenService:Create(logDot, TweenInfo.new(0.2), {BackgroundColor3 = isErr and T.red or T.green}):Play()
    logLbl.TextColor3 = isErr and Color3.fromRGB(240,130,130) or T.txtSub
end

-- ═══════════════════════════════════════════════════════════════════════
-- OUTPUT PAGE
-- ═══════════════════════════════════════════════════════════════════════
local op = outputTab.page
secLbl("Send history (last 10)", 1, op)

local outList = Instance.new("Frame"); outList.Size = UDim2.new(1,0,0,0)
outList.AutomaticSize = Enum.AutomaticSize.Y; outList.BackgroundTransparency = 1
outList.BorderSizePixel = 0; outList.LayoutOrder = 2; outList.Parent = op

local outLL = Instance.new("UIListLayout", outList)
outLL.SortOrder = Enum.SortOrder.LayoutOrder; outLL.Padding = UDim.new(0, 6)

local noHistL = Instance.new("TextLabel", outList); noHistL.Size = UDim2.new(1,0,0,38)
noHistL.BackgroundTransparency = 1; noHistL.Text = "No sends yet."
noHistL.TextColor3 = T.txtMute; noHistL.Font = Enum.Font.Gotham; noHistL.TextSize = 12; noHistL.LayoutOrder = 0

local outFrames = {}

local function rebuildOutput()
    for _, f in ipairs(outFrames) do f:Destroy() end; outFrames = {}
    noHistL.Visible = #outputLog == 0

    for idx, entry in ipairs(outputLog) do
        local card = Instance.new("Frame", outList); card.Size = UDim2.new(1,0,0,0)
        card.AutomaticSize = Enum.AutomaticSize.Y; card.BackgroundColor3 = T.card
        card.BorderSizePixel = 0; card.LayoutOrder = idx
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 9)
        local cst = Instance.new("UIStroke", card)
        cst.Color = entry.success and Color3.fromRGB(38,76,48) or Color3.fromRGB(76,28,28); cst.Thickness = 1

        local cL = Instance.new("UIListLayout", card); cL.SortOrder = Enum.SortOrder.LayoutOrder; cL.Padding = UDim.new(0,2)
        local cP = Instance.new("UIPadding", card)
        cP.PaddingLeft = UDim.new(0,12); cP.PaddingRight = UDim.new(0,12)
        cP.PaddingTop = UDim.new(0,8); cP.PaddingBottom = UDim.new(0,8)

        local hdr = Instance.new("Frame", card); hdr.Size = UDim2.new(1,0,0,20)
        hdr.BackgroundTransparency = 1; hdr.LayoutOrder = 1

        local sdot = Instance.new("Frame", hdr); sdot.Size = UDim2.new(0,9,0,9)
        sdot.Position = UDim2.new(0,0,0.5,-4.5); sdot.BackgroundColor3 = entry.success and T.green or T.red
        sdot.BorderSizePixel = 0
        Instance.new("UICorner", sdot).CornerRadius = UDim.new(1, 0)

        local toLbl = Instance.new("TextLabel", hdr); toLbl.Size = UDim2.new(1,-76,1,0)
        toLbl.Position = UDim2.new(0,16,0,0); toLbl.BackgroundTransparency = 1
        toLbl.Text = "→ " .. entry.to; toLbl.TextColor3 = T.txt
        toLbl.Font = Enum.Font.GothamBold; toLbl.TextSize = 13; toLbl.TextXAlignment = Enum.TextXAlignment.Left

        local tLbl = Instance.new("TextLabel", hdr); tLbl.Size = UDim2.new(0,68,1,0)
        tLbl.Position = UDim2.new(1,-68,0,0); tLbl.BackgroundTransparency = 1
        tLbl.Text = entry.time; tLbl.TextColor3 = T.txtMute
        tLbl.Font = Enum.Font.Code; tLbl.TextSize = 10; tLbl.TextXAlignment = Enum.TextXAlignment.Right

        if #entry.items > 0 then
            local parts = {}
            for _, it in ipairs(entry.items) do table.insert(parts, it.name .. " ×" .. it.amount) end
            local iL = Instance.new("TextLabel", card); iL.Size = UDim2.new(1,0,0,15)
            iL.BackgroundTransparency = 1; iL.Text = "  " .. table.concat(parts, "  ·  ")
            iL.TextColor3 = T.txtSub; iL.Font = Enum.Font.Gotham; iL.TextSize = 11
            iL.TextXAlignment = Enum.TextXAlignment.Left; iL.TextTruncate = Enum.TextTruncate.AtEnd; iL.LayoutOrder = 2
        end
        if #entry.skipped > 0 then
            local sL = Instance.new("TextLabel", card); sL.Size = UDim2.new(1,0,0,13)
            sL.BackgroundTransparency = 1; sL.Text = "  Skipped: " .. table.concat(entry.skipped, ", ")
            sL.TextColor3 = T.orange; sL.Font = Enum.Font.Gotham; sL.TextSize = 10
            sL.TextXAlignment = Enum.TextXAlignment.Left; sL.TextTruncate = Enum.TextTruncate.AtEnd; sL.LayoutOrder = 3
        end
        table.insert(outFrames, card)
    end
end

rebuildOutputFn = rebuildOutput; rebuildOutput()

local clearBtn = mkBtn("🗑   Clear History", T.redDk, 3, op)
clearBtn.MouseButton1Click:Connect(function() outputLog = {}; rebuildOutput() end)

-- ═══════════════════════════════════════════════════════════════════════
-- SETTINGS PAGE
-- ═══════════════════════════════════════════════════════════════════════
local sp = settingTab.page

-- ── Config slots ─────────────────────────────────────────────────────
secLbl("Configs", 1, sp)

local cfgCard = Instance.new("Frame"); cfgCard.Size = UDim2.new(1,0,0,0)
cfgCard.AutomaticSize = Enum.AutomaticSize.Y; cfgCard.BackgroundColor3 = T.card
cfgCard.BorderSizePixel = 0; cfgCard.LayoutOrder = 2; cfgCard.Parent = sp
Instance.new("UICorner", cfgCard).CornerRadius = UDim.new(0, 9)
Instance.new("UIStroke", cfgCard).Color = T.border

local cfgPad = Instance.new("UIPadding", cfgCard)
cfgPad.PaddingLeft = UDim.new(0,12); cfgPad.PaddingRight = UDim.new(0,12)
cfgPad.PaddingTop = UDim.new(0,10); cfgPad.PaddingBottom = UDim.new(0,10)

local cfgL = Instance.new("UIListLayout", cfgCard)
cfgL.SortOrder = Enum.SortOrder.LayoutOrder; cfgL.Padding = UDim.new(0, 8)

-- Config name input
local cfgNRow = Instance.new("Frame", cfgCard); cfgNRow.Size = UDim2.new(1,0,0,34)
cfgNRow.BackgroundTransparency = 1; cfgNRow.LayoutOrder = 1

local cfgNLabel = Instance.new("TextLabel", cfgNRow); cfgNLabel.Size = UDim2.new(0,86,1,0)
cfgNLabel.BackgroundTransparency = 1; cfgNLabel.Text = "Config name"
cfgNLabel.TextColor3 = T.txtSub; cfgNLabel.Font = Enum.Font.Gotham; cfgNLabel.TextSize = 12
cfgNLabel.TextXAlignment = Enum.TextXAlignment.Left

local cfgNameBox = Instance.new("TextBox", cfgNRow); cfgNameBox.Size = UDim2.new(1,-94,0,30)
cfgNameBox.Position = UDim2.new(0,92,0.5,-15); cfgNameBox.BackgroundColor3 = T.input
cfgNameBox.BorderSizePixel = 0; cfgNameBox.PlaceholderText = "e.g.  main"
cfgNameBox.PlaceholderColor3 = T.txtMute; cfgNameBox.Text = ""
cfgNameBox.TextColor3 = T.txt; cfgNameBox.Font = Enum.Font.Gotham; cfgNameBox.TextSize = 13
cfgNameBox.ClearTextOnFocus = false
Instance.new("UICorner", cfgNameBox).CornerRadius = UDim.new(0, 7)
local cnSt = Instance.new("UIStroke", cfgNameBox); cnSt.Color = T.border; cnSt.Thickness = 1
Instance.new("UIPadding", cfgNameBox).PaddingLeft = UDim.new(0, 10)
cfgNameBox.Focused:Connect(function()  TweenService:Create(cnSt, TweenInfo.new(0.15), {Color = T.accent}):Play() end)
cfgNameBox.FocusLost:Connect(function() TweenService:Create(cnSt, TweenInfo.new(0.15), {Color = T.border}):Play() end)

-- Saved list header
local savedHdr = Instance.new("TextLabel", cfgCard); savedHdr.Size = UDim2.new(1,0,0,13)
savedHdr.BackgroundTransparency = 1; savedHdr.Text = "SAVED CONFIGS"
savedHdr.TextColor3 = T.txtMute; savedHdr.Font = Enum.Font.GothamSemibold
savedHdr.TextSize = 9; savedHdr.TextXAlignment = Enum.TextXAlignment.Left; savedHdr.LayoutOrder = 2

-- Saved configs list
local savedList = Instance.new("Frame", cfgCard); savedList.Size = UDim2.new(1,0,0,0)
savedList.AutomaticSize = Enum.AutomaticSize.Y; savedList.BackgroundTransparency = 1; savedList.LayoutOrder = 3
local slL = Instance.new("UIListLayout", savedList); slL.SortOrder = Enum.SortOrder.LayoutOrder; slL.Padding = UDim.new(0,4)

local noSaved = Instance.new("TextLabel", savedList); noSaved.Size = UDim2.new(1,0,0,24)
noSaved.BackgroundTransparency = 1; noSaved.Text = "No configs saved yet."
noSaved.TextColor3 = T.txtMute; noSaved.Font = Enum.Font.Gotham; noSaved.TextSize = 11

local cfgRowFrames = {}
local selectedCfgName = ""   -- currently highlighted config

local function applyConfigData(data)
    -- clear current items
    for _, e in ipairs(itemEntries) do e.frame:Destroy() end
    itemEntries = {}; syncCfgItems(); refreshEmpty()
    -- apply fields
    if data.username then usernameBox.Text = data.username; cfg.username = data.username end
    if data.note     then noteBox.Text = data.note; cfg.note = data.note end
    if data.interval then intBox.Text = tostring(data.interval); cfg.interval = data.interval end
    if type(data.items) == "table" then
        for _, it in ipairs(data.items) do addItemRow(it.name, it.amount, it.enabled ~= false) end
    end
end

local rebuildSavedListFn  -- forward declare

local function rebuildSavedList()
    for _, f in ipairs(cfgRowFrames) do f:Destroy() end; cfgRowFrames = {}
    local any = false
    for name, _ in pairs(configs) do
        any = true
        local row = Instance.new("Frame", savedList); row.Size = UDim2.new(1,0,0,32)
        row.BackgroundColor3 = T.surface; row.BorderSizePixel = 0
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
        local rowSt = Instance.new("UIStroke", row)
        rowSt.Thickness = 1

        -- Selected highlight
        local function refreshRowSel()
            if selectedCfgName == name then
                row.BackgroundColor3 = Color3.fromRGB(28,40,70)
                rowSt.Color = T.accent
            else
                row.BackgroundColor3 = T.surface
                rowSt.Color = T.border
            end
        end
        refreshRowSel()

        -- Selection dot
        local selDot = Instance.new("Frame", row); selDot.Size = UDim2.new(0,6,0,6)
        selDot.Position = UDim2.new(0,6,0.5,-3); selDot.BorderSizePixel = 0
        Instance.new("UICorner", selDot).CornerRadius = UDim.new(1,0)

        local function refreshDot()
            selDot.BackgroundColor3 = selectedCfgName == name and T.accent or T.border
        end
        refreshDot()

        local nLbl = Instance.new("TextLabel", row); nLbl.Size = UDim2.new(1,-82,1,0)
        nLbl.Position = UDim2.new(0,18,0,0); nLbl.BackgroundTransparency = 1
        nLbl.Text = name; nLbl.TextColor3 = T.txt; nLbl.Font = Enum.Font.GothamSemibold
        nLbl.TextSize = 12; nLbl.TextXAlignment = Enum.TextXAlignment.Left

        -- Select on click (anywhere on row)
        local selHit = Instance.new("TextButton", row); selHit.Size = UDim2.new(1,-80,1,0)
        selHit.BackgroundTransparency = 1; selHit.Text = ""
        selHit.MouseButton1Click:Connect(function()
            selectedCfgName = name; cfg.selectedCfg = name
            -- refresh all rows
            for _, f in ipairs(cfgRowFrames) do
                local rn = f:FindFirstChildWhichIsA("TextLabel")
                if rn then
                    if rn.Text == name then
                        f.BackgroundColor3 = Color3.fromRGB(28,40,70)
                        local st = f:FindFirstChildOfClass("UIStroke")
                        if st then st.Color = T.accent end
                        local sd = f:FindFirstChildWhichIsA("Frame")
                        if sd then sd.BackgroundColor3 = T.accent end
                    else
                        f.BackgroundColor3 = T.surface
                        local st = f:FindFirstChildOfClass("UIStroke")
                        if st then st.Color = T.border end
                        local sd = f:FindFirstChildWhichIsA("Frame")
                        if sd then sd.BackgroundColor3 = T.border end
                    end
                end
            end
            saveAll()
        end)

        local loadB = Instance.new("TextButton", row); loadB.Size = UDim2.new(0,44,0,22)
        loadB.Position = UDim2.new(1,-76,0.5,-11); loadB.BackgroundColor3 = T.accent
        loadB.Text = "Load"; loadB.TextColor3 = Color3.new(1,1,1)
        loadB.Font = Enum.Font.GothamBold; loadB.TextSize = 10; loadB.BorderSizePixel = 0
        Instance.new("UICorner", loadB).CornerRadius = UDim.new(0,5)
        loadB.MouseButton1Click:Connect(function()
            local saved = configs[name]; if not saved then return end
            applyConfigData(saved)
            selectedCfgName = name; cfg.selectedCfg = name
            saveAll(); rebuildSavedList()
            setLog("Loaded config: " .. name)
        end)

        local delB = Instance.new("TextButton", row); delB.Size = UDim2.new(0,26,0,22)
        delB.Position = UDim2.new(1,-26,0.5,-11); delB.BackgroundColor3 = T.redDk
        delB.Text = "✕"; delB.TextColor3 = Color3.fromRGB(220,90,90)
        delB.Font = Enum.Font.GothamBold; delB.TextSize = 10; delB.BorderSizePixel = 0
        Instance.new("UICorner", delB).CornerRadius = UDim.new(0,5)
        delB.MouseButton1Click:Connect(function()
            configs[name] = nil
            if selectedCfgName == name then selectedCfgName = ""; cfg.selectedCfg = "" end
            saveAll(); rebuildSavedList()
        end)

        table.insert(cfgRowFrames, row)
    end
    noSaved.Visible = not any
end

rebuildSavedListFn = rebuildSavedList

-- Save config button
local saveCfgBtn = mkBtn("💾   Save Config", T.green, 4, cfgCard)
saveCfgBtn.LayoutOrder = 4
saveCfgBtn.MouseButton1Click:Connect(function()
    local n = cfgNameBox.Text:match("^%s*(.-)%s*$")
    if n == "" then setLog("⚠  Enter a config name.", true); return end
    syncCfgItems()
    configs[n] = {
        username = usernameBox.Text,
        note     = noteBox.Text,
        interval = tonumber(intBox.Text) or 10,
        items    = deepCopy(cfg.items),
    }
    selectedCfgName = n; cfg.selectedCfg = n
    saveAll(); rebuildSavedList()
    saveCfgBtn.Text = "✓  Saved!"
    task.delay(1.5, function() if saveCfgBtn and saveCfgBtn.Parent then saveCfgBtn.Text = "💾   Save Config" end end)
end)

rebuildSavedList()

-- Auto Load Selected toggle
local _, getAutoLoad, setAutoLoad = mkToggle("Auto Load Selected on Start", 5, cfgCard)
setAutoLoad(cfg.autoLoad)
task.spawn(function()
    while gui.Parent do
        local v = getAutoLoad(); if v ~= cfg.autoLoad then cfg.autoLoad = v; saveAll() end
        task.wait(0.5)
    end
end)

-- ── Window size ───────────────────────────────────────────────────────
secLbl("Window size", 6, sp)

local szCard = Instance.new("Frame"); szCard.Size = UDim2.new(1,0,0,0)
szCard.AutomaticSize = Enum.AutomaticSize.Y; szCard.BackgroundColor3 = T.card
szCard.BorderSizePixel = 0; szCard.LayoutOrder = 7; szCard.Parent = sp
Instance.new("UICorner", szCard).CornerRadius = UDim.new(0,9)
Instance.new("UIStroke", szCard).Color = T.border

local szPad = Instance.new("UIPadding", szCard)
szPad.PaddingLeft = UDim.new(0,12); szPad.PaddingRight = UDim.new(0,12)
szPad.PaddingTop = UDim.new(0,10); szPad.PaddingBottom = UDim.new(0,10)

local szL = Instance.new("UIListLayout", szCard); szL.SortOrder = Enum.SortOrder.LayoutOrder; szL.Padding = UDim.new(0,8)

local function sizeRow(lbl, minV, maxV, defV, ord, cb)
    local row = Instance.new("Frame", szCard); row.Size = UDim2.new(1,0,0,28)
    row.BackgroundTransparency = 1; row.LayoutOrder = ord

    local l = Instance.new("TextLabel", row); l.Size = UDim2.new(0.52,0,1,0)
    l.BackgroundTransparency = 1; l.Text = lbl; l.TextColor3 = T.txt
    l.Font = Enum.Font.Gotham; l.TextSize = 12; l.TextXAlignment = Enum.TextXAlignment.Left

    local box = Instance.new("TextBox", row); box.Size = UDim2.new(0,68,0,26)
    box.Position = UDim2.new(0.54,0,0.5,-13); box.BackgroundColor3 = T.input
    box.BorderSizePixel = 0; box.Text = tostring(defV); box.TextColor3 = T.txt
    box.Font = Enum.Font.GothamBold; box.TextSize = 12; box.ClearTextOnFocus = false
    Instance.new("UICorner", box).CornerRadius = UDim.new(0,6)
    local bSt = Instance.new("UIStroke", box); bSt.Color = T.border; bSt.Thickness = 1
    Instance.new("UIPadding", box).PaddingLeft = UDim.new(0,8)
    box.Focused:Connect(function()  TweenService:Create(bSt, TweenInfo.new(0.15), {Color = T.accent}):Play() end)
    box.FocusLost:Connect(function()
        TweenService:Create(bSt, TweenInfo.new(0.15), {Color = T.border}):Play()
        local v = tonumber(box.Text)
        if v then cb(math.clamp(v, minV, maxV)) end
    end)

    local apB = Instance.new("TextButton", row); apB.Size = UDim2.new(0,50,0,26)
    apB.Position = UDim2.new(1,-50,0.5,-13); apB.BackgroundColor3 = T.accent
    apB.Text = "Apply"; apB.TextColor3 = Color3.new(1,1,1)
    apB.Font = Enum.Font.GothamBold; apB.TextSize = 10; apB.BorderSizePixel = 0
    Instance.new("UICorner", apB).CornerRadius = UDim.new(0,6)
    apB.MouseButton1Click:Connect(function()
        local v = tonumber(box.Text)
        if v then box.Text = tostring(math.clamp(v,minV,maxV)); cb(tonumber(box.Text)) end
    end)
end

sizeRow("Width  (340–700)",  340, 700, cfg.winW, 1, function(v) cfg.winW = v; win.Size = UDim2.new(0,cfg.winW,0,cfg.winH) end)
sizeRow("Height  (380–700)", 380, 700, cfg.winH, 2, function(v) cfg.winH = v; win.Size = UDim2.new(0,cfg.winW,0,cfg.winH) end)

-- ── Send limit ────────────────────────────────────────────────────────
secLbl("Send limit", 8, sp)

local limCard = Instance.new("Frame"); limCard.Size = UDim2.new(1,0,0,50)
limCard.BackgroundColor3 = T.card; limCard.BorderSizePixel = 0; limCard.LayoutOrder = 9; limCard.Parent = sp
Instance.new("UICorner", limCard).CornerRadius = UDim.new(0,9)
Instance.new("UIStroke", limCard).Color = T.border

local llbl = Instance.new("TextLabel", limCard); llbl.Size = UDim2.new(1,-90,0,20)
llbl.Position = UDim2.new(0,12,0,7); llbl.BackgroundTransparency = 1; llbl.Text = "Max qty per item"
llbl.TextColor3 = T.txt; llbl.Font = Enum.Font.GothamSemibold; llbl.TextSize = 12; llbl.TextXAlignment = Enum.TextXAlignment.Left
local ldsc = Instance.new("TextLabel", limCard); ldsc.Size = UDim2.new(1,-90,0,14)
ldsc.Position = UDim2.new(0,12,0,28); ldsc.BackgroundTransparency = 1; ldsc.Text = "Hard cap: 100 for safety"
ldsc.TextColor3 = T.txtMute; ldsc.Font = Enum.Font.Gotham; ldsc.TextSize = 10; ldsc.TextXAlignment = Enum.TextXAlignment.Left

local limBox = Instance.new("TextBox", limCard); limBox.Size = UDim2.new(0,58,0,28)
limBox.Position = UDim2.new(1,-70,0.5,-14); limBox.BackgroundColor3 = T.input
limBox.BorderSizePixel = 0; limBox.Text = tostring(cfg.maxAmt)
limBox.TextColor3 = T.txt; limBox.Font = Enum.Font.GothamBold; limBox.TextSize = 12; limBox.ClearTextOnFocus = false
Instance.new("UICorner", limBox).CornerRadius = UDim.new(0,6)
local lmSt = Instance.new("UIStroke", limBox); lmSt.Color = T.border; lmSt.Thickness = 1
Instance.new("UIPadding", limBox).PaddingLeft = UDim.new(0,8)
limBox.Focused:Connect(function()  TweenService:Create(lmSt, TweenInfo.new(0.15), {Color = T.accent}):Play() end)
limBox.FocusLost:Connect(function()
    TweenService:Create(lmSt, TweenInfo.new(0.15), {Color = T.border}):Play()
    local v = tonumber(limBox.Text)
    if v then cfg.maxAmt = math.clamp(v, 1, 100); limBox.Text = tostring(cfg.maxAmt) end
end)

-- ── Discord Webhook ───────────────────────────────────────────────────
secLbl("Discord Webhook", 10, sp)
local webhookBox = mkIn("https://discord.com/api/webhooks/...", 11, sp)
webhookBox.FocusLost:Connect(function() cfg.webhook = webhookBox.Text end)

local testWH = mkBtn("🔔   Test Webhook", Color3.fromRGB(88,101,242), 12, sp)
testWH.MouseButton1Click:Connect(function()
    if cfg.webhook == "" then setLog("⚠  No webhook URL.", true); return end
    pcall(function()
        local body = HttpService:JSONEncode({ embeds = {{ title = "✅  Webhook Test — Auto Send Mailbox", color = 3066993,
            description = "Webhook is connected and working!", footer = { text = "Auto Send Mailbox v4.0" } }} })
        local req = (syn and syn.request) or (http and http.request) or request
        if req then req({ Url = cfg.webhook, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body }) end
    end)
end)

local _, getWHon, setWHon = mkToggle("Send to webhook on each send", 13, sp)
setWHon(cfg.webhookOn)
task.spawn(function()
    while gui.Parent do
        local v = getWHon(); if v ~= cfg.webhookOn then cfg.webhookOn = v; saveAll() end
        task.wait(0.5)
    end
end)

-- ── About ─────────────────────────────────────────────────────────────
secLbl("About", 14, sp)
local aCard = Instance.new("Frame"); aCard.Size = UDim2.new(1,0,0,56)
aCard.BackgroundColor3 = T.card; aCard.BorderSizePixel = 0; aCard.LayoutOrder = 15; aCard.Parent = sp
Instance.new("UICorner", aCard).CornerRadius = UDim.new(0,9)
Instance.new("UIStroke", aCard).Color = T.border
local aLbl = Instance.new("TextLabel", aCard); aLbl.Size = UDim2.new(1,-20,1,0)
aLbl.Position = UDim2.new(0,12,0,0); aLbl.BackgroundTransparency = 1
aLbl.Text = "Auto Send Mailbox  v4.0\nLoops enabled items · skips items not in inventory.\nMax 20 entries per batch · Hard item cap: 100."
aLbl.TextColor3 = T.txtMute; aLbl.Font = Enum.Font.Gotham; aLbl.TextSize = 10
aLbl.TextXAlignment = Enum.TextXAlignment.Left; aLbl.TextYAlignment = Enum.TextYAlignment.Center

-- ═══════════════════════════════════════════════════════════════════════
-- AUTO-SEND LOGIC
-- ═══════════════════════════════════════════════════════════════════════
local autoRunning   = false
local autoThread    = nil
local itemLoopIndex = 1

sendOnceBtn.MouseButton1Click:Connect(function()
    syncCfgItems(); cfg.username = usernameBox.Text; cfg.note = noteBox.Text
    -- check there are enabled items
    local hasEnabled = false
    for _, e in ipairs(cfg.items) do if e.enabled then hasEnabled = true; break end end
    if not hasEnabled then setLog("⚠  No items enabled to send.", true); return end
    setLog("Sending all enabled items...")
    task.spawn(function()
        local ok, err = pcall(function() doSendAll(setLog) end)
        if not ok then setLog("Error: " .. tostring(err), true) end
    end)
end)

local function stopAuto()
    autoRunning = false
    if autoThread then task.cancel(autoThread); autoThread = nil end
    setLog("Auto send stopped.")
end

local function startAuto()
    -- validate before starting
    syncCfgItems(); cfg.username = usernameBox.Text
    if cfg.username == "" then setLog("⚠  No username set.", true); setAutoSend(false); return end
    local hasEnabled = false
    for _, e in ipairs(cfg.items) do if e.enabled then hasEnabled = true; break end end
    if not hasEnabled then setLog("⚠  No items enabled — check ✓ box per item.", true); setAutoSend(false); return end

    autoRunning    = true
    itemLoopIndex  = 1
    autoThread = task.spawn(function()
        while autoRunning do
            syncCfgItems(); cfg.username = usernameBox.Text; cfg.note = noteBox.Text
            cfg.interval = tonumber(intBox.Text) or 10

            local inv = getInv()
            if inv then updateDots(inv) end

            local active = {}
            for _, e in ipairs(cfg.items) do if e.enabled then table.insert(active, e) end end

            if #active == 0 then
                setLog("⚠  No enabled items.", true); task.wait(cfg.interval); continue
            end

            if itemLoopIndex > #active then itemLoopIndex = 1 end

            local entry = active[itemLoopIndex]
            inv = getInv()
            if inv then
                if hasItem(inv, entry.name) then
                    setLog("[" .. itemLoopIndex .. "/" .. #active .. "] Sending: " .. entry.name .. " ×" .. tostring(entry.amount) .. "...")
                    local worked, wasSkip = doSendEntry(entry, setLog)
                    if worked then
                        pushLog(cfg.username, {entry}, {}, true)
                        sendWebhook(cfg.username, {entry}, {}, true)
                        saveAll()
                    elseif not wasSkip then
                        pushLog(cfg.username, {}, {entry.name}, false)
                    end
                else
                    setLog("⏭  [" .. itemLoopIndex .. "/" .. #active .. "] " .. entry.name .. " not in inv, skipping...", true)
                end
            end

            itemLoopIndex = itemLoopIndex % #active + 1
            task.wait(cfg.interval)
        end
    end)
end

-- Sync toggle → auto logic
task.spawn(function()
    while gui.Parent do
        if getAutoSend() and not autoRunning then
            startAuto()
        elseif not getAutoSend() and autoRunning then
            stopAuto()
        end
        task.wait(0.5)
    end
end)

-- Periodic dot refresh
task.spawn(function()
    while gui.Parent do
        task.wait(6)
        local ok, inv = pcall(getInv)
        if ok and inv then updateDots(inv) end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════
-- LOAD SAVED CONFIG ON START
-- ═══════════════════════════════════════════════════════════════════════
if loadAll() then
    usernameBox.Text = cfg.username
    noteBox.Text     = cfg.note
    intBox.Text      = tostring(cfg.interval)
    limBox.Text      = tostring(cfg.maxAmt)
    if cfg.webhook ~= "" then webhookBox.Text = cfg.webhook end
    setWHon(cfg.webhookOn)
    setAutoLoad(cfg.autoLoad)
    win.Size     = UDim2.new(0, cfg.winW, 0, cfg.winH)
    win.Position = UDim2.new(0.5, -cfg.winW/2, 0.5, -cfg.winH/2)
    selectedCfgName = cfg.selectedCfg or ""
    -- restore last items (not from a named config, just the raw last state)
    for _, it in ipairs(cfg.items) do
        addItemRow(it.name, it.amount, it.enabled ~= false)
    end
    rebuildSavedList()
    -- auto-load selected config if toggle is on
    if cfg.autoLoad and cfg.selectedCfg ~= "" and configs[cfg.selectedCfg] then
        applyConfigData(configs[cfg.selectedCfg])
        setLog("Auto-loaded config: " .. cfg.selectedCfg)
    else
        setLog("Config restored from last session.")
    end
else
    setLog("Ready — add items and send.")
end
