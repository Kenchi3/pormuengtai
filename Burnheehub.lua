

-- ========================
-- 🔗 Load UI
-- ========================
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- ========================
-- 🪟 Create Window
-- ========================
local Window = Fluent:CreateWindow({
    Title = "Benten Hub",
    SubTitle = "by Nonny",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

-- ========================
-- 📑 Tabs
-- ========================
local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local Options = Fluent.Options

-- ========================
-- 🧠 Game System
-- ========================
local player = game.Players.LocalPlayer
local Players = game:GetService("Players")
local mouse = player:GetMouse()
local char = player.Character or player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")
local userId = player.UserId

local enemiesFolder = workspace:WaitForChild("Enemies")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local distanceBehind = 6 -- ค่าเริ่มต้น
local lastPos = nil
local stuckTime = 0
local selectedTool = nil
local toolList = {}
local lastHit = 0
local hitDelay = 0.4 -- ปรับได้ (0.2-0.6 กำลังดี)
local respawnTime = 0
local lastPoint = nil
local safeHPPercent = 30
local safeDistance = 50 -- ระยะหนีมอน
local isEscaping = false

local SelectedSkills = {Z=true,X=true,C=true,V=true}
local currentMob, hum, root
-- แก้ค้างตอนตี --
local mouseDown = false

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        mouseDown = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        mouseDown = false
    end
end)
-- blacklist --
local blacklist = {
    ["StarterTrainingDummy"] = true,
    ["TrainingDummy"] = true,
    ["BossDummy"] = true,
    ["DivineDogs"] = true
}
-- หามอนใกล้สุดที่ไม่อยู่ใน blacklist --
local function getEnemy()
    local closest, closestHum, closestRoot
    local shortestDistance = math.huge

    for _, v in pairs(enemiesFolder:GetChildren()) do
        local enemyName = v:GetAttribute("EnemyName")

        -- 🔥 ข้ามตัวที่อยู่ใน blacklist
        if not blacklist[enemyName] and not v:GetAttribute("IsCivilian") then

            local h = v:FindFirstChildOfClass("Humanoid")
            local r = v:FindFirstChild("HumanoidRootPart")

            if h and r and h.Health > 0 then
                local distance = (hrp.Position - r.Position).Magnitude

                if distance < shortestDistance then
                    shortestDistance = distance
                    closest = v
                    closestHum = h
                    closestRoot = r
                end
            end

        end
    end

    return closest, closestHum, closestRoot
end
-- anim lock monster --
local function aimAtTarget(targetRoot)
    if not targetRoot then return end

    local pos, onScreen = Camera:WorldToViewportPoint(targetRoot.Position)

    if onScreen then
        VirtualInputManager:SendMouseMoveEvent(pos.X, pos.Y, game)
    end
end
-- อัปเดตตัวแปรตัวละครเมื่อเกิดใหม่ --
local function updateCharacter()
    char = player.Character or player.CharacterAdded:Wait()
    hrp = char:WaitForChild("HumanoidRootPart")
end

player.CharacterAdded:Connect(function()
    respawnTime = tick() -- ⏱️ จำเวลาเกิด

    task.wait(1.5) -- รอโหลดตัวละคร
    updateCharacter()
end)

updateCharacter()
-- หา Tool ใน Backpack --
local function getTools()
    toolList = {}

    for _, v in pairs(player.Backpack:GetChildren()) do
        if v:IsA("Tool") then
            table.insert(toolList, v.Name)
        end
    end

    return toolList
end

-- ========================
-- 🗺️ Dungeon Positions (แยกตาม PlaceId)
-- ========================
local currentPoint = 1
local lastTP = 0
local tpDelay = 2

local function hasEnemy()
    for _, v in pairs(enemiesFolder:GetChildren()) do
        local enemyName = v:GetAttribute("EnemyName")

        if not blacklist[enemyName] and not v:GetAttribute("IsCivilian") then
            local h = v:FindFirstChildOfClass("Humanoid")
            local r = v:FindFirstChild("HumanoidRootPart")

            if h and r and h.Health > 0 then
                return true
            end
        end
    end
    return false
end

local function dungeonTP()
    local map = workspace:FindFirstChild("Map")
    if not map then return end

    -- 🔥 หา Raid Name
    local raidName = nil
    for _, v in pairs(map:GetChildren()) do
        if v:IsA("Folder") and v:FindFirstChild("World") then
            raidName = v.Name
            break
        end
    end
    if not raidName then return end

    local world = map:FindFirstChild(raidName):FindFirstChild("World")
    if not world then return end

    local phaseZones = world:FindFirstChild("PhaseZones")
    if not phaseZones then return end

    -- 🔁 เก็บ Folder ของ PhaseZone ทั้งหมด (1,2,3…)
    local zones = {}
    for _, zone in pairs(phaseZones:GetChildren()) do
        if zone:IsA("Folder") then
            table.insert(zones, zone)
        end
    end

    -- 🔥 เรียง Phase ตามเลข
    table.sort(zones, function(a, b)
        return tonumber(a.Name) < tonumber(b.Name)
    end)

    if #zones == 0 then return end

    if currentPoint > #zones then
        currentPoint = 1
    end

    local targetZone = zones[currentPoint]

    -- 🚀 วาปไปตำแหน่ง Zone (ใช้ตำแหน่ง folder ต้นแบบ)
    local pos = targetZone.Start and targetZone.Start.Position or targetZone:GetModelCFrame().Position
    hrp.CFrame = CFrame.new(pos)

    -- 💾 จำจุดล่าสุด
    lastPoint = targetZone

    -- ➡️ เตรียม index รอบหน้า
    currentPoint += 1
end
--ฟังก์ชันเช็คเลือด--
local function isLowHP()
    local character = player.Character
    if not character then return false end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    local hpPercent = (humanoid.Health / humanoid.MaxHealth) * 100
    return hpPercent <= safeHPPercent
end
-- ========================
-- 🎯 Select Skill
-- ========================
local SkillDropdown = Tabs.Main:AddDropdown("SkillSelect", {
    Title = "Select Skill",
    Values = {"Z","X","C","V","R"},
    Multi = true,
    Default = {"Z","X","C","V","R"},
})

SkillDropdown:OnChanged(function(Value)
    SelectedSkills = {Z=false,X=false,C=false,V=false,R=false}

    for key, state in pairs(Value) do
        key = tostring(key)

        if SelectedSkills[key] ~= nil then
            SelectedSkills[key] = state
        end
    end
end)

local ToolDropdown = Tabs.Main:AddDropdown("ToolSelect", {
    Title = "Select Tool",
    Values = getTools(),
    Multi = false,
    Default = nil
})

ToolDropdown:OnChanged(function(Value)
    selectedTool = Value
end)

Tabs.Main:AddButton({
    Title = "Refresh Tool",
    Description = "อัปเดตรายชื่อ Tool",
    Callback = function()
        local newTools = getTools()
        ToolDropdown:SetValues(newTools)

        Fluent:Notify({
            Title = "Refreshed",
            Content = "Updated tool list 🔄",
            Duration = 3
        })
    end
})

-- ========================
-- 🔘 Toggles
-- ========================
local AutoFarm = Tabs.Main:AddToggle("AutoFarm", {Title = "Auto Farm Mobs", Default = false})
local AutoSkill = Tabs.Main:AddToggle("AutoSkill", {Title = "Auto Skill", Default = false})
local AutoEquip = Tabs.Main:AddToggle("AutoEquip", {Title = "Auto Equip Tool", Default = false})
local AutoReplay = Tabs.Main:AddToggle("AutoReplay", {Title = "Auto Replay", Default = false})


Options.AutoFarm:SetValue(false)
Options.AutoSkill:SetValue(false)
Options.AutoEquip:SetValue(false)
Options.AutoReplay:SetValue(false)

AutoFarm:OnChanged(function()
    if Options.AutoFarm.Value then
        -- 🔥 รีเป้าทันทีตอนเปิด
        currentMob = nil
        hum = nil
        root = nil

        -- 🎯 หาใหม่ทันที
        currentMob, hum, root = getEnemy()
    end
end)
-- ========================
-- Slider 
-- ========================
local DistanceSlider = Tabs.Main:AddSlider("Distance", {
    Title = "Distance From Enemy",
    Description = "ระยะห่างจากมอน",
    Default = 6,
    Min = 0,
    Max = 15,
    Rounding = 0,
    Callback = function(Value)
        distanceBehind = Value
    end
})
local AttackSpeedSlider = Tabs.Main:AddSlider("AttackSpeed", {
    Title = "Attack Speed",
    Description = "ยิ่งน้อย = ตีไว",
    Default = 0.2,
    Min = 0.1,
    Max = 1,
    Rounding = 2,
    Callback = function(Value)
        hitDelay = Value
    end
})
local SafeMode = Tabs.Main:AddToggle("SafeMode", {
    Title = "Safe Mode (หนีตอนเลือดต่ำ)",
    Default = false
})

local SafeHPSlider = Tabs.Main:AddSlider("SafeHP", {
    Title = "HP ต่ำกว่า (%)",
    Description = "ถ้าต่ำกว่านี้จะหนี",
    Default = 30,
    Min = 5,
    Max = 80,
    Rounding = 0,
    Callback = function(Value)
        safeHPPercent = Value
    end
})
-- ========================
-- 🧲 Auto Farm (Lock หลังมอน)
-- ========================
RunService.Heartbeat:Connect(function()
    if not Options.AutoFarm.Value then return end
    if not hrp then return end

    if not currentMob or not hum or hum.Health <= 0 then
        currentMob, hum, root = getEnemy()
    end

    -- 🧭 ไม่มีมอน → TP เปิดแมพ
    if not hasEnemy() then
        dungeonTP()
        return
    end

    -- 💀 ถ้ามอนตาย → รีทันที
    if hum and hum.Health <= 0 then
        currentMob = nil
        hum = nil
        root = nil
    end
    task.wait(0.1) -- ลดโหลดเครื่อง
    -- 🎯 หาเป้าใหม่
    if not currentMob or not hum or hum.Health <= 0 then
        currentMob, hum, root = getEnemy()
    end

    -- 🧲 วาป + หันหน้า
    if currentMob and root then

    -- 🛡️ SAFE MODE
    if Options.SafeMode.Value and isLowHP() then
        isEscaping = true

        local escapeCF = root.CFrame * CFrame.new(0, 0, safeDistance)
        hrp.CFrame = escapeCF

        return
    else
        isEscaping = false
    end

    -- ❌ ถ้ากำลังหนี ห้ามตี
    if isEscaping then return end

    -- 🔥 ปกติ
    local targetCF = root.CFrame * CFrame.new(0, 0, distanceBehind)
    hrp.CFrame = targetCF
    hrp.CFrame = CFrame.new(hrp.Position, root.Position)

    if hum and hum.Health > 0 then
         aimAtTarget(root)
        if tick() - lastHit >= hitDelay and not mouseDown then
            lastHit = tick()

            VirtualInputManager:SendMouseButtonEvent(0,0,0,true,game,0)
            task.wait()
            VirtualInputManager:SendMouseButtonEvent(0,0,0,false,game,0)
        end
    end
end

end)

-- ========================
-- 🧰 Auto Equip Tool
-- ========================
task.spawn(function()
    while task.wait(0.3) do
        if Options.AutoEquip.Value and Options.AutoFarm.Value and selectedTool and char and hrp then
            
            -- ⛔ กันรีบ equip หลังเกิด
            if tick() - respawnTime < 2 then continue end

            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if not humanoid then continue end

            -- 🔍 เช็ค tool ที่ถืออยู่ตอนนี้
            local equippedTool = char:FindFirstChildOfClass("Tool")

            -- ❌ ไม่มี tool หรือถือไม่ตรง
            if not equippedTool or equippedTool.Name ~= selectedTool then
                
                local tool = player.Backpack:FindFirstChild(selectedTool)

                if tool then
                    humanoid:EquipTool(tool) -- 🔥 equip แบบเนียน
                end
            end
        end
    end
end)
-- ========================
-- 🔁 Auto Replay
-- ========================
task.spawn(function()

    local raidrewards = player.PlayerGui:WaitForChild("RaidRewards")
    local CanvasGroup = raidrewards:WaitForChild("CanvasGroup")
    local raidrewards2 = CanvasGroup:WaitForChild("RaidRewards")
    local Repaly = raidrewards2:WaitForChild("Replay")
    local Container = Repaly:WaitForChild("Container")
    local Button = Container:WaitForChild("Button")

    local GuiService = game:GetService("GuiService")

    while task.wait(0.3) do
        if Options.AutoReplay.Value and CanvasGroup.Visible then
            GuiService.SelectedObject = Button
            GuiService.SelectedObject = Button
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
            task.wait(.001)
            GuiService.SelectedObject = nil
        end
    end
end)



-- ========================
-- ⚔️ Auto Skill
-- ========================
task.spawn(function()
    local order = {"Z","X","C","V","R"}

    while task.wait(0.02) do
        if Options.AutoSkill.Value and Options.AutoFarm.Value then
            if not currentMob or not hum or hum.Health <= 0 then
                continue
            end
            for _, key in ipairs(order) do
                if SelectedSkills[key] then
                    local keyCode = Enum.KeyCode[key]

                    if keyCode then
                        VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
                        task.wait(0.01)
                        VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
                    end
                end
            end
        end
    end
end)

RunService.RenderStepped:Connect(function()
    if Options.AutoFarm.Value and Options.AutoSkill.Value then
        if currentMob and root then
            aimAtTarget(root)
        end
    end
end)

-- ========================
-- ⚙️ Save / UI Manager
-- ========================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})

InterfaceManager:SetFolder("FluentScriptHub")
SaveManager:SetFolder("NonnyHub/game")

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

local function getAutoSaveFile()
    return "autosave_" .. tostring(player.Name) -- ใช้ username แทน userId
end

task.spawn(function()
    local autosaveName = getAutoSaveFile()
    local autosaveFile = SaveManager.Folder .. "/settings/" .. autosaveName .. ".json"

    if isfile(autosaveFile) then
        local success, err = SaveManager:Load(autosaveName)
        if success then
            print("✅ Auto-loaded config for UserId:", userId)
            Fluent:Notify({
                Title = "Config",
                Content = "Auto-loaded settings for UserId: " .. userId,
                Duration = 3
            })
        else
            warn("❌ Failed to load config for UserId:", userId, err)
        end
    end
end)

-- ========================
-- 🔔 Auto Save Config (FIXED)
-- ========================
local function autoSave()
    local autosaveName = getAutoSaveFile()
    local success, err = SaveManager:Save(autosaveName)
    if success then
        print("💾 Saved:", autosaveName)
    else
        warn("❌ Save failed:", err)
    end
end

-- 🔥 Hook ทุก Option แบบถูกต้อง
for _, option in pairs(SaveManager.Options) do
    if option.OnChanged then
        option:OnChanged(function()
            autoSave()
        end)
    end
end

-- ========================
-- 🔔 Notify Loaded
-- ========================
Fluent:Notify({
    Title = "Loaded",
    Content = "Auto Farm Ready 🔥",
    Duration = 5
})

-- โหลด Autoload Config
SaveManager:LoadAutoloadConfig()
