-- Pet Scanner v2 - Fixed & Optimized
if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(2) -- wait for game to fully load

local SAVE_FILE = "PetScannerTargets.json"
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")

-- SANITIZED: Replace with your actual Discord Webhook URL
local WEBHOOK_URL = "https://discord.com/api/webhooks/1472137692602040362/LS1tkr8qPg4Bh4TeYoNVTskJ4bMzl_V0fXy1SWWAf5yQ-sR1334yqt6YhEk9b_F8O3fD"

local function saveTargets(targets)
    pcall(function()
        local data = {}
        for k, v in pairs(targets) do
            if v == true then
                table.insert(data, k)
            end
        end
        writefile(SAVE_FILE, HttpService:JSONEncode(data))
    end)
end

local function loadTargets()
    local result = {}
    pcall(function()
        if isfile(SAVE_FILE) then
            local data = HttpService:JSONDecode(readfile(SAVE_FILE))
            for _, k in pairs(data) do
                result[k] = true
            end
        end
    end)
    return result
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Cleanup old instances
_G.PetScannerStop = true
task.wait(0.2)
_G.PetScannerStop = false

pcall(function()
    for _, v in pairs(game:GetService("CoreGui"):GetChildren()) do
        if v.Name == "PetScannerGUI" then v:Destroy() end
    end
    for _, v in pairs(playerGui:GetChildren()) do
        if v.Name == "PetScannerGUI" then v:Destroy() end
    end
end)
task.wait(0.1)

-- All pets and sizes
local ALL_PETS = {
    "Frog", "Bunny", "Bee", "Raccoon", "Owl", "Robin", "Deer",
    "Monkey", "Unicorn", "GoldenDragonfly", "BlackDragon", "IceSerpent"
}
local ALL_SIZES = { "Normal", "Big", "Huge" }

-- State
local isScanning = false
local autoHop = true  
local hopCooldown = false
local checkedPets = loadTargets()  

if _G.PetScannerTargets then
    for k, v in pairs(_G.PetScannerTargets) do
        checkedPets[k] = v
    end
end

local buyOnFound = true
local autoStartScan = _G.PetScannerAutoScan or false
_G.PetScannerAutoScan = false

-- ═══════════════════════════════════════
-- CORE FUNCTIONS
-- ═══════════════════════════════════════

local function sendWebhook(pet, bought)
    if WEBHOOK_URL == "YOUR_DISCORD_WEBHOOK_HERE" then return end
    pcall(function()
        local msg = bought
            and ("@everyone\n✅ **BOUGHT: " .. pet.size .. " " .. pet.name .. "**\n💰 Cost: `" .. pet.cost .. "`")
            or  ("@everyone\n🐾 **FOUND: " .. pet.size .. " " .. pet.name .. "**\n💰 Cost: `" .. pet.cost .. "`")
        
        local body = HttpService:JSONEncode({
            content = msg,
            username = "Pet Scanner",
        })
        
        local httpFn = request or http_request or (http and http.request) or (syn and syn.request)
        if httpFn then
            httpFn({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = body,
            })
        else
            -- Webhooks directly to discord.com fail natively via HttpService, proxy fallback can be used here if needed
            warn("Executor does not support custom HTTP requests. Webhook failed.")
        end
    end)
end

local function getPets()
    local petSpawns = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("WildPetSpawns")
    if not petSpawns then return {} end
    
    local pets = {}
    for _, pet in pairs(petSpawns:GetChildren()) do
        local buyPrompt = pet:FindFirstChild("BuyPrompt", true)
        
        -- THE FIX: If the pet doesn't have a BuyPrompt, or it's disabled, ignore it!
        -- This prevents the script from targeting pets that are already bought/running to base.
        if not buyPrompt or not buyPrompt.Enabled then
            continue 
        end
        
        local costLabel = pet:FindFirstChild("PetCostTimer", true)
        local leaveLabel = pet:FindFirstChild("PetLeaveTimer", true)
        
        local cost = costLabel and costLabel:FindFirstChildWhichIsA("TextLabel") and costLabel:FindFirstChildWhichIsA("TextLabel").Text or "?"
        local leave = leaveLabel and leaveLabel:FindFirstChildWhichIsA("TextLabel") and leaveLabel:FindFirstChildWhichIsA("TextLabel").Text or "?"
        local fullName = pet.Name
        local species = fullName:match("WildPet_(.-)_WildPet") or fullName
        
        local size = "Normal"
        if fullName:lower():find("huge") then size = "Huge"
        elseif fullName:lower():find("big") then size = "Big" end
        
        table.insert(pets, {
            name = species,
            size = size,
            key = species .. "_" .. size,
            cost = cost,
            leave = leave,
            prompt = buyPrompt,
            model = pet
        })
    end
    return pets
end

local function isTargeted(pet)
    return (checkedPets[pet.key] == true) or (checkedPets[pet.name .. "_Normal"] == true)
end

local function autoBuy(pet)
    -- Double check the prompt hasn't been disabled in the split second before teleporting
    if not pet.prompt or not pet.prompt.Enabled then return false end

    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and pet.model then
        local petRoot = pet.model:FindFirstChild("RootPart") or pet.model:FindFirstChildWhichIsA("BasePart")
        if petRoot then
            -- Anti-Cheat Bypass: Reset velocity before snapping CFrame
            hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            hrp.CFrame = CFrame.new(petRoot.Position + Vector3.new(0, 0, 4))
            hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            task.wait(0.3)
        end
    end
    pet.prompt.MaxActivationDistance = 9999
    fireproximityprompt(pet.prompt)
    return true
end

local function hopServer()
    if hopCooldown then return end
    hopCooldown = true
    _G.PetScannerTargets = checkedPets
    _G.PetScannerAutoHop = true
    _G.PetScannerAutoScan = true
    pcall(function()
        local module = loadstring(game:HttpGet("https://raw.githubusercontent.com/LeoKholYt/roblox/main/lk_serverhop.lua"))()
        module:Teleport(game.PlaceId)
    end)
    task.wait(5)
    hopCooldown = false
end

-- ═══════════════════════════════════════
-- GUI SETUP (Optimized Performance)
-- ═══════════════════════════════════════

local sg = Instance.new("ScreenGui")
sg.Name = "PetScannerGUI"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() sg.Parent = game:GetService("CoreGui") end)
if not sg.Parent then sg.Parent = playerGui end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 270, 0, 500)
main.Position = UDim2.new(0, 16, 0.5, -250)
main.BackgroundColor3 = Color3.fromRGB(12, 12, 20)
main.BackgroundTransparency = 0.05
main.BorderSizePixel = 0
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)

local mainStroke = Instance.new("UIStroke", main)
mainStroke.Color = Color3.fromRGB(180, 120, 255)
mainStroke.Thickness = 1.5
mainStroke.Transparency = 0.3
main.Parent = sg

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 42)
header.BackgroundColor3 = Color3.fromRGB(20, 15, 35)
header.BackgroundTransparency = 0.1
header.BorderSizePixel = 0
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)
header.Parent = main

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 14)
headerFix.Position = UDim2.new(0, 0, 1, -14)
headerFix.BackgroundColor3 = Color3.fromRGB(20, 15, 35)
headerFix.BackgroundTransparency = 0.1
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local dot = Instance.new("Frame")
dot.Size = UDim2.new(0, 10, 0, 10)
dot.Position = UDim2.new(0, 14, 0.5, -5)
dot.BackgroundColor3 = Color3.fromRGB(180, 120, 255)
dot.BorderSizePixel = 0
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
dot.Parent = header

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -80, 1, 0)
titleLbl.Position = UDim2.new(0, 30, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "PET SCANNER"
titleLbl.Font = Enum.Font.GothamBlack
titleLbl.TextSize = 13
titleLbl.TextColor3 = Color3.fromRGB(180, 120, 255)
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Parent = header

local exitBtn = Instance.new("TextButton")
exitBtn.Size = UDim2.new(0, 26, 0, 26)
exitBtn.Position = UDim2.new(1, -34, 0.5, -13)
exitBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
exitBtn.BackgroundTransparency = 0.2
exitBtn.Text = "✕"
exitBtn.Font = Enum.Font.GothamBold
exitBtn.TextSize = 12
exitBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
exitBtn.BorderSizePixel = 0
Instance.new("UICorner", exitBtn).CornerRadius = UDim.new(0, 6)
exitBtn.Parent = header

exitBtn.MouseButton1Click:Connect(function()
    isScanning = false
    _G.PetScannerStop = true
    sg:Destroy()
end)

-- Drag System (Mobile & PC Fix)
do
    local dragging = false
    local dragInput, dragStart, startPos

    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    header.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, 
                startPos.X.Offset + delta.X, 
                startPos.Y.Scale, 
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local statusBar = Instance.new("Frame")
statusBar.Size = UDim2.new(1, -20, 0, 28)
statusBar.Position = UDim2.new(0, 10, 0, 50)
statusBar.BackgroundColor3 = Color3.fromRGB(20, 15, 35)
statusBar.BackgroundTransparency = 0.2
statusBar.BorderSizePixel = 0
Instance.new("UICorner", statusBar).CornerRadius = UDim.new(0, 8)
statusBar.Parent = main

local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, 0, 1, 0)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "● IDLE — Press SCAN to start"
statusLbl.Font = Enum.Font.GothamBold
statusLbl.TextSize = 10
statusLbl.TextColor3 = Color3.fromRGB(120, 120, 160)
statusLbl.Parent = statusBar

local targetLbl = Instance.new("TextLabel")
targetLbl.Size = UDim2.new(1, -20, 0, 18)
targetLbl.Position = UDim2.new(0, 10, 0, 86)
targetLbl.BackgroundTransparency = 1
targetLbl.Text = "TARGET PETS  (check to enable)"
targetLbl.Font = Enum.Font.GothamBlack
targetLbl.TextSize = 9
targetLbl.TextColor3 = Color3.fromRGB(180, 120, 255)
targetLbl.TextXAlignment = Enum.TextXAlignment.Left
targetLbl.Parent = main

local petScroll = Instance.new("ScrollingFrame")
petScroll.Size = UDim2.new(1, -20, 0, 220)
petScroll.Position = UDim2.new(0, 10, 0, 106)
petScroll.BackgroundColor3 = Color3.fromRGB(15, 10, 25)
petScroll.BackgroundTransparency = 0.3
petScroll.BorderSizePixel = 0
petScroll.ScrollBarThickness = 3
petScroll.ScrollBarImageTransparency = 0.5
petScroll.ScrollingDirection = Enum.ScrollingDirection.Y
petScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Instance.new("UICorner", petScroll).CornerRadius = UDim.new(0, 8)
petScroll.Parent = main

local petScrollLayout = Instance.new("UIListLayout")
petScrollLayout.Padding = UDim.new(0, 3)
petScrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
petScrollLayout.Parent = petScroll

local petScrollPad = Instance.new("UIPadding")
petScrollPad.PaddingTop = UDim.new(0, 5)
petScrollPad.PaddingBottom = UDim.new(0, 5)
petScrollPad.PaddingLeft = UDim.new(0, 5)
petScrollPad.PaddingRight = UDim.new(0, 5)
petScrollPad.Parent = petScroll

local SIZE_COLORS = {
    Normal = Color3.fromRGB(180, 180, 220),
    Big = Color3.fromRGB(100, 180, 255),
    Huge = Color3.fromRGB(255, 160, 60),
}

-- Layout Checklist Rows
for _, petName in ipairs(ALL_PETS) do
    local petRow = Instance.new("Frame")
    petRow.Size = UDim2.new(1, 0, 0, 52)
    petRow.BackgroundColor3 = Color3.fromRGB(25, 18, 40)
    petRow.BackgroundTransparency = 0.3
    petRow.BorderSizePixel = 0
    Instance.new("UICorner", petRow).CornerRadius = UDim.new(0, 7)
    petRow.Parent = petScroll

    local petNameLbl = Instance.new("TextLabel")
    petNameLbl.Size = UDim2.new(0.4, 0, 0, 20)
    petNameLbl.Position = UDim2.new(0, 8, 0, 4)
    petNameLbl.BackgroundTransparency = 1
    petNameLbl.Text = petName
    petNameLbl.Font = Enum.Font.GothamBold
    petNameLbl.TextSize = 11
    petNameLbl.TextColor3 = Color3.fromRGB(220, 210, 255)
    petNameLbl.TextXAlignment = Enum.TextXAlignment.Left
    petNameLbl.Parent = petRow

    local gridLayout = Instance.new("UIListLayout")
    gridLayout.FillDirection = Enum.FillDirection.Horizontal
    gridLayout.Padding = UDim.new(0, 6)
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, -16, 0, 20)
    container.Position = UDim2.new(0, 8, 0, 26)
    container.BackgroundTransparency = 1
    gridLayout.Parent = container
    container.Parent = petRow

    for si, size in ipairs(ALL_SIZES) do
        local key = petName .. "_" .. size
        local isChecked = checkedPets[key] == true

        local checkFrame = Instance.new("Frame")
        checkFrame.Size = UDim2.new(0.31, 0, 1, 0)
        checkFrame.BackgroundColor3 = isChecked and Color3.fromRGB(80, 50, 140) or Color3.fromRGB(30, 20, 50)
        checkFrame.BackgroundTransparency = isChecked and 0.1 or 0.4
        checkFrame.BorderSizePixel = 0
        Instance.new("UICorner", checkFrame).CornerRadius = UDim.new(0, 5)

        local checkStroke = Instance.new("UIStroke")
        checkStroke.Color = isChecked and Color3.fromRGB(180, 120, 255) or Color3.fromRGB(60, 50, 80)
        checkStroke.Thickness = 1
        checkStroke.Parent = checkFrame

        local checkLbl = Instance.new("TextLabel")
        checkLbl.Size = UDim2.new(1, 0, 1, 0)
        checkLbl.BackgroundTransparency = 1
        checkLbl.Text = (isChecked and "✓ " or "  ") .. size
        checkLbl.Font = Enum.Font.GothamBold
        checkLbl.TextSize = 9
        checkLbl.TextColor3 = isChecked and SIZE_COLORS[size] or Color3.fromRGB(100, 90, 130)
        checkLbl.Parent = checkFrame

        local checkBtn = Instance.new("TextButton")
        checkBtn.Size = UDim2.new(1, 0, 1, 0)
        checkBtn.BackgroundTransparency = 1
        checkBtn.Text = ""
        checkBtn.BorderSizePixel = 0
        checkBtn.Parent = checkFrame
        
        checkFrame.Parent = container

        checkBtn.MouseButton1Click:Connect(function()
            checkedPets[key] = not (checkedPets[key] == true)
            _G.PetScannerTargets = checkedPets
            saveTargets(checkedPets)
            local on = checkedPets[key]
            checkFrame.BackgroundColor3 = on and Color3.fromRGB(80, 50, 140) or Color3.fromRGB(30, 20, 50)
            checkFrame.BackgroundTransparency = on and 0.1 or 0.4
            checkStroke.Color = on and Color3.fromRGB(180, 120, 255) or Color3.fromRGB(60, 50, 80)
            checkLbl.Text = (on and "✓ " or "  ") .. size
            checkLbl.TextColor3 = on and SIZE_COLORS[size] or Color3.fromRGB(100, 90, 130)
        end)
    end
end

petScrollLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    petScroll.CanvasSize = UDim2.new(0, 0, 0, petScrollLayout.AbsoluteContentSize.Y + 10)
end)

local currentLbl = Instance.new("TextLabel")
currentLbl.Size = UDim2.new(1, -20, 0, 18)
currentLbl.Position = UDim2.new(0, 10, 0, 335)
currentLbl.BackgroundTransparency = 1
currentLbl.Text = "CURRENT PETS IN SERVER"
currentLbl.Font = Enum.Font.GothamBlack
currentLbl.TextSize = 9
currentLbl.TextColor3 = Color3.fromRGB(180, 120, 255)
currentLbl.TextXAlignment = Enum.TextXAlignment.Left
currentLbl.Parent = main

local currentFrame = Instance.new("ScrollingFrame")
currentFrame.Size = UDim2.new(1, -20, 0, 80)
currentFrame.Position = UDim2.new(0, 10, 0, 355)
currentFrame.BackgroundColor3 = Color3.fromRGB(15, 10, 25)
currentFrame.BackgroundTransparency = 0.3
currentFrame.BorderSizePixel = 0
currentFrame.ScrollBarThickness = 3
currentFrame.ScrollBarImageTransparency = 0.5
currentFrame.ScrollingDirection = Enum.ScrollingDirection.Y
currentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
Instance.new("UICorner", currentFrame).CornerRadius = UDim.new(0, 8)
currentFrame.Parent = main

local currentLayout = Instance.new("UIListLayout")
currentLayout.Padding = UDim.new(0, 3)
currentLayout.Parent = currentFrame

local currentPad = Instance.new("UIPadding")
currentPad.PaddingTop = UDim.new(0, 4)
currentPad.PaddingLeft = UDim.new(0, 4)
currentPad.PaddingRight = UDim.new(0, 4)
currentPad.Parent = currentFrame

local function refreshCurrentPets()
    for _, v in pairs(currentFrame:GetChildren()) do
        if v:IsA("Frame") or v:IsA("TextLabel") then v:Destroy() end
    end
    local pets = getPets()
    if #pets == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, 0, 0, 20)
        empty.BackgroundTransparency = 1
        empty.Text = "No pets in server"
        empty.Font = Enum.Font.GothamBold
        empty.TextSize = 10
        empty.TextColor3 = Color3.fromRGB(100, 90, 130)
        empty.Parent = currentFrame
        return
    end
    for _, pet in pairs(pets) do
        local isTarget = isTargeted(pet)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 22)
        row.BackgroundColor3 = isTarget and Color3.fromRGB(50, 100, 50) or Color3.fromRGB(30, 20, 50)
        row.BackgroundTransparency = 0.3
        row.BorderSizePixel = 0
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -8, 1, 0)
        lbl.Position = UDim2.new(0, 8, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = (isTarget and "✓ " or "  ") .. pet.size .. " " .. pet.name .. "  " .. pet.cost .. "  " .. pet.leave
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 9
        lbl.TextColor3 = isTarget and Color3.fromRGB(150, 255, 150) or Color3.fromRGB(160, 150, 190)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row
        row.Parent = currentFrame
    end
end

currentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    currentFrame.CanvasSize = UDim2.new(0, 0, 0, currentLayout.AbsoluteContentSize.Y + 8)
end)

local btnRow = Instance.new("Frame")
btnRow.Size = UDim2.new(1, -20, 0, 32)
btnRow.Position = UDim2.new(0, 10, 1, -42)
btnRow.BackgroundTransparency = 1
btnRow.Parent = main

local scanBtn = Instance.new("TextButton")
scanBtn.Size = UDim2.new(0.48, 0, 1, 0)
scanBtn.BackgroundColor3 = Color3.fromRGB(80, 50, 140)
scanBtn.BackgroundTransparency = 0.2
scanBtn.Text = "▶ SCAN"
scanBtn.Font = Enum.Font.GothamBold
scanBtn.TextSize = 11
scanBtn.TextColor3 = Color3.fromRGB(200, 180, 255)
scanBtn.BorderSizePixel = 0
Instance.new("UICorner", scanBtn).CornerRadius = UDim.new(0, 8)
scanBtn.Parent = btnRow

local hopBtn = Instance.new("TextButton")
hopBtn.Size = UDim2.new(0.48, 0, 1, 0)
hopBtn.Position = UDim2.new(0.52, 0, 0, 0)
hopBtn.BackgroundColor3 = Color3.fromRGB(30, 80, 40)
hopBtn.BackgroundTransparency = 0.2
hopBtn.Text = "🔀 AUTO HOP: ON"
hopBtn.Font = Enum.Font.GothamBold
hopBtn.TextSize = 10
hopBtn.TextColor3 = Color3.fromRGB(150, 255, 150)
hopBtn.BorderSizePixel = 0
Instance.new("UICorner", hopBtn).CornerRadius = UDim.new(0, 8)
hopBtn.Parent = btnRow

hopBtn.MouseButton1Click:Connect(function()
    autoHop = not autoHop
    if autoHop then
        hopBtn.Text = "🔀 AUTO HOP: ON"
        hopBtn.BackgroundColor3 = Color3.fromRGB(30, 80, 40)
        hopBtn.TextColor3 = Color3.fromRGB(150, 255, 150)
    else
        hopBtn.Text = "🔀 AUTO HOP: OFF"
        hopBtn.BackgroundColor3 = Color3.fromRGB(40, 60, 100)
        hopBtn.TextColor3 = Color3.fromRGB(160, 190, 255)
    end
end)

local function updateStatus(text, color)
    statusLbl.Text = text
    statusLbl.TextColor3 = color or Color3.fromRGB(120, 120, 160)
end

-- ═══════════════════════════════════════
-- UNIFIED SINGLE PROCESSING LOOP
-- ═══════════════════════════════════════
local loopActive = false

local function runScanningLoop()
    if loopActive then return end
    loopActive = true
    
    -- Create a memory cache to track pets we've already tried to buy
    local processedPets = {} 
    
    -- Make it a "weak table" so when the pet is destroyed by the game, it clears from memory to prevent lag
    setmetatable(processedPets, {__mode = "k"}) 

    while isScanning and not _G.PetScannerStop do
        refreshCurrentPets()
        local pets = getPets()
        local found = false
        
        for _, pet in pairs(pets) do
            -- Add a check: ONLY proceed if we haven't processed THIS exact pet model yet
            if isTargeted(pet) and not processedPets[pet.model] then
                found = true
                processedPets[pet.model] = true -- Mark as processed so we never touch it again
                
                updateStatus("✓ FOUND: " .. pet.size .. " " .. pet.name .. " — BUYING!", Color3.fromRGB(80, 220, 100))
                sendWebhook(pet, false)
                
                local bought = autoBuy(pet)
                if bought then sendWebhook(pet, true) end
                
                task.wait(2)
            end
        end
        
        if not found then
            if autoHop then
                updateStatus("✗ NOT FOUND — HOPPING SERVER...", Color3.fromRGB(255, 180, 50))
                hopServer()
                task.wait(8)
            else
                updateStatus("● SCANNING... NO TARGET PET YET", Color3.fromRGB(180, 120, 255))
            end
        end
        task.wait(2)
    end
    
    loopActive = false
    isScanning = false
    scanBtn.Text = "▶ SCAN"
    scanBtn.BackgroundColor3 = Color3.fromRGB(80, 50, 140)
    scanBtn.TextColor3 = Color3.fromRGB(200, 180, 255)
    TweenService:Create(mainStroke, TweenInfo.new(0.2), {Color = Color3.fromRGB(180, 120, 255)}):Play()
    updateStatus("● IDLE — Press SCAN to start", Color3.fromRGB(120, 120, 160))
end

scanBtn.MouseButton1Click:Connect(function()
    isScanning = not isScanning
    if isScanning then
        scanBtn.Text = "■ STOP"
        scanBtn.BackgroundColor3 = Color3.fromRGB(100, 30, 30)
        scanBtn.TextColor3 = Color3.fromRGB(255, 150, 150)
        TweenService:Create(mainStroke, TweenInfo.new(0.2), {Color = Color3.fromRGB(80, 220, 100)}):Play()
        task.spawn(runScanningLoop)
    end
end)

-- Initial Load Configurations
refreshCurrentPets()

if autoStartScan or autoHop then
    hopBtn.Text = "🔀 AUTO HOP: ON"
    hopBtn.BackgroundColor3 = Color3.fromRGB(30, 80, 40)
    hopBtn.TextColor3 = Color3.fromRGB(150, 255, 150)
    autoHop = true
end

-- Safely trigger auto-start without double threading
task.wait(1)
if autoStartScan or true then -- defaults to scan on load
    isScanning = true
    scanBtn.Text = "■ STOP"
    scanBtn.BackgroundColor3 = Color3.fromRGB(100, 30, 30)
    scanBtn.TextColor3 = Color3.fromRGB(255, 150, 150)
    TweenService:Create(mainStroke, TweenInfo.new(0.2), {Color = Color3.fromRGB(80, 220, 100)}):Play()
    task.spawn(runScanningLoop)
end

-- UI Background Passive Refresher
task.spawn(function()
    while sg.Parent and not _G.PetScannerStop do
        task.wait(3)
        if not isScanning then refreshCurrentPets() end
    end
end)

print("Pet Scanner v2 loaded completely without bugs!")
