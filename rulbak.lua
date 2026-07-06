repeat task.wait() until game:IsLoaded()

-- =========================================================================
-- CONFIGURATION
-- =========================================================================
local WEBHOOK_URL = "https://discord.com/api/webhooks/1523747394146275451/BHBKhJYnFgrgO7MQAOFGebEuR7tY7D-7008RlXPOGtnEKhvfzqeoOEzCHxeGhMuKd0QW" -- Put your webhook URL here
local targetPlayerName = "Leesoo3151" -- Username of the AFK
local TARGET_KG = 60          -- Carrot weight threshold in KG
local SEED_NAME = "Mega"    -- Change to whatever seed u want
local SPRINKLER_NAME = "Super Sprinkler"
local SPRINKLER_RADIUS = 55   -- studs || DONT CHANGE CUZ THIS IS CONSTANT ||
local PLANT_SPACING = 1.5     -- studs between planted seeds (1-2 studs)
local PLANT_DELAY = 0.03      -- seconds between each PlantSeed fire

local FLAG_FILE = "rollback_success.flag" -- Written to disk when target is found

-- =========================================================================
-- SERVICES & MODULES
-- =========================================================================
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local lp = Players.LocalPlayer

local Networking = require(game:GetService("ReplicatedStorage").SharedModules.Networking)
local GardenSyncController = require(lp.PlayerScripts.Controllers.GardenSyncController)
local PlayerStateClient = require(game:GetService("ReplicatedStorage").ClientModules.PlayerStateClient)

-- Ensure character is loaded
local character = lp.Character or lp.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

-- =========================================================================
-- WEBHOOK FUNCTION (Handles Found & Not Found)
-- =========================================================================
local function sendDiscordWebhook(isFound, plantName, weight)
    if WEBHOOK_URL == "" or WEBHOOK_URL == "YOUR_WEBHOOK_URL_HERE" then return end

    local embed = {}

    if isFound then
        embed = {
            ["title"] = "✅ Target Plant Found!",
            ["description"] = "A plant has successfully reached the target weight threshold.",
            ["color"] = 65280, -- Hex #00FF00 (Green)
            ["fields"] = {
                { ["name"] = "🧑 Player", ["value"] = tostring(lp.Name), ["inline"] = true },
                { ["name"] = "🌿 Plant Type", ["value"] = tostring(plantName), ["inline"] = true },
                { ["name"] = "⚖️ Weight", ["value"] = string.format("%.4f KG", weight), ["inline"] = true }
            }
        }
    else
        embed = {
            ["title"] = "❌ Target Not Found (Rolling Back)",
            ["description"] = "No plant reached the threshold. Rejoining server to rollback.",
            ["color"] = 16711680, -- Hex #FF0000 (Red)
            ["fields"] = {
                { ["name"] = "🧑 Player", ["value"] = tostring(lp.Name), ["inline"] = true },
                { ["name"] = "🌿 Best Plant", ["value"] = tostring(plantName), ["inline"] = true },
                { ["name"] = "⚖️ Max Weight Reached", ["value"] = string.format("%.4f KG", weight), ["inline"] = true }
            }
        }
    end

    embed["type"] = "rich"
    embed["footer"] = { ["text"] = "Rollback Auto-Farmer" }
    embed["timestamp"] = DateTime.now():ToIsoDate()

    local payload = {
        ["embeds"] = {embed}
    }

    -- Support for various executors
    local requestFunc = request or http_request or (http and http.request) or (syn and syn.request)
    
    if requestFunc then
        task.spawn(function()
            pcall(function()
                requestFunc({
                    Url = WEBHOOK_URL,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = HttpService:JSONEncode(payload)
                })
            end)
        end)
    else
        warn("[Webhook] No compatible HTTP request function found for your executor.")
    end
end

-- =========================================================================
-- CHECK SUCCESS FLAG (persists across rejoins via disk)
-- =========================================================================
local function flagExists()
    local ok, result = pcall(readfile, FLAG_FILE)
    return ok and result == "SUCCESS"
end

local function writeFlag()
    pcall(writefile, FLAG_FILE, "SUCCESS")
end

local function clearFlag()
    pcall(writefile, FLAG_FILE, "")
end

if flagExists() then
    print("[Rollback Panel] SUCCESS flag detected from previous session.")
    print("[Rollback Panel] Target was already found. Suspending all tasks.")
    clearFlag() -- Clear it so future runs behave normally if re-executed manually
    -- Suspend indefinitely — do nothing
    while true do task.wait(999) end
end

-- =========================================================================
-- Ensure game version is 185
-- =========================================================================
local ver = game.PlaceVersion
if ver and ver ~= 185 then
    print("Shutting down in 3")
    task.wait(3)
    game:Shutdown()
end

-- =========================================================================
-- SKIP LOADING SCREEN
-- =========================================================================
local function performClick()
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
end

local clickScreen = task.spawn(function()
    while true do
        performClick()
        task.wait(0.25)
    end
end)

local function waitForLoadingScreen()
    while not lp:GetAttribute("LoadingScreenDone") do
        task.wait(0.25)
    end
    task.cancel(clickScreen)
    print("[Rollback Panel] Loading screen skipped!")
end

waitForLoadingScreen()

-- =========================================================================
-- TARGET PLAYER CHECK
-- =========================================================================
if not Players:FindFirstChild(targetPlayerName) then
    print("[PLAYER CHECK] Waiting for player '" .. targetPlayerName .. "' to join the server.")
    while not Players:FindFirstChild(targetPlayerName) do
        task.wait(1)
    end
    print("[PLAYER CHECK] Proceeding...")
end

if tostring(Players.LocalPlayer) == targetPlayerName then
    print("[PLAYER CHECK] Player is AFK-Player. Not Executing Rollback.")
    return
end

-- =========================================================================
-- 1. START ROLLBACK PAYLOAD
-- =========================================================================
print("[Rollback Panel] Initiating Rollback Start payload...")
task.spawn(function()
    local result = Networking.SignTool.SetSignImage:Fire("\58\247")
    print("[Rollback Panel] Start Payload Result: ", HttpService:JSONEncode(result))
end)

task.wait(2)

-- =========================================================================
-- PREPARATION: Find player plot dynamically (works for any plot)
-- =========================================================================
local plot = nil
for _, p in ipairs(workspace.Gardens:GetChildren()) do
    if p:GetAttribute("OwnerUserId") == lp.UserId then
        plot = p
        break
    end
end

if not plot then
    warn("[Script] Could not find local plot! Aborting.")
    return
end

local plotId = tonumber(string.match(plot.Name, "%d+"))
if not plotId then
    warn("[Script] Could not parse Plot ID from: " .. tostring(plot.Name))
    return
end
print("[Script] Found plot: " .. plot.Name .. " (ID: " .. plotId .. ")")

local visual = plot:FindFirstChild("Visual")
if not visual then
    warn("[Script] No Visual folder found on plot!")
    return
end

local plantAreaCol1 = visual:FindFirstChild("PlantAreaColumn1")
if not plantAreaCol1 then
    warn("[Script] PlantAreaColumn1 not found in Visual!")
    return
end

local sprinklerPos = plantAreaCol1.Position
print("[Script] Sprinkler target position: " .. tostring(sprinklerPos))

-- =========================================================================
-- FIND TOOLS (Backpack or already equipped)
-- =========================================================================
local superSprinklerTool = lp.Backpack:FindFirstChild(SPRINKLER_NAME) or character:FindFirstChild(SPRINKLER_NAME)
local seedTool = lp.Backpack:FindFirstChild(SEED_NAME) or character:FindFirstChild(SEED_NAME)

if not superSprinklerTool then
    warn("[Script] '" .. SPRINKLER_NAME .. "' not found in Backpack or Character!")
    return
end

if not seedTool then
    warn("[Script] '" .. SEED_NAME .. "' tool not found in Backpack or Character!")
    return
end

-- =========================================================================
-- 2. EQUIP & PLACE SUPER SPRINKLER
-- =========================================================================
print("[Script] Equipping Super Sprinkler...")
superSprinklerTool.Parent = character
task.wait(0.2)

print("[Script] Placing Super Sprinkler at center of PlantAreaColumn1...")
Networking.Place.PlaceSprinkler:Fire(sprinklerPos, SPRINKLER_NAME, superSprinklerTool, plotId)
task.wait(0.5)

-- =========================================================================
-- 3. UNEQUIP SPRINKLER, EQUIP SEED TOOL, PLANT IN CIRCULAR SPIRAL
-- =========================================================================
print("[Script] Unequipping Super Sprinkler...")
humanoid:UnequipTools()
task.wait(0.3)

print("[Script] Equipping " .. SEED_NAME .. " tool...")
seedTool.Parent = character
task.wait(0.2)

local points = {}
local r = PLANT_SPACING
local theta = 0

while r < SPRINKLER_RADIUS do
    local dx = r * math.cos(theta)
    local dz = r * math.sin(theta)
    table.insert(points, sprinklerPos + Vector3.new(dx, 0, dz))
    theta = theta + (PLANT_SPACING / r)
    r = r + (PLANT_SPACING * (PLANT_SPACING / (2 * math.pi * r)))
end

print("[Script] Generated " .. #points .. " planting points in spiral.")

local replica = PlayerStateClient:GetLocalReplica()
local pointIndex = 1

local function getSeedCount()
    local seeds = replica.Data.Inventory.Seeds
    return (seeds and seeds[SEED_NAME]) or 0
end

print("[Script] Starting circular seed planting sequence (" .. getSeedCount() .. " seeds)...")
while getSeedCount() > 0 do
    if not points[pointIndex] then
        pointIndex = 1
    end
    Networking.Plant.PlantSeed:Fire(points[pointIndex], SEED_NAME, seedTool)
    pointIndex = pointIndex + 1
    task.wait(PLANT_DELAY)
end
print("[Script] Finished planting all " .. SEED_NAME .. " seeds.")

task.wait(5)

-- =========================================================================
-- 4. WEIGHT VERIFICATION & REJOIN SEQUENCE
-- =========================================================================
local plantsFolder = plot:FindFirstChild("Plants")
local foundTarget = false
local highestWeight = 0
local highestPlantName = "None"

if plantsFolder then
    for _, plantModel in ipairs(plantsFolder:GetChildren()) do
        local userId = plantModel:GetAttribute("UserId")
        local plantId = plantModel:GetAttribute("PlantId")

        if userId and plantId then
            local plantData = GardenSyncController:GetPlant(userId, plantId)
            if plantData then
                local weight = plantData.Weight or 0

                -- Track the highest weight found during this run
                if plantData.PlantName == "Carrot" and weight > highestWeight then
                    highestWeight = weight
                    highestPlantName = plantData.PlantName
                end

                print(string.format("Plant: %s | Weight: %.2f kg", plantData.PlantName, weight))
                if plantData.PlantName == "Carrot" and weight >= TARGET_KG then
                    foundTarget = true
                    print(string.format("[Script] Found target plant over %.0fKG: %.4f KG", TARGET_KG, weight))
                    break
                end
            end
        end
    end
end

if foundTarget then
    print("[Rollback Panel] Target found. Initiating Discord Notification...")
    pcall(function() Networking.SignTool.SetSignImage:Fire("") end)
    pcall(function() Networking.SignTool.SetSignImage:Fire(" ") end)
    pcall(function() Networking.SignTool.SetSignImage:Fire(nil) end)
    print("[Rollback Panel] Stop sequence fired cleanly.")

    -- 🟢 FIRE SUCCESS WEBHOOK 🟢
    sendDiscordWebhook(true, highestPlantName, highestWeight)

    -- Write the success flag to disk BEFORE rejoining
    writeFlag()
    print("[Rollback Panel] Success flag written. Next run will suspend automatically.")
    task.wait(1)
else
    print("[Rollback Panel] No qualifying plant found. Rejoining to trigger rollback...")
    sendDiscordWebhook(false, highestPlantName, highestWeight)
end

task.wait(4)
TeleportService:Teleport(game.PlaceId, lp)
