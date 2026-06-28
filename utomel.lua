-- Auto Send Mailbox GUI v7.1 (Modified)
-- loadstring(game:HttpGet("URL_HERE",true))()

local RS           = game:GetService("ReplicatedStorage")
local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local HttpService  = game:GetService("HttpService")
local LocalPlayer  = Players.LocalPlayer

-- ═══════════════════════════════════════════════════════════════════════
-- DEFAULT ITEMS (always pre-loaded)
-- ═══════════════════════════════════════════════════════════════════════
local DEFAULT_ITEMS = {
    { name = "Uncommon Sprinkler",  amount = 100, autoSend = true },
    { name = "Trowel",              amount = 100, autoSend = true },
    { name = "Rare Sprinkler",      amount = 100, autoSend = true },
    { name = "Gnome",               amount = 100, autoSend = true },
    { name = "Legendary Sprinkler", amount = 100, autoSend = true },
    { name = "Super Sprinkler",     amount = 100, autoSend = true },
    { name = "Ladder Crate",        amount = 100, autoSend = true },
    { name = "Super Watering Can",  amount = 100, autoSend = true },
}

-- ═══════════════════════════════════════════════════════════════════════
-- SAVE / LOAD
-- ═══════════════════════════════════════════════════════════════════════
local SAVE_KEY = "ASM_v7"

local cfg = {
    username        = "",
    items           = {},
    note            = "",
    interval        = 10,
    maxAmt          = 500,
    webhook         = "",
    webhookOn       = false,
    winW            = 620,
    winH            = 500,
    confirmOnce     = true,   -- NEW: show confirmation before Send Once
    clearAfterOnce  = true,   -- NEW: clear recipient after Send Once
}

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}; for k,v in pairs(t) do c[k] = deepCopy(v) end; return c
end

local function saveAll()
    getgenv()[SAVE_KEY] = { cfg = deepCopy(cfg) }
end

local function loadAll()
    local d = getgenv()[SAVE_KEY]
    if type(d) ~= "table" then return false end
    if type(d.cfg) == "table" then for k,v in pairs(d.cfg) do cfg[k] = v end end
    return true
end

-- ═══════════════════════════════════════════════════════════════════════
-- GAME LOGIC
-- ═══════════════════════════════════════════════════════════════════════
local STACK = {
    Sprinklers=1,WateringCans=1,Mushrooms=1,Gnomes=1,Raccoons=1,Crates=1,
    SeedPacks=1,Trowels=1,Props=1,Seeds=1,HarvestedFruits=1,Flashbangs=1,EmptyPots=1,
}

local function safeNet() return require(RS:WaitForChild("SharedModules"):WaitForChild("Networking")) end
local function safePS()  return require(RS:WaitForChild("ClientModules"):WaitForChild("PlayerStateClient")) end

local function getInv()
    local ok, r = pcall(function() return safePS():WaitForLocalReplica(5) end)
    return ok and r and r.Data and type(r.Data.Inventory) == "table" and r.Data.Inventory
end

local function hasItem(inv, name)
    if type(inv.Pets) == "table" then
        for _, p in pairs(inv.Pets) do
            if type(p)=="table" and p.Id and not p.Equipped and tostring(p.Name)==name then return true end
        end
    end
    for cat in pairs(STACK) do
        local t = inv[cat]
        if type(t)=="table" and type(t[name])=="number" and t[name]>0 then return true end
    end
    return false
end

-- NEW: get how many of an item the player has in inventory
local function getItemCount(inv, name)
    if not inv then return 0 end
    local total = 0
    if type(inv.Pets) == "table" then
        for _, p in pairs(inv.Pets) do
            if type(p)=="table" and p.Id and not p.Equipped and tostring(p.Name)==name then
                total += 1
            end
        end
    end
    for cat in pairs(STACK) do
        local t = inv[cat]
        if type(t)=="table" and type(t[name])=="number" and t[name]>0 then
            total += t[name]
        end
    end
    return total
end

local function buildBatch(inv, entry)
    local out, want = {}, math.clamp(math.floor(entry.amount or 1), 1, cfg.maxAmt)
    if type(inv.Pets) == "table" then
        for key, p in pairs(inv.Pets) do
            if want <= 0 then break end
            if type(p)=="table" and p.Id and not p.Equipped and tostring(p.Name)==entry.name then
                out[#out+1] = {Category="Pets", ItemKey=key, Count=1}; want -= 1
            end
        end
    end
    if want > 0 then
        for cat in pairs(STACK) do
            local t = inv[cat]
            if type(t)=="table" and type(t[entry.name])=="number" and t[entry.name]>0 then
                out[#out+1] = {Category=cat, ItemKey=entry.name, Count=math.min(want,t[entry.name])}; break
            end
        end
    end
    return out
end

local function sendEntry(entry, logFn)
    if cfg.username == "" then logFn("⚠  No username set.", true); return false, false end
    local inv = getInv()
    if not inv then logFn("⚠  No inventory.", true); return false, false end
    if not hasItem(inv, entry.name) then return false, true end
    local batch = buildBatch(inv, entry)
    if #batch == 0 then return false, true end
    local Net = safeNet()
    local ok, uid = pcall(function() return Net.Mailbox.LookupPlayer:Fire(cfg.username) end)
    if not ok or type(uid)~="number" or uid<=0 then logFn("⚠  Lookup failed.", true); return false, false end
    local _, suc = pcall(function() return Net.Mailbox.SendBatch:Fire(uid, batch, cfg.note or "") end)
    return suc == true, false
end

-- ═══════════════════════════════════════════════════════════════════════
-- DISCORD WEBHOOK
-- ═══════════════════════════════════════════════════════════════════════
local function sendWebhook(to, sentItems, skippedNames, success, mode)
    if cfg.webhook == "" or not cfg.webhookOn then return end
    local now    = os.date("%Y-%m-%d %H:%M:%S")
    local sender = LocalPlayer.Name
    local color  = success and 3066993 or 15158332
    local modeTag = mode and ("**["..mode.."]**  ") or ""

    local sentLines = {}
    for _, e in ipairs(sentItems) do
        sentLines[#sentLines+1] = "` "..e.name.." `  ×"..tostring(e.amount)
    end
    local skipLines = {}
    for _, s in ipairs(skippedNames) do skipLines[#skipLines+1] = "` "..s.." `" end

    local embed = {
        title = (success and "✅" or "❌").."  "..modeTag..(success and "Items Sent" or "Send Failed"),
        color = color,
        description = table.concat({
            "```ansi",
            "\27[0;34mSender  \27[0m→  "..sender,
            "\27[0;34mTarget  \27[0m→  "..to,
            "```",
        }, "\n"),
        fields = {
            {
                name   = "📦  Sent  ("..#sentItems..")",
                value  = #sentLines > 0 and table.concat(sentLines, "\n") or "_nothing sent_",
                inline = true,
            },
            {
                name   = "⏭  Skipped  ("..#skippedNames..")",
                value  = #skipLines > 0 and table.concat(skipLines, "\n") or "_none skipped_",
                inline = true,
            },
        },
        footer    = { text = "Auto Send Mailbox  v7.1  •  "..now },
        thumbnail = {
            url = "https://www.roblox.com/headshot-thumbnail/image?userId="
                  ..tostring(LocalPlayer.UserId).."&width=48&height=48&format=png"
        },
    }

    pcall(function()
        local body = HttpService:JSONEncode({ embeds = { embed } })
        local req  = (syn and syn.request) or (http and http.request) or request
        if req then req({ Url=cfg.webhook, Method="POST", Headers={["Content-Type"]="application/json"}, Body=body }) end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════
-- OUTPUT LOG
-- ═══════════════════════════════════════════════════════════════════════
local outputLog       = {}
local MAX_LOG         = 10
local rebuildOutputFn = nil

local function pushLog(to, sent, skipped, success, mode)
    table.insert(outputLog, 1, {
        time    = os.date("%H:%M:%S"),
        to      = to,
        items   = deepCopy(sent),
        skipped = deepCopy(skipped),
        success = success,
        mode    = mode or "Auto",
    })
    while #outputLog > MAX_LOG do table.remove(outputLog) end
    if rebuildOutputFn then rebuildOutputFn() end
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
    blue    = Color3.fromRGB(55, 115, 230),
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
local winStk = Instance.new("UIStroke", win); winStk.Color = T.border; winStk.Thickness = 1.5

-- animated rainbow top bar
local topBar = Instance.new("Frame", win)
topBar.Size = UDim2.new(1,0,0,3); topBar.BackgroundColor3 = T.accent; topBar.BorderSizePixel = 0; topBar.ZIndex = 10
local topG = Instance.new("UIGradient", topBar)
topG.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(100,140,255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150,80,235)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(52,195,105)),
}
task.spawn(function()
    local t = 0
    while gui.Parent do t += task.wait(0.016); topG.Offset = Vector2.new(math.sin(t*0.4)*0.5, 0) end
end)

-- ── Title bar ────────────────────────────────────────────────────────
local TH = 44
local titleBar = Instance.new("Frame", win)
titleBar.Size = UDim2.new(1,0,0,TH); titleBar.Position = UDim2.new(0,0,0,3)
titleBar.BackgroundColor3 = T.surface; titleBar.BorderSizePixel = 0; titleBar.ZIndex = 4
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 13)
local tbFix = Instance.new("Frame", titleBar)
tbFix.Size = UDim2.new(1,0,0,13); tbFix.Position = UDim2.new(0,0,1,-13)
tbFix.BackgroundColor3 = T.surface; tbFix.BorderSizePixel = 0

local pill = Instance.new("Frame", titleBar)
pill.Size = UDim2.new(0,22,0,14); pill.Position = UDim2.new(0,14,0.5,-7)
pill.BackgroundColor3 = T.accent; pill.BorderSizePixel = 0
Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
local pillG = Instance.new("UIGradient", pill)
pillG.Color = ColorSequence.new{ColorSequenceKeypoint.new(0,T.accent), ColorSequenceKeypoint.new(1,T.purple)}

local titleLbl = Instance.new("TextLabel", titleBar)
titleLbl.Size = UDim2.new(1,-120,1,0); titleLbl.Position = UDim2.new(0,44,0,0)
titleLbl.BackgroundTransparency = 1; titleLbl.Text = "Auto Send Mailbox"
titleLbl.TextColor3 = T.txt; titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 14; titleLbl.TextXAlignment = Enum.TextXAlignment.Left

local function mkTitleBtn(lbl, col, ox)
    local b = Instance.new("TextButton", titleBar)
    b.Size = UDim2.new(0,26,0,26); b.Position = UDim2.new(1,ox,0.5,-13)
    b.BackgroundColor3 = col; b.Text = lbl; b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold; b.TextSize = 13; b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseEnter:Connect(function() TweenService:Create(b,TweenInfo.new(0.12),{BackgroundColor3=col:Lerp(Color3.new(1,1,1),0.18)}):Play() end)
    b.MouseLeave:Connect(function() TweenService:Create(b,TweenInfo.new(0.12),{BackgroundColor3=col}):Play() end)
    return b
end

local hideBtn  = mkTitleBtn("−", Color3.fromRGB(55,125,60), -64)
local closeBtn = mkTitleBtn("✕", T.red, -32)
closeBtn.MouseButton1Click:Connect(function() saveAll(); gui:Destroy() end)

-- ═══════════════════════════════════════════════════════════════════════
-- MINI RESTORE BUTTON
-- ═══════════════════════════════════════════════════════════════════════
local miniBtn = Instance.new("TextButton", gui)
miniBtn.Size             = UDim2.new(0, 54, 0, 54)
miniBtn.Position         = UDim2.new(0, 20, 0.5, -27)
miniBtn.BackgroundColor3 = T.accent
miniBtn.Text             = "📬"
miniBtn.TextSize         = 24
miniBtn.Font             = Enum.Font.GothamBold
miniBtn.BorderSizePixel  = 0
miniBtn.Visible          = false
miniBtn.ZIndex           = 20
Instance.new("UICorner", miniBtn).CornerRadius = UDim.new(0, 14)
local miniStroke = Instance.new("UIStroke", miniBtn)
miniStroke.Color     = T.accentL
miniStroke.Thickness = 2

local miniTip = Instance.new("TextLabel", miniBtn)
miniTip.Size = UDim2.new(1,0,0,14)
miniTip.Position = UDim2.new(0,0,1,4)
miniTip.BackgroundTransparency = 1
miniTip.Text = "Click to open"
miniTip.TextColor3 = T.txtMute
miniTip.Font = Enum.Font.Gotham
miniTip.TextSize = 9
miniTip.ZIndex = 21

local miniDragging   = false
local miniDragStart  = nil
local miniStartPos   = nil
local miniMoved      = false
local DRAG_THRESHOLD = 5

miniBtn.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
    or inp.UserInputType == Enum.UserInputType.Touch then
        miniDragging  = true
        miniMoved     = false
        miniDragStart = Vector2.new(inp.Position.X, inp.Position.Y)
        miniStartPos  = miniBtn.Position
    end
end)

UIS.InputChanged:Connect(function(inp)
    if miniDragging and (inp.UserInputType == Enum.UserInputType.MouseMovement
                      or inp.UserInputType == Enum.UserInputType.Touch) then
        local delta = Vector2.new(inp.Position.X, inp.Position.Y) - miniDragStart
        if math.abs(delta.X) > DRAG_THRESHOLD or math.abs(delta.Y) > DRAG_THRESHOLD then
            miniMoved = true
        end
        if miniMoved then
            local vp = game:GetService("Workspace").CurrentCamera.ViewportSize
            local bW, bH = miniBtn.AbsoluteSize.X, miniBtn.AbsoluteSize.Y
            local newX = math.clamp(miniStartPos.X.Offset + delta.X, 0, vp.X - bW)
            local newY = math.clamp(miniStartPos.Y.Offset + delta.Y, 0, vp.Y - bH)
            miniBtn.Position = UDim2.new(0, newX, 0, newY)
        end
    end
end)

UIS.InputEnded:Connect(function(inp)
    if (inp.UserInputType == Enum.UserInputType.MouseButton1
     or inp.UserInputType == Enum.UserInputType.Touch) and miniDragging then
        local wasDrag = miniMoved
        miniDragging = false
        miniMoved    = false
        if not wasDrag then
            miniBtn.Visible = false
            win.Visible     = true
            miniTip.Text    = "Click to open"
        end
    end
end)

local guiVisible = true
hideBtn.MouseButton1Click:Connect(function()
    guiVisible = false
    win.Visible     = false
    miniBtn.Visible = true
    local abs = hideBtn.AbsolutePosition
    miniBtn.Position = UDim2.new(0, math.max(0, abs.X - 10), 0, math.max(0, abs.Y - 4))
    miniTip.Text = "Click to open"
end)

-- ── Sidebar ──────────────────────────────────────────────────────────
local SW = 130
local sidebar = Instance.new("Frame", win)
sidebar.Size             = UDim2.new(0, SW, 1, -TH-3)
sidebar.Position         = UDim2.new(0, 0, 0, TH+3)
sidebar.BackgroundColor3 = T.sidebar; sidebar.BorderSizePixel = 0; sidebar.ZIndex = 2
Instance.new("UIStroke", sidebar).Color = T.border

local sideGrad = Instance.new("UIGradient", sidebar)
sideGrad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(22,22,38)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(14,14,22)),
}
sideGrad.Rotation = 90

local sideL = Instance.new("UIListLayout", sidebar)
sideL.SortOrder = Enum.SortOrder.LayoutOrder; sideL.Padding = UDim.new(0,3)
local sideP = Instance.new("UIPadding", sidebar)
sideP.PaddingTop = UDim.new(0,10); sideP.PaddingLeft = UDim.new(0,7)
sideP.PaddingRight = UDim.new(0,7); sideP.PaddingBottom = UDim.new(0,8)

local menuHdr = Instance.new("TextLabel", sidebar)
menuHdr.Size = UDim2.new(1,0,0,14); menuHdr.BackgroundTransparency = 1; menuHdr.Text = "MENU"
menuHdr.TextColor3 = T.txtMute; menuHdr.Font = Enum.Font.GothamSemibold; menuHdr.TextSize = 8
menuHdr.TextXAlignment = Enum.TextXAlignment.Left; menuHdr.LayoutOrder = 0

local verLbl = Instance.new("TextLabel", sidebar)
verLbl.Size = UDim2.new(1,0,0,12); verLbl.AnchorPoint = Vector2.new(0,1); verLbl.Position = UDim2.new(0,0,1,-4)
verLbl.BackgroundTransparency = 1; verLbl.Text = "v7.1"; verLbl.TextColor3 = T.txtMute
verLbl.Font = Enum.Font.Gotham; verLbl.TextSize = 9; verLbl.TextXAlignment = Enum.TextXAlignment.Center; verLbl.ZIndex = 3

-- ── Content area ─────────────────────────────────────────────────────
local content = Instance.new("Frame", win)
content.Size             = UDim2.new(1,-SW,1,-TH-3)
content.Position         = UDim2.new(0,SW,0,TH+3)
content.BackgroundColor3 = T.bg; content.BorderSizePixel = 0; content.ClipsDescendants = true

-- ── Tab factory ──────────────────────────────────────────────────────
local allTabs   = {}
local activeTab = nil

local function makeTab(icon, label, order)
    local btn = Instance.new("TextButton", sidebar)
    btn.Size = UDim2.new(1,0,0,38); btn.BackgroundColor3 = T.sidebar
    btn.BorderSizePixel = 0; btn.Text = ""; btn.LayoutOrder = order; btn.AutoButtonColor = false
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

    local bar = Instance.new("Frame", btn)
    bar.Size = UDim2.new(0,3,0,20); bar.Position = UDim2.new(0,0,0.5,-10)
    bar.BackgroundColor3 = T.accent; bar.BorderSizePixel = 0; bar.Visible = false
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)

    local ic = Instance.new("TextLabel", btn)
    ic.Size = UDim2.new(0,24,1,0); ic.Position = UDim2.new(0,8,0,0); ic.BackgroundTransparency = 1
    ic.Text = icon; ic.TextSize = 14; ic.Font = Enum.Font.GothamBold; ic.TextColor3 = T.txtMute

    local nm = Instance.new("TextLabel", btn)
    nm.Size = UDim2.new(1,-36,1,0); nm.Position = UDim2.new(0,34,0,0); nm.BackgroundTransparency = 1
    nm.Text = label; nm.Font = Enum.Font.GothamSemibold; nm.TextSize = 12
    nm.TextColor3 = T.txtMute; nm.TextXAlignment = Enum.TextXAlignment.Left

    local page = Instance.new("ScrollingFrame", content)
    page.Size = UDim2.new(1,0,1,0); page.BackgroundTransparency = 1
    page.BorderSizePixel = 0; page.ScrollBarThickness = 6
    page.ScrollBarImageColor3 = Color3.fromRGB(55, 55, 90)
    page.CanvasSize = UDim2.new(0,0,0,0); page.AutomaticCanvasSize = Enum.AutomaticSize.Y; page.Visible = false

    local pl = Instance.new("UIListLayout", page)
    pl.SortOrder = Enum.SortOrder.LayoutOrder; pl.Padding = UDim.new(0, 10)
    local pp = Instance.new("UIPadding", page)
    pp.PaddingTop = UDim.new(0,14); pp.PaddingBottom = UDim.new(0,20)
    pp.PaddingLeft = UDim.new(0,12); pp.PaddingRight = UDim.new(0,12)

    local td = {btn=btn, page=page, bar=bar, ic=ic, nm=nm}
    table.insert(allTabs, td)

    btn.MouseButton1Click:Connect(function()
        if activeTab then
            TweenService:Create(activeTab.btn,TweenInfo.new(0.18),{BackgroundColor3=T.sidebar}):Play()
            activeTab.bar.Visible = false; activeTab.ic.TextColor3 = T.txtMute; activeTab.nm.TextColor3 = T.txtMute; activeTab.page.Visible = false
        end
        activeTab = td
        TweenService:Create(btn,TweenInfo.new(0.18),{BackgroundColor3=T.card}):Play()
        bar.Visible = true; ic.TextColor3 = T.txt; nm.TextColor3 = T.txt; page.Visible = true
    end)
    return td
end

local mailTab    = makeTab("✉️",  "Mail",     1)
local outputTab  = makeTab("📋",  "Output",   2)
local settingTab = makeTab("⚙️",  "Settings", 3)

mailTab.btn.BackgroundColor3 = T.card; mailTab.bar.Visible = true
mailTab.ic.TextColor3 = T.txt; mailTab.nm.TextColor3 = T.txt
mailTab.page.Visible = true; activeTab = mailTab

-- ── Widget helpers ───────────────────────────────────────────────────
local function secLbl(txt, order, page)
    local f = Instance.new("Frame"); f.Size = UDim2.new(1,0,0,14); f.BackgroundTransparency = 1; f.LayoutOrder = order; f.Parent = page
    local l = Instance.new("TextLabel", f); l.Size = UDim2.new(1,0,1,0); l.BackgroundTransparency = 1; l.Text = txt:upper()
    l.TextColor3 = T.txtMute; l.Font = Enum.Font.GothamSemibold; l.TextSize = 9; l.TextXAlignment = Enum.TextXAlignment.Left
end

local function mkIn(ph, order, page, h)
    local b = Instance.new("TextBox"); b.Size = UDim2.new(1,0,0,h or 36); b.BackgroundColor3 = T.input; b.BorderSizePixel = 0
    b.Text = ""; b.PlaceholderText = ph; b.PlaceholderColor3 = T.txtMute; b.TextColor3 = T.txt
    b.Font = Enum.Font.Gotham; b.TextSize = 13; b.ClearTextOnFocus = false; b.LayoutOrder = order; b.Parent = page
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    local st = Instance.new("UIStroke", b); st.Color = T.border; st.Thickness = 1
    Instance.new("UIPadding", b).PaddingLeft = UDim.new(0, 12)
    b.Focused:Connect(function()  TweenService:Create(st,TweenInfo.new(0.15),{Color=T.accent}):Play() end)
    b.FocusLost:Connect(function() TweenService:Create(st,TweenInfo.new(0.15),{Color=T.border}):Play() end)
    return b
end

local function mkBtn(txt, col, order, page, h)
    local b = Instance.new("TextButton"); b.Size = UDim2.new(1,0,0,h or 38); b.BackgroundColor3 = col; b.BorderSizePixel = 0
    b.Text = txt; b.TextColor3 = Color3.new(1,1,1); b.Font = Enum.Font.GothamBold; b.TextSize = 13; b.LayoutOrder = order; b.Parent = page
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 9)
    local g = Instance.new("UIGradient", b)
    g.Color = ColorSequence.new{ColorSequenceKeypoint.new(0,Color3.new(1,1,1):Lerp(col,0.72)),ColorSequenceKeypoint.new(1,col)}; g.Rotation = 90
    b.MouseEnter:Connect(function()     TweenService:Create(b,TweenInfo.new(0.13),{BackgroundColor3=col:Lerp(Color3.new(1,1,1),0.10)}):Play() end)
    b.MouseLeave:Connect(function()     TweenService:Create(b,TweenInfo.new(0.13),{BackgroundColor3=col}):Play() end)
    b.MouseButton1Down:Connect(function() TweenService:Create(b,TweenInfo.new(0.07),{BackgroundColor3=col:Lerp(Color3.new(0,0,0),0.12)}):Play() end)
    b.MouseButton1Up:Connect(function()   TweenService:Create(b,TweenInfo.new(0.07),{BackgroundColor3=col}):Play() end)
    return b
end

local function mkToggle(lbl, order, page)
    local row = Instance.new("Frame"); row.Size = UDim2.new(1,0,0,40); row.BackgroundColor3 = T.card; row.BorderSizePixel = 0; row.LayoutOrder = order; row.Parent = page
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 9); Instance.new("UIStroke", row).Color = T.border
    local l = Instance.new("TextLabel", row); l.Size = UDim2.new(1,-68,1,0); l.Position = UDim2.new(0,14,0,0); l.BackgroundTransparency = 1
    l.Text = lbl; l.TextColor3 = T.txt; l.Font = Enum.Font.Gotham; l.TextSize = 13; l.TextXAlignment = Enum.TextXAlignment.Left
    local pill2 = Instance.new("Frame", row); pill2.Size = UDim2.new(0,44,0,24); pill2.Position = UDim2.new(1,-54,0.5,-12); pill2.BackgroundColor3 = T.border; pill2.BorderSizePixel = 0
    Instance.new("UICorner", pill2).CornerRadius = UDim.new(1, 0)
    local thumb = Instance.new("Frame", pill2); thumb.Size = UDim2.new(0,18,0,18); thumb.Position = UDim2.new(0,3,0.5,-9); thumb.BackgroundColor3 = T.txtMute; thumb.BorderSizePixel = 0
    Instance.new("UICorner", thumb).CornerRadius = UDim.new(1, 0)
    local state = false
    local hit = Instance.new("TextButton", row); hit.Size = UDim2.new(1,0,1,0); hit.BackgroundTransparency = 1; hit.Text = ""
    local function refresh()
        if state then
            TweenService:Create(pill2,TweenInfo.new(0.2),{BackgroundColor3=T.accent}):Play()
            TweenService:Create(thumb,TweenInfo.new(0.2),{Position=UDim2.new(1,-21,0.5,-9),BackgroundColor3=Color3.new(1,1,1)}):Play()
        else
            TweenService:Create(pill2,TweenInfo.new(0.2),{BackgroundColor3=T.border}):Play()
            TweenService:Create(thumb,TweenInfo.new(0.2),{Position=UDim2.new(0,3,0.5,-9),BackgroundColor3=T.txtMute}):Play()
        end
    end
    hit.MouseButton1Click:Connect(function() state = not state; refresh() end)
    return row, function() return state end, function(v) state=v; refresh() end
end

-- ═══════════════════════════════════════════════════════════════════════
-- NEW: CONFIRMATION POPUP GUI
-- Creates a modal overlay asking the user to confirm before Send Once
-- ═══════════════════════════════════════════════════════════════════════
local function showConfirmPopup(itemName, itemAmt, recipientName, onConfirm, onCancel)
    -- Dim overlay
    local overlay = Instance.new("Frame", gui)
    overlay.Size = UDim2.new(1,0,1,0)
    overlay.BackgroundColor3 = Color3.fromRGB(0,0,0)
    overlay.BackgroundTransparency = 0.45
    overlay.BorderSizePixel = 0
    overlay.ZIndex = 50

    -- Popup card
    local popup = Instance.new("Frame", gui)
    popup.Size = UDim2.new(0, 340, 0, 190)
    popup.AnchorPoint = Vector2.new(0.5, 0.5)
    popup.Position = UDim2.new(0.5, 0, 0.5, 0)
    popup.BackgroundColor3 = T.surface
    popup.BorderSizePixel = 0
    popup.ZIndex = 51
    Instance.new("UICorner", popup).CornerRadius = UDim.new(0, 14)
    local popStk = Instance.new("UIStroke", popup)
    popStk.Color = T.accent; popStk.Thickness = 1.5

    -- Accent top bar on popup
    local popTop = Instance.new("Frame", popup)
    popTop.Size = UDim2.new(1,0,0,3)
    popTop.BackgroundColor3 = T.accent
    popTop.BorderSizePixel = 0
    popTop.ZIndex = 52
    Instance.new("UICorner", popTop).CornerRadius = UDim.new(0, 14)
    local popG = Instance.new("UIGradient", popTop)
    popG.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, T.accent),
        ColorSequenceKeypoint.new(0.5, T.purple),
        ColorSequenceKeypoint.new(1, T.orange),
    }

    -- Icon
    local iconLbl = Instance.new("TextLabel", popup)
    iconLbl.Size = UDim2.new(1,0,0,40)
    iconLbl.Position = UDim2.new(0,0,0,10)
    iconLbl.BackgroundTransparency = 1
    iconLbl.Text = "📬"
    iconLbl.TextSize = 28
    iconLbl.Font = Enum.Font.GothamBold
    iconLbl.TextColor3 = T.txt
    iconLbl.ZIndex = 52

    -- Title
    local titleP = Instance.new("TextLabel", popup)
    titleP.Size = UDim2.new(1,-24,0,22)
    titleP.Position = UDim2.new(0,12,0,52)
    titleP.BackgroundTransparency = 1
    titleP.Text = "Confirm Send Once"
    titleP.TextColor3 = T.txt
    titleP.Font = Enum.Font.GothamBold
    titleP.TextSize = 15
    titleP.TextXAlignment = Enum.TextXAlignment.Center
    titleP.ZIndex = 52

    -- Details text
    local detailLbl = Instance.new("TextLabel", popup)
    detailLbl.Size = UDim2.new(1,-24,0,36)
    detailLbl.Position = UDim2.new(0,12,0,78)
    detailLbl.BackgroundTransparency = 1
    detailLbl.Text = "Send  "..tostring(itemAmt).."x  \""..itemName.."\"\nto  → "..tostring(recipientName ~= "" and recipientName or "(no recipient set)")
    detailLbl.TextColor3 = T.txtSub
    detailLbl.Font = Enum.Font.Gotham
    detailLbl.TextSize = 12
    detailLbl.TextXAlignment = Enum.TextXAlignment.Center
    detailLbl.TextWrapped = true
    detailLbl.ZIndex = 52

    -- Confirm button
    local confirmBtn = Instance.new("TextButton", popup)
    confirmBtn.Size = UDim2.new(0, 136, 0, 36)
    confirmBtn.Position = UDim2.new(0, 14, 1, -50)
    confirmBtn.BackgroundColor3 = T.green
    confirmBtn.Text = "✓  Confirm"
    confirmBtn.TextColor3 = Color3.new(1,1,1)
    confirmBtn.Font = Enum.Font.GothamBold
    confirmBtn.TextSize = 13
    confirmBtn.BorderSizePixel = 0
    confirmBtn.ZIndex = 52
    Instance.new("UICorner", confirmBtn).CornerRadius = UDim.new(0, 9)
    confirmBtn.MouseEnter:Connect(function()
        TweenService:Create(confirmBtn,TweenInfo.new(0.12),{BackgroundColor3=T.green:Lerp(Color3.new(1,1,1),0.15)}):Play()
    end)
    confirmBtn.MouseLeave:Connect(function()
        TweenService:Create(confirmBtn,TweenInfo.new(0.12),{BackgroundColor3=T.green}):Play()
    end)

    -- Cancel button
    local cancelBtn = Instance.new("TextButton", popup)
    cancelBtn.Size = UDim2.new(0, 136, 0, 36)
    cancelBtn.Position = UDim2.new(1, -150, 1, -50)
    cancelBtn.BackgroundColor3 = T.redDk
    cancelBtn.Text = "✕  Cancel"
    cancelBtn.TextColor3 = Color3.new(1,1,1)
    cancelBtn.Font = Enum.Font.GothamBold
    cancelBtn.TextSize = 13
    cancelBtn.BorderSizePixel = 0
    cancelBtn.ZIndex = 52
    Instance.new("UICorner", cancelBtn).CornerRadius = UDim.new(0, 9)
    cancelBtn.MouseEnter:Connect(function()
        TweenService:Create(cancelBtn,TweenInfo.new(0.12),{BackgroundColor3=T.red}):Play()
    end)
    cancelBtn.MouseLeave:Connect(function()
        TweenService:Create(cancelBtn,TweenInfo.new(0.12),{BackgroundColor3=T.redDk}):Play()
    end)

    -- Entrance animation: scale + fade in
    popup.BackgroundTransparency = 1
    local function destroyPopup()
        overlay:Destroy()
        popup:Destroy()
    end

    TweenService:Create(popup, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency = 0}):Play()

    confirmBtn.MouseButton1Click:Connect(function()
        destroyPopup()
        if onConfirm then onConfirm() end
    end)

    cancelBtn.MouseButton1Click:Connect(function()
        destroyPopup()
        if onCancel then onCancel() end
    end)

    -- Clicking overlay cancels too
    overlay.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            destroyPopup()
            if onCancel then onCancel() end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════
-- MAIL PAGE
-- ═══════════════════════════════════════════════════════════════════════
local mp = mailTab.page

secLbl("Recipient", 1, mp)

-- Recipient row: input + clear 🗑 button
local recipRow = Instance.new("Frame")
recipRow.Size = UDim2.new(1,0,0,36); recipRow.BackgroundTransparency = 1
recipRow.LayoutOrder = 2; recipRow.Parent = mp

local usernameBox = Instance.new("TextBox", recipRow)
usernameBox.Size = UDim2.new(1,-42,1,0)
usernameBox.BackgroundColor3 = T.input; usernameBox.BorderSizePixel = 0
usernameBox.Text = ""; usernameBox.PlaceholderText = "Roblox username"
usernameBox.PlaceholderColor3 = T.txtMute; usernameBox.TextColor3 = T.txt
usernameBox.Font = Enum.Font.Gotham; usernameBox.TextSize = 13; usernameBox.ClearTextOnFocus = false
Instance.new("UICorner", usernameBox).CornerRadius = UDim.new(0, 8)
local uSt = Instance.new("UIStroke", usernameBox); uSt.Color = T.border; uSt.Thickness = 1
Instance.new("UIPadding", usernameBox).PaddingLeft = UDim.new(0, 12)
usernameBox.Focused:Connect(function()  TweenService:Create(uSt,TweenInfo.new(0.15),{Color=T.accent}):Play() end)
usernameBox.FocusLost:Connect(function()
    TweenService:Create(uSt,TweenInfo.new(0.15),{Color=T.border}):Play()
    cfg.username = usernameBox.Text
end)

local clearRecipBtn = Instance.new("TextButton", recipRow)
clearRecipBtn.Size = UDim2.new(0,36,0,36); clearRecipBtn.Position = UDim2.new(1,-36,0,0)
clearRecipBtn.BackgroundColor3 = T.redDk; clearRecipBtn.BorderSizePixel = 0
clearRecipBtn.Text = "🗑"; clearRecipBtn.TextSize = 16; clearRecipBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", clearRecipBtn).CornerRadius = UDim.new(0, 8)
local crStk = Instance.new("UIStroke", clearRecipBtn); crStk.Color = T.red; crStk.Thickness = 1
clearRecipBtn.MouseEnter:Connect(function()
    TweenService:Create(clearRecipBtn,TweenInfo.new(0.12),{BackgroundColor3=T.red}):Play()
end)
clearRecipBtn.MouseLeave:Connect(function()
    TweenService:Create(clearRecipBtn,TweenInfo.new(0.12),{BackgroundColor3=T.redDk}):Play()
end)

-- forward declare setLog so clearRecipBtn can reference it
local setLog

clearRecipBtn.MouseButton1Click:Connect(function()
    usernameBox.Text = ""; cfg.username = ""
    TweenService:Create(clearRecipBtn,TweenInfo.new(0.07),{BackgroundColor3=Color3.fromRGB(255,80,80)}):Play()
    task.delay(0.2, function() if clearRecipBtn and clearRecipBtn.Parent then TweenService:Create(clearRecipBtn,TweenInfo.new(0.15),{BackgroundColor3=T.redDk}):Play() end end)
    if setLog then setLog("Recipient cleared.") end
end)

-- ── Items card ───────────────────────────────────────────────────────
secLbl("Items to send", 3, mp)

local itemCard = Instance.new("Frame"); itemCard.Size = UDim2.new(1,0,0,10); itemCard.AutomaticSize = Enum.AutomaticSize.Y
itemCard.BackgroundColor3 = T.card; itemCard.BorderSizePixel = 0; itemCard.LayoutOrder = 4; itemCard.Parent = mp
Instance.new("UICorner", itemCard).CornerRadius = UDim.new(0, 10)
Instance.new("UIStroke", itemCard).Color = T.border

local icL = Instance.new("UIListLayout", itemCard); icL.SortOrder = Enum.SortOrder.LayoutOrder; icL.Padding = UDim.new(0, 0)

-- add-input row
local addRowF = Instance.new("Frame", itemCard); addRowF.Size = UDim2.new(1,0,0,44); addRowF.BackgroundTransparency = 1; addRowF.LayoutOrder = 1

local nameIn = Instance.new("TextBox", addRowF); nameIn.Size = UDim2.new(1,-104,0,30); nameIn.Position = UDim2.new(0,10,0.5,-15)
nameIn.BackgroundColor3 = T.input; nameIn.BorderSizePixel = 0; nameIn.PlaceholderText = "Item name"; nameIn.PlaceholderColor3 = T.txtMute
nameIn.Text = ""; nameIn.TextColor3 = T.txt; nameIn.Font = Enum.Font.Gotham; nameIn.TextSize = 12; nameIn.ClearTextOnFocus = false
Instance.new("UICorner", nameIn).CornerRadius = UDim.new(0, 7)
local nsSt = Instance.new("UIStroke", nameIn); nsSt.Color = T.border; nsSt.Thickness = 1; Instance.new("UIPadding", nameIn).PaddingLeft = UDim.new(0, 9)
nameIn.Focused:Connect(function()  TweenService:Create(nsSt,TweenInfo.new(0.15),{Color=T.accent}):Play() end)
nameIn.FocusLost:Connect(function() TweenService:Create(nsSt,TweenInfo.new(0.15),{Color=T.border}):Play() end)

local amtIn = Instance.new("TextBox", addRowF); amtIn.Size = UDim2.new(0,50,0,30); amtIn.Position = UDim2.new(1,-88,0.5,-15)
amtIn.BackgroundColor3 = T.input; amtIn.BorderSizePixel = 0; amtIn.PlaceholderText = "Qty"; amtIn.PlaceholderColor3 = T.txtMute
amtIn.Text = ""; amtIn.TextColor3 = T.txt; amtIn.Font = Enum.Font.GothamBold; amtIn.TextSize = 12; amtIn.ClearTextOnFocus = false
Instance.new("UICorner", amtIn).CornerRadius = UDim.new(0, 7)
local amSt = Instance.new("UIStroke", amtIn); amSt.Color = T.border; amSt.Thickness = 1; Instance.new("UIPadding", amtIn).PaddingLeft = UDim.new(0, 7)
amtIn.Focused:Connect(function()  TweenService:Create(amSt,TweenInfo.new(0.15),{Color=T.accent}):Play() end)
amtIn.FocusLost:Connect(function() TweenService:Create(amSt,TweenInfo.new(0.15),{Color=T.border}):Play() end)

local addBtn = Instance.new("TextButton", addRowF); addBtn.Size = UDim2.new(0,30,0,30); addBtn.Position = UDim2.new(1,-34,0.5,-15)
addBtn.BackgroundColor3 = T.green; addBtn.Text = "+"; addBtn.TextColor3 = Color3.new(1,1,1); addBtn.Font = Enum.Font.GothamBold; addBtn.TextSize = 18; addBtn.BorderSizePixel = 0
Instance.new("UICorner", addBtn).CornerRadius = UDim.new(0, 7)

-- divider
local addDiv = Instance.new("Frame", itemCard); addDiv.Size = UDim2.new(1,-20,0,1); addDiv.BackgroundColor3 = T.border; addDiv.BorderSizePixel = 0; addDiv.LayoutOrder = 2

-- column headers
local colHdr = Instance.new("Frame", itemCard); colHdr.Size = UDim2.new(1,0,0,20); colHdr.BackgroundTransparency = 1; colHdr.LayoutOrder = 3

local function mkColLbl(txt, xOff, w)
    local l = Instance.new("TextLabel", colHdr); l.Size = UDim2.new(0,w,1,0); l.Position = UDim2.new(1,xOff,0,0)
    l.BackgroundTransparency = 1; l.Text = txt; l.TextColor3 = T.txtMute
    l.Font = Enum.Font.GothamSemibold; l.TextSize = 9; l.TextXAlignment = Enum.TextXAlignment.Center
end
mkColLbl("Qty",       -214, 46)
mkColLbl("Auto Send", -162, 68)
mkColLbl("→ Once",    -88,  58)
-- NEW: "In Inv" column header
mkColLbl("In Inv",    -280, 58)
local colItemLbl = Instance.new("TextLabel", colHdr); colItemLbl.Size = UDim2.new(1,-290,1,0); colItemLbl.Position = UDim2.new(0,42,0,0)
colItemLbl.BackgroundTransparency = 1; colItemLbl.Text = "Item name"; colItemLbl.TextColor3 = T.txtMute
colItemLbl.Font = Enum.Font.GothamSemibold; colItemLbl.TextSize = 9; colItemLbl.TextXAlignment = Enum.TextXAlignment.Left

-- error label
local errLbl = Instance.new("TextLabel", itemCard); errLbl.Size = UDim2.new(1,-20,0,16); errLbl.BackgroundTransparency = 1
errLbl.Text = ""; errLbl.TextColor3 = T.red; errLbl.Font = Enum.Font.GothamSemibold; errLbl.TextSize = 10; errLbl.LayoutOrder = 4
Instance.new("UIPadding", errLbl).PaddingLeft = UDim.new(0, 10)
local function showErr(msg)
    errLbl.Text = msg; task.delay(2.5, function() if errLbl and errLbl.Parent then errLbl.Text = "" end end)
end

-- item list container
local itemList = Instance.new("Frame", itemCard); itemList.Name = "ItemList"
itemList.Size = UDim2.new(1,0,0,0); itemList.AutomaticSize = Enum.AutomaticSize.Y
itemList.BackgroundTransparency = 1; itemList.BorderSizePixel = 0; itemList.LayoutOrder = 5

local ilL = Instance.new("UIListLayout", itemList); ilL.SortOrder = Enum.SortOrder.LayoutOrder; ilL.Padding = UDim.new(0, 0)

local emptyLbl = Instance.new("TextLabel", itemList); emptyLbl.Size = UDim2.new(1,0,0,32)
emptyLbl.BackgroundTransparency = 1; emptyLbl.Text = "No items added yet."
emptyLbl.TextColor3 = T.txtMute; emptyLbl.Font = Enum.Font.Gotham; emptyLbl.TextSize = 12; emptyLbl.LayoutOrder = 0

local itemEntries = {}
local function refreshEmpty() emptyLbl.Visible = #itemEntries == 0 end

local function syncCfgItems()
    cfg.items = {}
    for _, e in ipairs(itemEntries) do
        table.insert(cfg.items, { name=e.cfgEntry.name, amount=e.cfgEntry.amount, autoSend=e.cfgEntry.autoSend })
    end
end

-- NEW: update inventory count labels for all items
local function updateDots(inv)
    for _, e in ipairs(itemEntries) do
        if e.dot and e.dot.Parent then
            TweenService:Create(e.dot,TweenInfo.new(0.3),{BackgroundColor3=(inv and hasItem(inv,e.cfgEntry.name)) and T.green or T.red}):Play()
        end
        -- Update inventory count label
        if e.invCountLbl and e.invCountLbl.Parent then
            local count = inv and getItemCount(inv, e.cfgEntry.name) or 0
            if count > 0 then
                e.invCountLbl.Text = "x"..tostring(count)
                e.invCountLbl.TextColor3 = T.green
            else
                e.invCountLbl.Text = "x0"
                e.invCountLbl.TextColor3 = T.red
            end
        end
    end
end

local function doSendOneItem(entry)
    if cfg.username == "" then if setLog then setLog("⚠  No username set.", true) end; return end
    task.spawn(function()
        local inv = getInv()
        if not inv then if setLog then setLog("⚠  No inventory.", true) end; return end
        if not hasItem(inv, entry.name) then if setLog then setLog("⚠  "..entry.name.." not in inventory.", true) end; return end
        if setLog then setLog("→ Sending "..entry.name.." ×"..entry.amount.." now...") end
        local worked, _ = sendEntry(entry, setLog or function() end)
        if worked then
            if setLog then setLog("✓  Sent "..entry.name.." ×"..entry.amount.." to "..cfg.username) end
            pushLog(cfg.username, {entry}, {}, true, "Once")
            sendWebhook(cfg.username, {entry}, {}, true, "Once")
            -- NEW: clear recipient after successful Send Once
            if cfg.clearAfterOnce then
                usernameBox.Text = ""
                cfg.username = ""
            end
        else
            if setLog then setLog("✗  Failed to send "..entry.name, true) end
            pushLog(cfg.username, {}, {entry.name}, false, "Once")
        end
        saveAll()
    end)
end

local function addItemRow(name, amount, autoSend)
    if name == "" then return end
    amount   = math.clamp(math.floor(tonumber(amount) or 1), 1, cfg.maxAmt)
    if autoSend == nil then autoSend = true end

    local idx = #itemEntries + 1
    local row = Instance.new("Frame", itemList)
    row.Size = UDim2.new(1,0,0,38); row.BackgroundColor3 = (idx%2==0) and T.card or T.tagBg
    row.BorderSizePixel = 0; row.LayoutOrder = idx

    local abar = Instance.new("Frame", row); abar.Size = UDim2.new(0,3,0,22); abar.Position = UDim2.new(0,0,0.5,-11)
    abar.BackgroundColor3 = autoSend and T.green or T.red; abar.BorderSizePixel = 0
    Instance.new("UICorner", abar).CornerRadius = UDim.new(0, 2)

    local numL = Instance.new("TextLabel", row); numL.Size = UDim2.new(0,20,1,0); numL.Position = UDim2.new(0,6,0,0)
    numL.BackgroundTransparency = 1; numL.Text = tostring(idx).."."; numL.TextColor3 = T.txtMute
    numL.Font = Enum.Font.GothamSemibold; numL.TextSize = 10; numL.TextXAlignment = Enum.TextXAlignment.Right

    local dot = Instance.new("Frame", row); dot.Size = UDim2.new(0,7,0,7); dot.Position = UDim2.new(0,30,0.5,-3.5)
    dot.BackgroundColor3 = T.txtMute; dot.BorderSizePixel = 0; Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    -- NEW: item name is narrower to fit the inv count badge
    local nmL = Instance.new("TextLabel", row); nmL.Size = UDim2.new(1,-290,1,0); nmL.Position = UDim2.new(0,42,0,0)
    nmL.BackgroundTransparency = 1; nmL.Text = name; nmL.TextColor3 = T.txt; nmL.Font = Enum.Font.GothamSemibold
    nmL.TextSize = 12; nmL.TextXAlignment = Enum.TextXAlignment.Left; nmL.TextTruncate = Enum.TextTruncate.AtEnd

    -- NEW: inventory count badge — shows how many of this item the player currently has
    local invCountBadge = Instance.new("Frame", row)
    invCountBadge.Size = UDim2.new(0,52,0,22)
    invCountBadge.Position = UDim2.new(1,-286,0.5,-11)
    invCountBadge.BackgroundColor3 = Color3.fromRGB(18,18,32)
    invCountBadge.BorderSizePixel = 0
    Instance.new("UICorner", invCountBadge).CornerRadius = UDim.new(0, 5)
    local invStk = Instance.new("UIStroke", invCountBadge); invStk.Color = T.border; invStk.Thickness = 1

    local invCountLbl = Instance.new("TextLabel", invCountBadge)
    invCountLbl.Size = UDim2.new(1,0,1,0)
    invCountLbl.BackgroundTransparency = 1
    invCountLbl.Text = "x?"
    invCountLbl.TextColor3 = T.txtMute
    invCountLbl.Font = Enum.Font.GothamBold
    invCountLbl.TextSize = 10
    invCountLbl.TextXAlignment = Enum.TextXAlignment.Center

    local qtyBox = Instance.new("TextBox", row); qtyBox.Size = UDim2.new(0,44,0,26); qtyBox.Position = UDim2.new(1,-216,0.5,-13)
    qtyBox.BackgroundColor3 = T.badgeBg; qtyBox.BorderSizePixel = 0; qtyBox.Text = tostring(amount)
    qtyBox.TextColor3 = T.badgeTx; qtyBox.Font = Enum.Font.GothamBold; qtyBox.TextSize = 11; qtyBox.ClearTextOnFocus = false
    Instance.new("UICorner", qtyBox).CornerRadius = UDim.new(0, 5); Instance.new("UIPadding", qtyBox).PaddingLeft = UDim.new(0, 6)
    local qSt = Instance.new("UIStroke", qtyBox); qSt.Color = T.border; qSt.Thickness = 1
    qtyBox.Focused:Connect(function()  TweenService:Create(qSt,TweenInfo.new(0.15),{Color=T.accent}):Play() end)
    qtyBox.FocusLost:Connect(function()
        TweenService:Create(qSt,TweenInfo.new(0.15),{Color=T.border}):Play()
        local v = tonumber(qtyBox.Text)
        if v then v = math.clamp(math.floor(v),1,cfg.maxAmt); qtyBox.Text = tostring(v) end
        for _, e in ipairs(itemEntries) do if e.qtyBox == qtyBox then e.cfgEntry.amount = tonumber(qtyBox.Text) or 1; break end end
        syncCfgItems(); saveAll()
    end)

    local autoSendState = autoSend
    local autoBtn = Instance.new("TextButton", row); autoBtn.Size = UDim2.new(0,66,0,26); autoBtn.Position = UDim2.new(1,-164,0.5,-13)
    autoBtn.BorderSizePixel = 0; autoBtn.Font = Enum.Font.GothamBold; autoBtn.TextSize = 9
    Instance.new("UICorner", autoBtn).CornerRadius = UDim.new(0, 6)

    local function refreshAutoBtn()
        if autoSendState then
            autoBtn.BackgroundColor3 = Color3.fromRGB(28,70,40); autoBtn.TextColor3 = T.green; autoBtn.Text = "Auto Send"
            abar.BackgroundColor3    = T.green
        else
            autoBtn.BackgroundColor3 = Color3.fromRGB(60,22,22); autoBtn.TextColor3 = Color3.fromRGB(220,80,80); autoBtn.Text = "Auto Send"
            abar.BackgroundColor3    = T.red
        end
    end
    refreshAutoBtn()

    -- Send Once button (per-item, with optional confirmation)
    local onceBtn = Instance.new("TextButton", row); onceBtn.Size = UDim2.new(0,56,0,26); onceBtn.Position = UDim2.new(1,-90,0.5,-13)
    onceBtn.BackgroundColor3 = Color3.fromRGB(28,50,110); onceBtn.BorderSizePixel = 0
    onceBtn.Font = Enum.Font.GothamBold; onceBtn.TextSize = 9
    onceBtn.Text = "→ Once"; onceBtn.TextColor3 = Color3.fromRGB(120,170,255)
    Instance.new("UICorner", onceBtn).CornerRadius = UDim.new(0, 6)
    onceBtn.MouseEnter:Connect(function() TweenService:Create(onceBtn,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(50,90,190)}):Play() end)
    onceBtn.MouseLeave:Connect(function() TweenService:Create(onceBtn,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(28,50,110)}):Play() end)

    local remBtn = Instance.new("TextButton", row); remBtn.Size = UDim2.new(0,26,0,26); remBtn.Position = UDim2.new(1,-28,0.5,-13)
    remBtn.BackgroundColor3 = Color3.fromRGB(70,20,20); remBtn.Text = "🗑"; remBtn.TextSize = 13
    remBtn.Font = Enum.Font.GothamBold; remBtn.BorderSizePixel = 0
    Instance.new("UICorner", remBtn).CornerRadius = UDim.new(0, 7)
    local remStk = Instance.new("UIStroke", remBtn); remStk.Color = Color3.fromRGB(180,40,40); remStk.Thickness = 1
    remBtn.MouseEnter:Connect(function() TweenService:Create(remBtn,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(180,40,40)}):Play() end)
    remBtn.MouseLeave:Connect(function() TweenService:Create(remBtn,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(70,20,20)}):Play() end)

    local cfgEntry = { name=name, amount=amount, autoSend=autoSend }
    local entryData = { frame=row, dot=dot, qtyBox=qtyBox, autoBtn=autoBtn, onceBtn=onceBtn, numLbl=numL, cfgEntry=cfgEntry, invCountLbl=invCountLbl }
    table.insert(itemEntries, entryData)
    syncCfgItems(); refreshEmpty()

    -- Try to update inventory count immediately if we can
    task.spawn(function()
        local ok, inv = pcall(getInv)
        if ok and inv then
            local count = getItemCount(inv, name)
            if invCountLbl and invCountLbl.Parent then
                invCountLbl.Text = "x"..tostring(count)
                invCountLbl.TextColor3 = count > 0 and T.green or T.red
            end
        end
    end)

    autoBtn.MouseButton1Click:Connect(function()
        autoSendState = not autoSendState
        cfgEntry.autoSend = autoSendState
        refreshAutoBtn()
        syncCfgItems(); saveAll()
    end)

    -- NEW: Send Once with optional confirmation popup
    onceBtn.MouseButton1Click:Connect(function()
        TweenService:Create(onceBtn,TweenInfo.new(0.08),{BackgroundColor3=T.accent}):Play()
        task.delay(0.35, function()
            if onceBtn and onceBtn.Parent then
                TweenService:Create(onceBtn,TweenInfo.new(0.2),{BackgroundColor3=Color3.fromRGB(28,50,110)}):Play()
            end
        end)
        if cfg.confirmOnce then
            -- Show confirmation popup before sending
            showConfirmPopup(cfgEntry.name, cfgEntry.amount, cfg.username,
                function()
                    -- Confirmed — proceed with send
                    doSendOneItem(cfgEntry)
                end,
                function()
                    -- Cancelled
                    if setLog then setLog("Send Once cancelled.") end
                end
            )
        else
            -- No confirmation needed, send directly
            doSendOneItem(cfgEntry)
        end
    end)

    remBtn.MouseButton1Click:Connect(function()
        row:Destroy()
        for i, e in ipairs(itemEntries) do if e == entryData then table.remove(itemEntries, i); break end end
        for i2, e2 in ipairs(itemEntries) do e2.numLbl.Text = tostring(i2).."." end
        syncCfgItems(); refreshEmpty(); saveAll()
    end)

    return entryData
end

local function tryAdd()
    local n = nameIn.Text:match("^%s*(.-)%s*$"); local a = amtIn.Text
    if n == "" then showErr("⚠  Enter an item name."); return end
    local numA = tonumber(a)
    if not numA or a == "" then showErr("⚠  Enter a valid quantity."); return end
    numA = math.clamp(math.floor(numA), 1, cfg.maxAmt)
    if tonumber(a) > cfg.maxAmt then showErr("⚠  Qty capped to "..tostring(cfg.maxAmt)..".") end
    amtIn.Text = tostring(numA)
    addItemRow(n, tostring(numA), true); nameIn.Text = ""; amtIn.Text = ""; saveAll()
end
addBtn.MouseButton1Click:Connect(tryAdd)
nameIn.FocusLost:Connect(function(enter) if enter then tryAdd() end end)

-- ── Note ─────────────────────────────────────────────────────────────
secLbl("Note (optional)", 6, mp)
local noteBox = mkIn("Mail note...", 7, mp)
noteBox.FocusLost:Connect(function() cfg.note = noteBox.Text end)

-- ── Interval ─────────────────────────────────────────────────────────
secLbl("Auto send interval", 8, mp)
local intRowF = Instance.new("Frame"); intRowF.Size = UDim2.new(1,0,0,34); intRowF.BackgroundTransparency = 1; intRowF.LayoutOrder = 9; intRowF.Parent = mp
local intBox = Instance.new("TextBox", intRowF); intBox.Size = UDim2.new(0,76,1,0); intBox.BackgroundColor3 = T.input; intBox.BorderSizePixel = 0
intBox.Text = "10"; intBox.TextColor3 = T.txt; intBox.Font = Enum.Font.GothamBold; intBox.TextSize = 14; intBox.ClearTextOnFocus = false
Instance.new("UICorner", intBox).CornerRadius = UDim.new(0, 8)
local iSt = Instance.new("UIStroke", intBox); iSt.Color = T.border; iSt.Thickness = 1; Instance.new("UIPadding", intBox).PaddingLeft = UDim.new(0, 12)
intBox.Focused:Connect(function()  TweenService:Create(iSt,TweenInfo.new(0.15),{Color=T.accent}):Play() end)
intBox.FocusLost:Connect(function()
    TweenService:Create(iSt,TweenInfo.new(0.15),{Color=T.border}):Play()
    local v = tonumber(intBox.Text); if v and v >= 1 then cfg.interval = v else intBox.Text = tostring(cfg.interval) end
end)
local intSL = Instance.new("TextLabel", intRowF); intSL.Size = UDim2.new(1,-86,1,0); intSL.Position = UDim2.new(0,84,0,0)
intSL.BackgroundTransparency = 1; intSL.Text = "seconds between sends"; intSL.TextColor3 = T.txtMute; intSL.Font = Enum.Font.Gotham; intSL.TextSize = 12; intSL.TextXAlignment = Enum.TextXAlignment.Left

-- ── Auto Send master toggle ───────────────────────────────────────────
local _, getAutoSend, setAutoSend = mkToggle("Auto Send", 10, mp)

-- ── Log bar ──────────────────────────────────────────────────────────
local logBar = Instance.new("Frame"); logBar.Size = UDim2.new(1,0,0,34); logBar.BackgroundColor3 = T.card; logBar.BorderSizePixel = 0; logBar.LayoutOrder = 11; logBar.Parent = mp
Instance.new("UICorner", logBar).CornerRadius = UDim.new(0, 8); Instance.new("UIStroke", logBar).Color = T.border
local logNub = Instance.new("Frame", logBar); logNub.Size = UDim2.new(0,3,0,20); logNub.Position = UDim2.new(0,0,0.5,-10); logNub.BackgroundColor3 = T.accent; logNub.BorderSizePixel = 0; Instance.new("UICorner", logNub).CornerRadius = UDim.new(0,2)
local logDot = Instance.new("Frame", logBar); logDot.Size = UDim2.new(0,8,0,8); logDot.Position = UDim2.new(0,12,0.5,-4)
logDot.BackgroundColor3 = T.green; logDot.BorderSizePixel = 0; Instance.new("UICorner", logDot).CornerRadius = UDim.new(1, 0)
local logLbl = Instance.new("TextLabel", logBar); logLbl.Size = UDim2.new(1,-30,1,0); logLbl.Position = UDim2.new(0,28,0,0)
logLbl.BackgroundTransparency = 1; logLbl.Text = "Idle — ready."; logLbl.TextColor3 = T.txtSub
logLbl.Font = Enum.Font.Gotham; logLbl.TextSize = 12; logLbl.TextXAlignment = Enum.TextXAlignment.Left; logLbl.TextTruncate = Enum.TextTruncate.AtEnd

setLog = function(msg, isErr)
    logLbl.Text = msg
    TweenService:Create(logDot,TweenInfo.new(0.2),{BackgroundColor3 = isErr and T.red or T.green}):Play()
    logLbl.TextColor3 = isErr and Color3.fromRGB(240,130,130) or T.txtSub
end

-- ═══════════════════════════════════════════════════════════════════════
-- OUTPUT PAGE
-- ═══════════════════════════════════════════════════════════════════════
local op = outputTab.page
secLbl("Send history (last 10)", 1, op)

local outList = Instance.new("Frame"); outList.Size = UDim2.new(1,0,0,0); outList.AutomaticSize = Enum.AutomaticSize.Y
outList.BackgroundTransparency = 1; outList.BorderSizePixel = 0; outList.LayoutOrder = 2; outList.Parent = op
local outLL = Instance.new("UIListLayout", outList); outLL.SortOrder = Enum.SortOrder.LayoutOrder; outLL.Padding = UDim.new(0, 6)
local noHistL = Instance.new("TextLabel", outList); noHistL.Size = UDim2.new(1,0,0,38); noHistL.BackgroundTransparency = 1
noHistL.Text = "No sends yet."; noHistL.TextColor3 = T.txtMute; noHistL.Font = Enum.Font.Gotham; noHistL.TextSize = 12; noHistL.LayoutOrder = 0

local outFrames = {}

local function rebuildOutput()
    for _, f in ipairs(outFrames) do f:Destroy() end; outFrames = {}
    noHistL.Visible = #outputLog == 0

    for idx, entry in ipairs(outputLog) do
        local card = Instance.new("Frame", outList); card.Size = UDim2.new(1,0,0,0); card.AutomaticSize = Enum.AutomaticSize.Y
        card.BackgroundColor3 = T.card; card.BorderSizePixel = 0; card.LayoutOrder = idx
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 9)
        local cst = Instance.new("UIStroke", card)
        cst.Color = entry.success and Color3.fromRGB(38,76,48) or Color3.fromRGB(76,28,28); cst.Thickness = 1

        local cL = Instance.new("UIListLayout", card); cL.SortOrder = Enum.SortOrder.LayoutOrder; cL.Padding = UDim.new(0, 3)
        local cP = Instance.new("UIPadding", card); cP.PaddingLeft = UDim.new(0,12); cP.PaddingRight = UDim.new(0,12); cP.PaddingTop = UDim.new(0,8); cP.PaddingBottom = UDim.new(0,8)

        local hdr = Instance.new("Frame", card); hdr.Size = UDim2.new(1,0,0,22); hdr.BackgroundTransparency = 1; hdr.LayoutOrder = 1
        local sdot = Instance.new("Frame", hdr); sdot.Size = UDim2.new(0,9,0,9); sdot.Position = UDim2.new(0,0,0.5,-4.5)
        sdot.BackgroundColor3 = entry.success and T.green or T.red; sdot.BorderSizePixel = 0; Instance.new("UICorner", sdot).CornerRadius = UDim.new(1, 0)

        local toLbl = Instance.new("TextLabel", hdr); toLbl.Size = UDim2.new(1,-120,1,0); toLbl.Position = UDim2.new(0,16,0,0)
        toLbl.BackgroundTransparency = 1; toLbl.Text = "→ "..entry.to; toLbl.TextColor3 = T.txt
        toLbl.Font = Enum.Font.GothamBold; toLbl.TextSize = 13; toLbl.TextXAlignment = Enum.TextXAlignment.Left

        local modeBadge = Instance.new("Frame", hdr); modeBadge.Size = UDim2.new(0,46,0,18); modeBadge.Position = UDim2.new(1,-114,0.5,-9)
        modeBadge.BackgroundColor3 = (entry.mode=="Once") and Color3.fromRGB(28,50,110) or Color3.fromRGB(28,55,40); modeBadge.BorderSizePixel = 0
        Instance.new("UICorner", modeBadge).CornerRadius = UDim.new(0, 4)
        local modeLbl = Instance.new("TextLabel", modeBadge); modeLbl.Size = UDim2.new(1,0,1,0); modeLbl.BackgroundTransparency = 1
        modeLbl.Text = entry.mode or "Auto"; modeLbl.Font = Enum.Font.GothamBold; modeLbl.TextSize = 9
        modeLbl.TextColor3 = (entry.mode=="Once") and Color3.fromRGB(120,165,255) or T.green

        local timeLbl = Instance.new("TextLabel", hdr); timeLbl.Size = UDim2.new(0,58,1,0); timeLbl.Position = UDim2.new(1,-58,0,0)
        timeLbl.BackgroundTransparency = 1; timeLbl.Text = entry.time; timeLbl.TextColor3 = T.txtMute
        timeLbl.Font = Enum.Font.Code; timeLbl.TextSize = 10; timeLbl.TextXAlignment = Enum.TextXAlignment.Right

        if #entry.items > 0 then
            local parts = {}; for _, it in ipairs(entry.items) do parts[#parts+1] = it.name.." ×"..it.amount end
            local iL = Instance.new("TextLabel", card); iL.Size = UDim2.new(1,0,0,15); iL.BackgroundTransparency = 1
            iL.Text = "  "..table.concat(parts, "  ·  "); iL.TextColor3 = T.txtSub; iL.Font = Enum.Font.Gotham; iL.TextSize = 11
            iL.TextXAlignment = Enum.TextXAlignment.Left; iL.TextTruncate = Enum.TextTruncate.AtEnd; iL.LayoutOrder = 2
        end

        if #entry.skipped > 0 then
            local sL = Instance.new("TextLabel", card); sL.Size = UDim2.new(1,0,0,13); sL.BackgroundTransparency = 1
            sL.Text = "  ⏭ Skipped: "..table.concat(entry.skipped, ", "); sL.TextColor3 = T.orange; sL.Font = Enum.Font.Gotham; sL.TextSize = 10
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

-- ── NEW: Send Once Behaviour ──────────────────────────────────────────
secLbl("Send Once Behaviour", 1, sp)

local onceCard = Instance.new("Frame")
onceCard.Size = UDim2.new(1,0,0,0); onceCard.AutomaticSize = Enum.AutomaticSize.Y
onceCard.BackgroundColor3 = T.card; onceCard.BorderSizePixel = 0; onceCard.LayoutOrder = 2; onceCard.Parent = sp
Instance.new("UICorner", onceCard).CornerRadius = UDim.new(0, 9)
Instance.new("UIStroke", onceCard).Color = T.border
local oncePad = Instance.new("UIPadding", onceCard)
oncePad.PaddingTop = UDim.new(0,4); oncePad.PaddingBottom = UDim.new(0,4)

local onceCardL = Instance.new("UIListLayout", onceCard)
onceCardL.SortOrder = Enum.SortOrder.LayoutOrder; onceCardL.Padding = UDim.new(0, 0)

-- Toggle 1: Confirm before Send Once
local _, getConfirmOnce, setConfirmOnce = mkToggle("Confirm before Send Once", 1, onceCard)
setConfirmOnce(cfg.confirmOnce)

-- Sub-description
local confirmDesc = Instance.new("TextLabel", onceCard)
confirmDesc.Size = UDim2.new(1,-28,0,26)
confirmDesc.BackgroundTransparency = 1; confirmDesc.LayoutOrder = 2
confirmDesc.Text = "  Shows a confirmation popup before sending\n  to prevent accidental sends."
confirmDesc.TextColor3 = T.txtMute; confirmDesc.Font = Enum.Font.Gotham; confirmDesc.TextSize = 9
confirmDesc.TextXAlignment = Enum.TextXAlignment.Left; confirmDesc.TextWrapped = true

-- Divider
local onceDivider = Instance.new("Frame", onceCard)
onceDivider.Size = UDim2.new(1,-20,0,1); onceDivider.BackgroundColor3 = T.border
onceDivider.BorderSizePixel = 0; onceDivider.LayoutOrder = 3

-- Toggle 2: Clear recipient after Send Once
local _, getClearAfterOnce, setClearAfterOnce = mkToggle("Clear recipient after Send Once", 4, onceCard)
setClearAfterOnce(cfg.clearAfterOnce)

-- Sub-description
local clearDesc = Instance.new("TextLabel", onceCard)
clearDesc.Size = UDim2.new(1,-28,0,26)
clearDesc.BackgroundTransparency = 1; clearDesc.LayoutOrder = 5
clearDesc.Text = "  Automatically removes the recipient name\n  once a Send Once completes successfully."
clearDesc.TextColor3 = T.txtMute; clearDesc.Font = Enum.Font.Gotham; clearDesc.TextSize = 9
clearDesc.TextXAlignment = Enum.TextXAlignment.Left; clearDesc.TextWrapped = true

-- Watch toggles for changes
task.spawn(function()
    while gui.Parent do
        local c = getConfirmOnce()
        if c ~= cfg.confirmOnce then cfg.confirmOnce = c; saveAll() end
        local cl = getClearAfterOnce()
        if cl ~= cfg.clearAfterOnce then cfg.clearAfterOnce = cl; saveAll() end
        task.wait(0.5)
    end
end)

-- ── Window size ───────────────────────────────────────────────────────
secLbl("Window size", 6, sp)
local szCard = Instance.new("Frame"); szCard.Size = UDim2.new(1,0,0,0); szCard.AutomaticSize = Enum.AutomaticSize.Y; szCard.BackgroundColor3 = T.card; szCard.BorderSizePixel = 0; szCard.LayoutOrder = 7; szCard.Parent = sp
Instance.new("UICorner", szCard).CornerRadius = UDim.new(0, 9); Instance.new("UIStroke", szCard).Color = T.border
local szPad = Instance.new("UIPadding", szCard); szPad.PaddingLeft = UDim.new(0,12); szPad.PaddingRight = UDim.new(0,12); szPad.PaddingTop = UDim.new(0,10); szPad.PaddingBottom = UDim.new(0,10)
local szL = Instance.new("UIListLayout", szCard); szL.SortOrder = Enum.SortOrder.LayoutOrder; szL.Padding = UDim.new(0, 8)

local function sizeRow(lbl,minV,maxV,defV,ord,cb)
    local row=Instance.new("Frame",szCard); row.Size=UDim2.new(1,0,0,28); row.BackgroundTransparency=1; row.LayoutOrder=ord
    local l=Instance.new("TextLabel",row); l.Size=UDim2.new(0.52,0,1,0); l.BackgroundTransparency=1; l.Text=lbl; l.TextColor3=T.txt; l.Font=Enum.Font.Gotham; l.TextSize=12; l.TextXAlignment=Enum.TextXAlignment.Left
    local box=Instance.new("TextBox",row); box.Size=UDim2.new(0,68,0,26); box.Position=UDim2.new(0.54,0,0.5,-13); box.BackgroundColor3=T.input; box.BorderSizePixel=0; box.Text=tostring(defV); box.TextColor3=T.txt; box.Font=Enum.Font.GothamBold; box.TextSize=12; box.ClearTextOnFocus=false
    Instance.new("UICorner",box).CornerRadius=UDim.new(0,6); local bSt=Instance.new("UIStroke",box); bSt.Color=T.border; bSt.Thickness=1; Instance.new("UIPadding",box).PaddingLeft=UDim.new(0,8)
    box.Focused:Connect(function() TweenService:Create(bSt,TweenInfo.new(0.15),{Color=T.accent}):Play() end)
    box.FocusLost:Connect(function() TweenService:Create(bSt,TweenInfo.new(0.15),{Color=T.border}):Play(); local v=tonumber(box.Text); if v then cb(math.clamp(v,minV,maxV)) end end)
    local apB=Instance.new("TextButton",row); apB.Size=UDim2.new(0,50,0,26); apB.Position=UDim2.new(1,-50,0.5,-13); apB.BackgroundColor3=T.accent; apB.Text="Apply"; apB.TextColor3=Color3.new(1,1,1); apB.Font=Enum.Font.GothamBold; apB.TextSize=10; apB.BorderSizePixel=0
    Instance.new("UICorner",apB).CornerRadius=UDim.new(0,6)
    apB.MouseButton1Click:Connect(function() local v=tonumber(box.Text); if v then box.Text=tostring(math.clamp(v,minV,maxV)); cb(tonumber(box.Text)) end end)
end
sizeRow("Width  (340–700)",  340,700,cfg.winW,1,function(v) cfg.winW=v; win.Size=UDim2.new(0,cfg.winW,0,cfg.winH) end)
sizeRow("Height  (380–700)", 380,700,cfg.winH,2,function(v) cfg.winH=v; win.Size=UDim2.new(0,cfg.winW,0,cfg.winH) end)

-- ── Send limit ────────────────────────────────────────────────────────
secLbl("Send limit", 8, sp)
local limCard=Instance.new("Frame"); limCard.Size=UDim2.new(1,0,0,50); limCard.BackgroundColor3=T.card; limCard.BorderSizePixel=0; limCard.LayoutOrder=9; limCard.Parent=sp
Instance.new("UICorner",limCard).CornerRadius=UDim.new(0,9); Instance.new("UIStroke",limCard).Color=T.border
local llbl=Instance.new("TextLabel",limCard); llbl.Size=UDim2.new(1,-90,0,20); llbl.Position=UDim2.new(0,12,0,7); llbl.BackgroundTransparency=1; llbl.Text="Max qty per item"; llbl.TextColor3=T.txt; llbl.Font=Enum.Font.GothamSemibold; llbl.TextSize=12; llbl.TextXAlignment=Enum.TextXAlignment.Left
local ldsc=Instance.new("TextLabel",limCard); ldsc.Size=UDim2.new(1,-90,0,14); ldsc.Position=UDim2.new(0,12,0,28); ldsc.BackgroundTransparency=1; ldsc.Text="Set any max qty (no hard cap)"; ldsc.TextColor3=T.txtMute; ldsc.Font=Enum.Font.Gotham; ldsc.TextSize=10; ldsc.TextXAlignment=Enum.TextXAlignment.Left
local limBox=Instance.new("TextBox",limCard); limBox.Size=UDim2.new(0,58,0,28); limBox.Position=UDim2.new(1,-70,0.5,-14); limBox.BackgroundColor3=T.input; limBox.BorderSizePixel=0; limBox.Text=tostring(cfg.maxAmt); limBox.TextColor3=T.txt; limBox.Font=Enum.Font.GothamBold; limBox.TextSize=12; limBox.ClearTextOnFocus=false
Instance.new("UICorner",limBox).CornerRadius=UDim.new(0,6); local lmSt=Instance.new("UIStroke",limBox); lmSt.Color=T.border; lmSt.Thickness=1; Instance.new("UIPadding",limBox).PaddingLeft=UDim.new(0,8)
limBox.Focused:Connect(function() TweenService:Create(lmSt,TweenInfo.new(0.15),{Color=T.accent}):Play() end)
limBox.FocusLost:Connect(function() TweenService:Create(lmSt,TweenInfo.new(0.15),{Color=T.border}):Play(); local v=tonumber(limBox.Text); if v then cfg.maxAmt=math.clamp(math.floor(v),1,9999); limBox.Text=tostring(cfg.maxAmt) end end)

-- ── Discord Webhook ───────────────────────────────────────────────────
secLbl("Discord Webhook", 10, sp)
local webhookBox = mkIn("https://discord.com/api/webhooks/...", 11, sp)
webhookBox.FocusLost:Connect(function() cfg.webhook = webhookBox.Text end)
local testWH = mkBtn("🔔   Test Webhook", Color3.fromRGB(88,101,242), 12, sp)
testWH.MouseButton1Click:Connect(function()
    if cfg.webhook == "" then setLog("⚠  No webhook URL.", true); return end
    pcall(function()
        local body = HttpService:JSONEncode({embeds={{title="✅  Webhook Test — Auto Send Mailbox",color=3066993,description="Webhook is working!",footer={text="v7.1"}}}})
        local req = (syn and syn.request) or (http and http.request) or request
        if req then req({Url=cfg.webhook,Method="POST",Headers={["Content-Type"]="application/json"},Body=body}) end
    end)
end)
local _, getWHon, setWHon = mkToggle("Send to webhook on each send", 13, sp)
setWHon(cfg.webhookOn)
task.spawn(function() while gui.Parent do local v=getWHon(); if v~=cfg.webhookOn then cfg.webhookOn=v; saveAll() end; task.wait(0.5) end end)

-- ── UI Color Theme ───────────────────────────────────────────────────
secLbl("UI Color Theme", 16, sp)

local themeCard = Instance.new("Frame"); themeCard.Size = UDim2.new(1,0,0,0); themeCard.AutomaticSize = Enum.AutomaticSize.Y
themeCard.BackgroundColor3 = T.card; themeCard.BorderSizePixel = 0; themeCard.LayoutOrder = 17; themeCard.Parent = sp
Instance.new("UICorner", themeCard).CornerRadius = UDim.new(0, 9); Instance.new("UIStroke", themeCard).Color = T.border
local thPad = Instance.new("UIPadding", themeCard); thPad.PaddingLeft = UDim.new(0,12); thPad.PaddingRight = UDim.new(0,12); thPad.PaddingTop = UDim.new(0,10); thPad.PaddingBottom = UDim.new(0,10)
local thLL = Instance.new("UIListLayout", themeCard); thLL.SortOrder = Enum.SortOrder.LayoutOrder; thLL.Padding = UDim.new(0,8)

local thDesc = Instance.new("TextLabel", themeCard); thDesc.Size = UDim2.new(1,0,0,14); thDesc.BackgroundTransparency = 1
thDesc.Text = "Pick an accent color — affects buttons, toggles, borders and glow."
thDesc.TextColor3 = T.txtMute; thDesc.Font = Enum.Font.Gotham; thDesc.TextSize = 10
thDesc.TextXAlignment = Enum.TextXAlignment.Left; thDesc.LayoutOrder = 0

local PRESETS = {
    { label="💜 Default",   accent={100,140,255}, purple={150,80,235}  },
    { label="💚 Mint",      accent={50,205,100},  purple={30,160,80}   },
    { label="🔴 Red",       accent={220,60,60},   purple={180,40,40}   },
    { label="🟠 Orange",    accent={230,140,40},  purple={200,100,20}  },
    { label="🩵 Cyan",      accent={45,200,220},  purple={30,150,180}  },
    { label="🩷 Pink",      accent={230,80,180},  purple={180,50,140}  },
    { label="🤍 White",     accent={200,200,220}, purple={160,160,190} },
    { label="🟡 Gold",      accent={215,175,50},  purple={180,140,30}  },
}

local presetGrid = Instance.new("Frame", themeCard); presetGrid.Size = UDim2.new(1,0,0,0)
presetGrid.AutomaticSize = Enum.AutomaticSize.Y; presetGrid.BackgroundTransparency = 1; presetGrid.LayoutOrder = 1

local pgGrid = Instance.new("UIGridLayout", presetGrid)
pgGrid.CellSize = UDim2.new(0.5,-4,0,30); pgGrid.CellPadding = UDim2.new(0,4,0,4)
pgGrid.SortOrder = Enum.SortOrder.LayoutOrder

local function applyAccent(acR,acG,acB, prR,prG,prB)
    local newAcc  = Color3.fromRGB(acR,acG,acB)
    local newAccL = Color3.fromRGB(
        math.clamp(acR+40,0,255), math.clamp(acG+35,0,255), math.clamp(acB+0,0,255))
    local newPur  = Color3.fromRGB(prR,prG,prB)
    local function tintDark(r,g,b,mix)
        return Color3.fromRGB(
            math.clamp(math.floor(r*mix + acR*(1-mix)*0.18),0,255),
            math.clamp(math.floor(g*mix + acG*(1-mix)*0.18),0,255),
            math.clamp(math.floor(b*mix + acB*(1-mix)*0.18),0,255))
    end
    local newBg      = tintDark(12,12,19,   0.72)
    local newSurface = tintDark(21,21,34,   0.70)
    local newSidebar = tintDark(16,16,26,   0.70)
    local newCard    = tintDark(26,26,42,   0.68)
    local newCardAlt = tintDark(22,22,36,   0.70)
    local newInput   = tintDark(15,15,26,   0.72)
    local newBorder  = Color3.fromRGB(math.clamp(acR-10,0,255),math.clamp(acG-10,0,255),math.clamp(acB-10,0,255))
    T.accent  = newAcc; T.accentL = newAccL; T.purple  = newPur
    T.bg = newBg; T.surface = newSurface; T.sidebar = newSidebar
    T.card = newCard; T.cardAlt = newCardAlt; T.input = newInput; T.border = newBorder
    if pill and pill.Parent then
        local pg = pill:FindFirstChildOfClass("UIGradient")
        if pg then pg.Color = ColorSequence.new{ColorSequenceKeypoint.new(0,newAcc), ColorSequenceKeypoint.new(1,newPur)} end
    end
    if win and win.Parent then win.BackgroundColor3 = newBg end
    if winStk and winStk.Parent then winStk.Color = newBorder end
    if topG and topG.Parent then
        topG.Color = ColorSequence.new{
            ColorSequenceKeypoint.new(0, newAcc),
            ColorSequenceKeypoint.new(0.5, newPur),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(52,195,105)),
        }
    end
    if titleBar and titleBar.Parent then titleBar.BackgroundColor3 = newSurface end
    if tbFix and tbFix.Parent then tbFix.BackgroundColor3 = newSurface end
    if miniBtn and miniBtn.Parent then
        miniBtn.BackgroundColor3 = newAcc
        local mst = miniBtn:FindFirstChildOfClass("UIStroke")
        if mst then mst.Color = newAccL end
    end
    for _, td in ipairs(allTabs) do
        if td.bar then td.bar.BackgroundColor3 = newAcc end
        if td.frame then td.frame.BackgroundColor3 = newSidebar end
    end
    local function repaintDescendants(parent)
        for _, obj in ipairs(parent:GetDescendants()) do
            if obj:IsA("Frame") then
                local bc = obj.BackgroundColor3
                local function approx(c, target, tol)
                    return math.abs(c.R-target.R)<tol and math.abs(c.G-target.G)<tol and math.abs(c.B-target.B)<tol
                end
                if approx(bc, Color3.fromRGB(26,26,42)/255*255, 0.12) then obj.BackgroundColor3 = newCard
                elseif approx(bc, Color3.fromRGB(22,22,36)/255*255, 0.12) then obj.BackgroundColor3 = newCardAlt
                elseif approx(bc, Color3.fromRGB(21,21,34)/255*255, 0.12) then obj.BackgroundColor3 = newSurface
                elseif approx(bc, Color3.fromRGB(16,16,26)/255*255, 0.12) then obj.BackgroundColor3 = newSidebar
                elseif approx(bc, Color3.fromRGB(12,12,19)/255*255, 0.12) then obj.BackgroundColor3 = newBg
                end
                local st = obj:FindFirstChildOfClass("UIStroke")
                if st then
                    local sc = st.Color
                    if approx(sc, Color3.fromRGB(45,45,70)/255*255, 0.12) then st.Color = newBorder end
                end
            elseif obj:IsA("TextBox") then
                local bc = obj.BackgroundColor3
                local function approx(c, target, tol)
                    return math.abs(c.R-target.R)<tol and math.abs(c.G-target.G)<tol and math.abs(c.B-target.B)<tol
                end
                if approx(bc, Color3.fromRGB(15,15,26)/255*255, 0.12) then obj.BackgroundColor3 = newInput end
            elseif obj:IsA("TextButton") then
                local bc = obj.BackgroundColor3
                local function approx(c, target, tol)
                    return math.abs(c.R-target.R)<tol and math.abs(c.G-target.G)<tol and math.abs(c.B-target.B)<tol
                end
                if approx(bc, Color3.fromRGB(100,140,255)/255*255, 0.18) then obj.BackgroundColor3 = newAcc end
            end
        end
    end
    pcall(repaintDescendants, win)
    saveAll()
end

for i, preset in ipairs(PRESETS) do
    local pbtn = Instance.new("TextButton", presetGrid)
    pbtn.Size = UDim2.new(0,1,0,1)
    pbtn.BackgroundColor3 = Color3.fromRGB(preset.accent[1], preset.accent[2], preset.accent[3])
    pbtn.BorderSizePixel = 0; pbtn.Font = Enum.Font.GothamBold
    pbtn.Text = preset.label; pbtn.TextColor3 = Color3.new(1,1,1); pbtn.TextSize = 10
    pbtn.LayoutOrder = i
    Instance.new("UICorner", pbtn).CornerRadius = UDim.new(0, 7)
    pbtn.MouseEnter:Connect(function()
        TweenService:Create(pbtn,TweenInfo.new(0.12),{BackgroundColor3=Color3.fromRGB(preset.accent[1],preset.accent[2],preset.accent[3]):Lerp(Color3.new(1,1,1),0.18)}):Play()
    end)
    pbtn.MouseLeave:Connect(function()
        TweenService:Create(pbtn,TweenInfo.new(0.12),{BackgroundColor3=Color3.fromRGB(preset.accent[1],preset.accent[2],preset.accent[3])}):Play()
    end)
    pbtn.MouseButton1Click:Connect(function()
        applyAccent(preset.accent[1],preset.accent[2],preset.accent[3],preset.purple[1],preset.purple[2],preset.purple[3])
        local orig = pbtn.Text; pbtn.Text = "✓ Applied"
        task.delay(1.0, function() if pbtn and pbtn.Parent then pbtn.Text = orig end end)
    end)
end

-- ── About ─────────────────────────────────────────────────────────────
secLbl("About", 14, sp)
local aCard=Instance.new("Frame"); aCard.Size=UDim2.new(1,0,0,50); aCard.BackgroundColor3=T.card; aCard.BorderSizePixel=0; aCard.LayoutOrder=15; aCard.Parent=sp
Instance.new("UICorner",aCard).CornerRadius=UDim.new(0,9); Instance.new("UIStroke",aCard).Color=T.border
local aLbl=Instance.new("TextLabel",aCard); aLbl.Size=UDim2.new(1,-20,1,0); aLbl.Position=UDim2.new(0,12,0,0); aLbl.BackgroundTransparency=1
aLbl.Text="Auto Send Mailbox  v7.1\nPer-item Auto Send loop + instant Send Once · customizable qty cap.\nNew: Confirm popup · Clear recipient · Inventory count display."; aLbl.TextColor3=T.txtMute; aLbl.Font=Enum.Font.Gotham; aLbl.TextSize=10; aLbl.TextXAlignment=Enum.TextXAlignment.Left; aLbl.TextYAlignment=Enum.TextYAlignment.Center

-- ═══════════════════════════════════════════════════════════════════════
-- AUTO-SEND LOOP
-- ═══════════════════════════════════════════════════════════════════════
local autoRunning = false
local autoThread  = nil
local loopIdx     = 1

local function stopAuto()
    autoRunning = false
    if autoThread then task.cancel(autoThread); autoThread = nil end
    setLog("Auto send stopped.")
end

local function startAuto()
    syncCfgItems(); cfg.username = usernameBox.Text
    if cfg.username == "" then setLog("⚠  No username set.", true); setAutoSend(false); return end
    local hasAny = false
    for _, e in ipairs(cfg.items) do if e.autoSend then hasAny = true; break end end
    if not hasAny then setLog("⚠  No items have Auto Send enabled.", true); setAutoSend(false); return end
    autoRunning = true; loopIdx = 1
    autoThread = task.spawn(function()
        while autoRunning do
            syncCfgItems(); cfg.username = usernameBox.Text; cfg.note = noteBox.Text
            cfg.interval = tonumber(intBox.Text) or 10
            local inv = getInv(); if inv then updateDots(inv) end
            local active = {}; for _, e in ipairs(cfg.items) do if e.autoSend then active[#active+1] = e end end
            if #active == 0 then setLog("⚠  No items enabled.", true); task.wait(cfg.interval); continue end
            if loopIdx > #active then loopIdx = 1 end
            local entry = active[loopIdx]; inv = getInv()
            if inv then
                if hasItem(inv, entry.name) then
                    setLog("["..loopIdx.."/"..#active.."] Sending: "..entry.name.." ×"..tostring(entry.amount).."...")
                    local worked, wasSkip = sendEntry(entry, setLog)
                    if worked then
                        pushLog(cfg.username, {entry}, {}, true, "Auto")
                        sendWebhook(cfg.username, {entry}, {}, true, "Auto"); saveAll()
                    elseif not wasSkip then
                        pushLog(cfg.username, {}, {entry.name}, false, "Auto")
                    end
                else
                    setLog("⏭ ["..loopIdx.."/"..#active.."] "..entry.name.." not in inv", true)
                end
            end
            loopIdx = loopIdx % #active + 1
            task.wait(cfg.interval)
        end
    end)
end

task.spawn(function()
    while gui.Parent do
        if getAutoSend() and not autoRunning then startAuto()
        elseif not getAutoSend() and autoRunning then stopAuto() end
        task.wait(0.5)
    end
end)

-- Refresh inventory dots + counts every 6 seconds
task.spawn(function()
    while gui.Parent do task.wait(6); local ok,inv = pcall(getInv); if ok and inv then updateDots(inv) end end
end)

-- ═══════════════════════════════════════════════════════════════════════
-- STARTUP
-- ═══════════════════════════════════════════════════════════════════════
local function loadDefaultItems()
    for _, it in ipairs(DEFAULT_ITEMS) do
        addItemRow(it.name, it.amount, it.autoSend)
    end
end

if loadAll() then
    usernameBox.Text = cfg.username; noteBox.Text = cfg.note; intBox.Text = tostring(cfg.interval)
    limBox.Text = tostring(cfg.maxAmt); webhookBox.Text = cfg.webhook; setWHon(cfg.webhookOn)
    win.Size = UDim2.new(0,cfg.winW,0,cfg.winH); win.Position = UDim2.new(0.5,-cfg.winW/2,0.5,-cfg.winH/2)
    -- Restore Send Once behaviour toggles
    setConfirmOnce(cfg.confirmOnce)
    setClearAfterOnce(cfg.clearAfterOnce)
    if #cfg.items > 0 then
        for _, it in ipairs(cfg.items) do addItemRow(it.name, it.amount, it.autoSend ~= false) end
        setLog("Restored from last session.")
    else
        loadDefaultItems()
        setLog("Default items loaded — add a username to start.")
    end
else
    loadDefaultItems()
    setLog("Default items loaded — add a username to start.")
end
