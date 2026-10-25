-- ================================================================= --
--                    RIDE A DINO - ADVANCED HUB                      --
-- ================================================================= --

-- A second run replaces this session instead of stacking loops and UI.
local environment = type(getgenv) == "function" and getgenv() or _G
local sessionKey = "RideADinoHubSession"
local previous = environment[sessionKey]
if type(previous) == "table" and type(previous.Stop) == "function" then pcall(previous.Stop) end
local session = {Running = true, Threads = {}}
environment[sessionKey] = session
local Rayfield
local cleanup = function() end
function session.Stop()
    if not session.Running then return end
    session.Running = false
    local current = coroutine.running()
    for thread in pairs(session.Threads) do
        if thread ~= current then pcall(task.cancel, thread) end
        session.Threads[thread] = nil
    end
    local ok, err = pcall(cleanup)
    if not ok then warn("Ride a Dino cleanup failed: " .. tostring(err)) end
    if Rayfield then pcall(function() Rayfield:Destroy() end) end
    if environment[sessionKey] == session then environment[sessionKey] = nil end
end
local function startWorker(callback)
    if not session.Running then return nil end
    local thread
    thread = coroutine.create(function()
        local ok, err = pcall(callback)
        session.Threads[thread] = nil
        if not ok then warn("Ride a Dino worker stopped: " .. tostring(err)) end
    end)
    session.Threads[thread] = true
    task.spawn(thread)
    return thread
end
local function cancelWorker(thread)
    if thread then
        pcall(task.cancel, thread)
        session.Threads[thread] = nil
    end
end
local loaded, result = pcall(function()
    return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
end)
if not loaded or type(result) ~= "table" then
    session.Stop()
    warn("Ride a Dino UI failed to load: " .. tostring(result))
    return
end
Rayfield = result

local initialized, initializationError = xpcall(function()
local Window = Rayfield:CreateWindow({
   Name = "Ride a Dino Hub | Full Suite",
   LoadingTitle = "Ride a Dino Script",
   LoadingSubtitle = "Auto Tame - ESP - Infinite Stamina",
   ConfigurationSaving = {
      Enabled = false, -- Never restore farming toggles automatically.
      FolderName = "RideADinoHub",
      FileName = "Config"
   },
   Discord = {
      Enabled = false
   },
   KeySystem = false
})

-- Services & References
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Game Logic Modules & Remotes
-- Bound both hierarchy lookup and module initialization time.
local function loadModule(path)
    local result
    local finished = false
    local worker = startWorker(function()
        local ok, value = pcall(function()
            local node = ReplicatedStorage
            for _, name in ipairs(path) do
                node = node:WaitForChild(name, 2)
                if not node then return nil end
            end
            if not node:IsA("ModuleScript") then return nil end
            return require(node)
        end)
        if ok and type(value) == "table" then result = value end
        finished = true
    end)
    local deadline = os.clock() + 8
    while not finished and session.Running and os.clock() < deadline do task.wait(0.1) end
    if not finished then cancelWorker(worker) end
    if not result then warn("Ride a Dino: unavailable module " .. table.concat(path, "/")) end
    return result
end
-- Do not require game modules while the hub loads. Require only when a
-- dependent feature is explicitly enabled, then preserve the original values.
local RideConfig, Net
local originalGodMode, originalLowGrip
local function ensureRideConfig()
    if RideConfig then return true end
    RideConfig = loadModule({"RideADino", "Config", "Ride"})
    if not RideConfig then return false end
    if type(RideConfig.Crash) == "table" then originalGodMode = RideConfig.Crash.godMode end
    if type(RideConfig.Tame) == "table" then originalLowGrip = RideConfig.Tame.lowGripAngerSec end
    return true
end
local function ensureNet()
    if not Net then Net = loadModule({"RideADino", "Shared", "Net"}) end
    return Net and type(Net.toServer) == "function"
end
local function setConfig(section, key, value)
    if RideConfig and type(RideConfig[section]) == "table" then
        local ok, err = pcall(function() RideConfig[section][key] = value end)
        if not ok then warn("Ride config is read-only: " .. tostring(err)) end
    end
end

-- Feature Toggles & Variables
local AutoTameEnabled = false
local InfiniteStaminaEnabled = false
local AutoTrainEnabled = false
local DinoESPEnabled = false
local OnlySecretColossalEnabled = false
local ShowDistanceEnabled = true
local AutoClaimGifts = false
local AutoClaimMeteors = false
local WalkSpeedValue = 16
local ESPStorage = {}
local MAX_ESP = 20
local originalSpeeds = {}

-- Known Secret Dino Species & Names
local SecretDinoNames = {
    ["alien skeleton boss"] = true,
    ["barosaurus skeleton fossil"] = true,
    ["barosaurus fossil"] = true,
    ["el maja"] = true,
    ["king gorilla"] = true,
    ["king yeti"] = true,
    ["magmasaur"] = true,
    ["qianzhousaurus_rig"] = true,
    ["qianzhousaurus"] = true,
    ["skeletal rex"] = true,
    ["drex"] = true,
    ["lunar dragon"] = true,
    ["warpcarnotaurus"] = true
}

-- Check if Model is a Secret Dino
local function IsSecretDino(model)
    if not model then return false end
    local name = string.lower(model.Name)
    if string.find(name, "secret") then return true end

    local specId = model:GetAttribute("SpecId") or model:GetAttribute("AuthoredSpecies") or model:GetAttribute("PoolKey")
    if specId and SecretDinoNames[string.lower(tostring(specId))] then
        return true
    end

    for secretName, _ in pairs(SecretDinoNames) do
        if string.find(name, secretName) then
            return true
        end
    end

    local rarity = model:GetAttribute("Rarity") or model:GetAttribute("Mutation")
    if rarity and (string.lower(tostring(rarity)) == "secret" or string.lower(tostring(rarity)) == "eternal") then
        return true
    end

    return false
end

-- Check if Model is a Colossal Dino
local function IsColossalDino(model)
    if not model then return false end
    local name = string.lower(model.Name)
    if string.find(name, "colossal") then return true end

    local size = model:GetAttribute("Size")
    if size and string.lower(tostring(size)) == "colossal" then
        return true
    end

    return false
end

-- ================================================================= --
--                         1. AUTO TAME & GOD MODE                    --
-- ================================================================= --

local TameTab = Window:CreateTab("Auto Tame & Grip", 0)

TameTab:CreateToggle({
   Name = "Instant / Auto Tame (God Mode)",
   CurrentValue = false,
   Flag = "AutoTameGodMode",
   Callback = function(Value)
      if Value and not ensureRideConfig() then return end
      AutoTameEnabled = Value
      if RideConfig and RideConfig.Crash then
          setConfig("Crash", "godMode", AutoTameEnabled or InfiniteStaminaEnabled or originalGodMode)
      end
      if Value then
          Rayfield:Notify({
             Title = "Auto Tame Enabled",
             Content = "Dinosaurs will no longer buck you off & taming fills automatically!",
             Duration = 4
          })
      end
   end,
})

TameTab:CreateToggle({
   Name = "Infinite Stamina & Infinite Grip",
   CurrentValue = false,
   Flag = "InfiniteStamina",
   Callback = function(Value)
      if Value and not ensureRideConfig() then return end
      InfiniteStaminaEnabled = Value
      if RideConfig and RideConfig.Crash then
          setConfig("Crash", "godMode", AutoTameEnabled or InfiniteStaminaEnabled or originalGodMode)
      end
      if RideConfig and RideConfig.Tame then
          setConfig("Tame", "lowGripAngerSec", Value and 999999 or originalLowGrip)
      end
   end,
})

TameTab:CreateToggle({
   Name = "Auto Train Grip (Machine Farm)",
   CurrentValue = false,
   Flag = "AutoTrainGrip",
   Callback = function(Value)
      if Value and not ensureNet() then return end
      AutoTrainEnabled = Value
   end,
})

-- Auto Train Loop
startWorker(function()
    while session.Running do
        task.wait(1)
        if not session.Running then break end
        if AutoTrainEnabled then
            pcall(function()
                if Net and type(Net.toServer) == "function" then
                    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if root then Net.toServer("MachineMount", {at = root.CFrame}) end
                end
            end)
        end
    end
end)

-- ================================================================= --
--                             2. DINO ESP                            --
-- ================================================================= --

local ESPTab = Window:CreateTab("Dino ESP", 0)

local function ClearESP()
    for model, data in pairs(ESPStorage) do
        if data.Gui then data.Gui:Destroy() end
        if data.Highlight then data.Highlight:Destroy() end
    end
    ESPStorage = {}
end

local function ApplyESP(model)
    if not model or not model:IsA("Model") then return end

    local isSecret = IsSecretDino(model)
    local isColossal = IsColossalDino(model)

    -- Filter option: if user enabled "Only Secret / Colossal", filter out normal dinos
    if OnlySecretColossalEnabled and not (isSecret or isColossal) then
        if ESPStorage[model] then
            if ESPStorage[model].Gui then ESPStorage[model].Gui:Destroy() end
            if ESPStorage[model].Highlight then ESPStorage[model].Highlight:Destroy() end
            ESPStorage[model] = nil
        end
        return
    end

    local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not root then return end

    -- Determine Text Label Prefix & Highlight Color
    local tag = ""
    local textColor = Color3.fromRGB(255, 255, 255)
    local fillColor = Color3.fromRGB(0, 255, 150)

    if isSecret and isColossal then
        tag = "[SECRET COLOSSAL] "
        textColor = Color3.fromRGB(255, 215, 0)
        fillColor = Color3.fromRGB(255, 100, 0)
    elseif isSecret then
        tag = "[SECRET] "
        textColor = Color3.fromRGB(255, 215, 0)
        fillColor = Color3.fromRGB(255, 50, 80)
    elseif isColossal then
        tag = "[COLOSSAL] "
        textColor = Color3.fromRGB(0, 255, 255)
        fillColor = Color3.fromRGB(180, 0, 255)
    end

    local displayName = tag .. model.Name

    if ShowDistanceEnabled and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local dist = math.floor((root.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude)
        displayName = displayName .. " [" .. tostring(dist) .. "m]"
    end

    -- Update existing ESP label if present
    if ESPStorage[model] then
        if ESPStorage[model].TextLabel then
            ESPStorage[model].TextLabel.Text = displayName
        end
        ESPStorage[model].TextLabel.TextColor3 = textColor
        ESPStorage[model].Highlight.FillColor = fillColor
        ESPStorage[model].Gui.Adornee = root
        return
    end

    local bgui = Instance.new("BillboardGui")
    bgui.Name = "DinoESP"
    bgui.Adornee = root
    bgui.Size = UDim2.new(0, 250, 0, 50)
    bgui.StudsOffset = Vector3.new(0, 4, 0)
    bgui.AlwaysOnTop = true

    local txt = Instance.new("TextLabel")
    txt.Size = UDim2.new(1, 0, 1, 0)
    txt.BackgroundTransparency = 1
    txt.TextColor3 = textColor
    txt.TextStrokeTransparency = 0
    txt.TextSize = 14
    txt.Font = Enum.Font.SourceSansBold
    txt.Text = displayName
    txt.Parent = bgui

    local highlight = Instance.new("Highlight")
    highlight.Name = "DinoHighlight"
    highlight.Adornee = model
    highlight.FillColor = fillColor
    highlight.FillTransparency = 0.5
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.Parent = model

    bgui.Parent = model
    ESPStorage[model] = {Gui = bgui, Highlight = highlight, TextLabel = txt}
end

ESPTab:CreateToggle({
   Name = "Enable Dino ESP",
   CurrentValue = false,
   Flag = "DinoESP",
   Callback = function(Value)
      DinoESPEnabled = Value
      if not Value then
          ClearESP()
      end
   end,
})

ESPTab:CreateToggle({
   Name = "Only Show Secret & Colossal Dinos",
   CurrentValue = false,
   Flag = "OnlySecretColossal",
   Callback = function(Value)
      OnlySecretColossalEnabled = Value
      ClearESP()
   end,
})

ESPTab:CreateToggle({
   Name = "Show Distance",
   CurrentValue = true,
   Flag = "ShowDistance",
   Callback = function(Value)
      ShowDistanceEnabled = Value
   end,
})

-- ESP Update Loop
startWorker(function()
    while session.Running do
        task.wait(1)
        if not session.Running then break end
        if DinoESPEnabled then
            local herd = Workspace:FindFirstChild("StampedeHerd")
            if herd then
                local activeModels = {}
                local count = 0
                for _, dino in ipairs(herd:GetChildren()) do
                    if dino:IsA("Model") and count < MAX_ESP then
                        if not OnlySecretColossalEnabled or IsSecretDino(dino) or IsColossalDino(dino) then
                            count = count + 1
                            activeModels[dino] = true
                            ApplyESP(dino)
                        end
                    end
                end
                -- Clean up despawned dinos
                for model, data in pairs(ESPStorage) do
                    if not activeModels[model] or not model:IsDescendantOf(Workspace) then
                        if data.Gui then data.Gui:Destroy() end
                        if data.Highlight then data.Highlight:Destroy() end
                        ESPStorage[model] = nil
                    end
                end
            else
                ClearESP()
            end
        else
            ClearESP()
        end
    end
end)

-- ================================================================= --
--                         3. AUTO REWARDS                            --
-- ================================================================= --

local FarmTab = Window:CreateTab("Auto Claims", 0)

FarmTab:CreateToggle({
   Name = "Auto Claim Daily Gifts & Offline Rewards",
   CurrentValue = false,
   Flag = "AutoClaimGifts",
   Callback = function(Value)
      if Value and not ensureNet() then return end
      AutoClaimGifts = Value
   end,
})

FarmTab:CreateToggle({
   Name = "Auto Claim Meteor Shards",
   CurrentValue = false,
   Flag = "AutoMeteors",
   Callback = function(Value)
      if Value and not ensureNet() then return end
      AutoClaimMeteors = Value
   end,
})

startWorker(function()
    while session.Running do
        task.wait(10)
        if not session.Running then break end
        if AutoClaimGifts and Net and type(Net.toServer) == "function" then
            pcall(function()
                Net.toServer("GiftClaim", {joined = true})
                Net.toServer("OfflineClaim", {})
            end)
        end
        if AutoClaimMeteors and Net and type(Net.toServer) == "function" then
            pcall(function()
                Net.toServer("MeteorShard", {key = "all"})
            end)
        end
    end
end)

-- ================================================================= --
--                           4. TELEPORTS                             --
-- ================================================================= --

local TeleportTab = Window:CreateTab("Teleports", 0)

local function TeleportTo(cframe)
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char.HumanoidRootPart.CFrame = cframe
    end
end

TeleportTab:CreateButton({
   Name = "Safe Zone / Spawn",
   Callback = function()
       local pad = Workspace:FindFirstChild("SafeZonePad") or Workspace:FindFirstChild("SpawnLocation")
       if pad and pad:IsA("BasePart") then TeleportTo(pad.CFrame + Vector3.new(0, 5, 0)) end
   end,
})

TeleportTab:CreateButton({
   Name = "Start Stampede Zone",
   Callback = function()
       local pad = Workspace:FindFirstChild("StartZonePad")
       if pad and pad:IsA("BasePart") then TeleportTo(pad.CFrame + Vector3.new(0, 5, 0)) end
   end,
})

TeleportTab:CreateButton({
   Name = "Aura Shop",
   Callback = function()
       local shop = Workspace:FindFirstChild("AuraShop")
       if shop then TeleportTo(shop:GetPivot() + Vector3.new(0, 5, 0)) end
   end,
})

TeleportTab:CreateButton({
   Name = "Sell Dino Shop",
   Callback = function()
       local shop = Workspace:FindFirstChild("SellDinoShop")
       if shop then TeleportTo(shop:GetPivot() + Vector3.new(0, 5, 0)) end
   end,
})

TeleportTab:CreateButton({
   Name = "Fuse Machine",
   Callback = function()
       local fuse = Workspace:FindFirstChild("FuseMachine")
       if fuse then TeleportTo(fuse:GetPivot() + Vector3.new(0, 5, 0)) end
   end,
})

-- ================================================================= --
--                          5. PLAYER / MISC                          --
-- ================================================================= --

local PlayerTab = Window:CreateTab("Player & Misc", 0)

PlayerTab:CreateSlider({
   Name = "WalkSpeed",
   Range = {16, 250},
   Increment = 5,
   Suffix = "Speed",
   CurrentValue = 16,
   Flag = "WalkSpeedSlider",
   Callback = function(Value)
      WalkSpeedValue = Value
      if LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
          local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
          if originalSpeeds[humanoid] == nil then originalSpeeds[humanoid] = humanoid.WalkSpeed end
          humanoid.WalkSpeed = Value
      end
   end,
})

PlayerTab:CreateButton({
   Name = "Fullbright (Remove Fog/Darkness)",
   Callback = function()
       local Lighting = game:GetService("Lighting")
       Lighting.Brightness = 3
       Lighting.ClockTime = 14
       Lighting.FogEnd = 100000
       Lighting.GlobalShadows = false
   end,
})

-- Local preview only: inventory, taming and ownership remain server-controlled.
local SpawnerTab = Window:CreateTab("Dragon Spawner", 0)
local spawnedDragon
local idleTrack
local spawning = false
local function removeDragon()
    if idleTrack then
        pcall(function() idleTrack:Stop(); idleTrack:Destroy() end)
        idleTrack = nil
    end
    if spawnedDragon then spawnedDragon:Destroy(); spawnedDragon = nil end
end
local function spawnDragon()
    if spawning or not session.Running then return end
    spawning = true
    local clone
    local ok, err = pcall(function()
        local character = LocalPlayer.Character
        local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
        if not playerRoot or not playerRoot:IsA("BasePart") then
            error("Wait for your character to spawn.", 0)
        end
        -- Search only the documented model pool. Avoid allocating a list of
        -- every replicated object, which can stall large game clients.
        local pool = ReplicatedStorage:FindFirstChild("RideADinoDinos")
        if not pool then error("RideADinoDinos model pool is unavailable.", 0) end
        local function boundedSearch(root, targetName, limit)
            local stack = {root}
            local visited = 0
            while #stack > 0 do
                if not session.Running then error("Session stopped.", 0) end
                local object = table.remove(stack)
                visited = visited + 1
                if visited > limit then error("Model search exceeded the preview safety limit.", 0) end
                if object.Name == targetName and object:IsA("Model") then return object end
                local children = object:GetChildren()
                if #stack + #children + visited > limit then
                    error("Model search exceeded the preview safety limit.", 0)
                end
                for _, child in ipairs(children) do table.insert(stack, child) end
                if visited % 50 == 0 then task.wait() end
            end
        end
        local template = boundedSearch(pool, "Magma Lunar Dragon", 2000)
        if not template then error("Magma Lunar Dragon model is not in the replicated dinosaur pool.", 0) end
        if not template.Archivable then error("The dragon template cannot be cloned.", 0) end
        local stack = {template}
        local visited, parts = 0, 0
        while #stack > 0 do
            if not session.Running then error("Session stopped.", 0) end
            local object = table.remove(stack)
            visited = visited + 1
            if object:IsA("BasePart") then parts = parts + 1 end
            if visited > 1000 or parts > 150 then error("Dragon is too complex for a stable local preview.", 0) end
            local children = object:GetChildren()
            if #stack + #children + visited > 1000 then error("Dragon exceeds the preview safety limit.", 0) end
            for _, child in ipairs(children) do table.insert(stack, child) end
            if visited % 50 == 0 then task.wait() end
        end
        removeDragon() -- Release the previous model before allocating another.
        clone = template:Clone()
        if not clone then error("Could not clone the dragon template.", 0) end
        local root = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
        if not root then error("Dragon template has no body parts.", 0) end
        clone.PrimaryPart = root
        for _, object in ipairs(clone:GetDescendants()) do
            if object:IsA("LuaSourceContainer") then
                object:Destroy() -- Never run scripts copied from the template.
            elseif object:IsA("BasePart") then
                object.CanCollide = false
                object.CanTouch = false
                object.CanQuery = false
                object.Anchored = true -- Static preview cannot fall or push the player.
            end
        end
        clone.Name = "Magma Lunar Dragon (Local Preview)"
        clone:SetAttribute("SpecId", "Lunar Dragon")
        clone:SetAttribute("id", "Lunar Dragon")
        clone:SetAttribute("Size", "Colossal")
        clone:SetAttribute("Mutation", "Magma")
        clone:SetAttribute("Zone", "Cosmic")
        clone:SetAttribute("Era", "Cosmic")
        clone:SetAttribute("IdleAnimationId", "120891080723954")
        clone:SetAttribute("WalkAnimationId", "114147499473856")
        clone:SetAttribute("RunAnimationId", "125932612384748")
        -- Preserve authored scale: the game's actual Colossal scale was not supplied.
        local extent = clone:GetExtentsSize()
        local distance = math.max(extent.X, extent.Z) / 2 + 12
        clone:PivotTo(playerRoot.CFrame * CFrame.new(0, extent.Y / 2 + 3, -distance))
        removeDragon() -- At most one preview per session.
        spawnedDragon = clone
        clone.Parent = Workspace
        -- Keep the anchored preview static. Loading an Animator on this
        -- cloned, anchored rig adds work without making it tameable.
    end)
    spawning = false
    if not ok then
        if clone then
            if spawnedDragon == clone then removeDragon() else clone:Destroy() end
        end
        if session.Running then
            Rayfield:Notify({Title = "Dragon preview unavailable", Content = tostring(err), Duration = 6})
        end
    end
end
SpawnerTab:CreateButton({
    Name = "Spawn Colossal Magma Lunar Dragon (Local Preview)",
    Callback = function()
        if not spawning then startWorker(spawnDragon) end
    end,
})
SpawnerTab:CreateButton({Name = "Remove Dragon Preview", Callback = removeDragon})

-- Uses the game's permission-checked admin API; never fabricates capture data.
local adminSpawnPending = false
local lastAdminSpawn = -math.huge
local function requestServerDragon()
    if not session.Running or adminSpawnPending then return end
    local now = os.clock()
    if now - lastAdminSpawn < 15 then
        Rayfield:Notify({Title = "Please wait", Content = "Wait 15 seconds between spawn requests.", Duration = 4})
        return
    end
    local adminFolder = ReplicatedStorage:FindFirstChild("RideADinoAdmin")
    local command = adminFolder and adminFolder:FindFirstChild("Command")
    if not command or not command:IsA("RemoteFunction") then
        Rayfield:Notify({Title = "Server spawn unavailable", Content = "The supplied admin RemoteFunction is not available in this game session.", Duration = 6})
        return
    end
    adminSpawnPending = true
    lastAdminSpawn = now
    startWorker(function()
        local finished = false
        local invokeOK, response
        local request = startWorker(function()
            invokeOK, response = pcall(function()
                return command:InvokeServer("spawnStart", {
                    scope = "server",
                    specId = "Lunar Dragon",
                    size = "Colossal",
                    mutation = "Magma",
                })
            end)
            finished = true
        end)
        local deadline = os.clock() + 10
        while session.Running and not finished and os.clock() < deadline do task.wait(0.1) end
        if not finished then cancelWorker(request) end
        adminSpawnPending = false
        if not session.Running then return end
        local message
        if not finished then
            message = "No reply within 10 seconds. The server may still process the request; check the herd before retrying."
        elseif not invokeOK then
            message = "Spawn request failed: " .. tostring(response)
        elseif response == false then
            message = "Server declined the request. Admin permission may be required."
        else
            message = "Server replied. Check the herd for the dragon and tame it normally. A reply does not confirm a spawn."
            if type(response) == "string" then message = "Server reply: " .. response end
        end
        Rayfield:Notify({Title = "Server dragon request", Content = message, Duration = 8})
    end)
end
SpawnerTab:CreateButton({
    Name = "Request Tameable Dragon (Server Admin Required)",
    Callback = requestServerDragon,
})

cleanup = function()
    removeDragon()
    ClearESP()
    setConfig("Crash", "godMode", originalGodMode)
    setConfig("Tame", "lowGripAngerSec", originalLowGrip)
    for humanoid, speed in pairs(originalSpeeds) do
        if humanoid.Parent then humanoid.WalkSpeed = speed end
    end
end
PlayerTab:CreateButton({
    Name = "Unload Hub (Stop All Loops)",
    Callback = session.Stop,
})

Rayfield:Notify({
   Title = "Ride a Dino Script Loaded",
   Content = "Ready. Features stay off until you enable them.",
   Duration = 5
})

end, function(err) return tostring(err) end)
if not initialized then
    session.Stop()
    warn("Ride a Dino initialization failed: " .. initializationError)
end
