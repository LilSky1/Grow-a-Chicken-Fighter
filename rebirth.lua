--!nocheck
--[[
  Chicken Auto Hub - Obsidian / LinoriaLib UI
  (Full English Edition: Automation, Event Mob Tracking & Hover, Target Maxing, Expand Coop, Smart Tower & Incubator)
]]

-- Terminate previous script instances
if _G.__AutoFarmRebirthRunning then
	_G.__AutoFarmRebirthStop = true
	_G.__AutoFarmRebirthRunning = false
	task.wait(0.3)
end
_G.__AutoFarmRebirthRunning = true
_G.__AutoFarmRebirthStop = false

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes", 5)

-- Load Obsidian UI Library & Addons
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

local CONFIG = {
	enabled = true,
	autoUpgrade = true,
	autoClaimIncubator = true,
	maxGenerators = 6,          -- Configurable from 1 to 6
	upgradeInterval = 0.10,     -- Turbo Delay (0.10s)
	towerRestartInterval = 16,
	rebirthCheckInterval = 5,
	incubatorInterval = 180,    -- 3 Minutes
	cooldownBeforeTower = 6,
	cooldownAfterRebirth = 8,

	-- Event / Mob Tracking Configuration
	autoTrackEventMob = false,
	hoverHeight = 10,           -- Distance above NPC head

	-- Anti-AFK Configuration
	autoAntiAFK = true,
	antiAFKInterval = 600,     -- 10 Minutes (600s)
}

local sessionId = 0
local isLoopRunning = false
local currentGeneratorTarget = 1
local eventTrackingConnection = nil

---------------------------------------------------------
-- 🛡️ SAFE ANTI-AFK (Human-like Walk Simulation Every 10 Mins)
---------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(CONFIG.antiAFKInterval or 600)
		if CONFIG.autoAntiAFK then
			pcall(function()
				local char = LocalPlayer.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local hrp = char and char:FindFirstChild("HumanoidRootPart")

				if hum and hrp and hum.Health > 0 then
					local startPos = hrp.Position
					
					-- 1. Walk forward 3 studs
					hum:MoveTo(startPos + (hrp.CFrame.LookVector * 3))
					task.wait(0.6)
					
					-- 2. Walk back to starting position
					hum:MoveTo(startPos)
					task.wait(0.6)
					
					-- 3. Stop movement
					hum:Move(Vector3.zero)
				end
			end)
		end
	end
end)

local function smartWait(duration, currentSession)
	local start = tick()
	while tick() - start < duration do
		if not CONFIG.enabled or _G.__AutoFarmRebirthStop or sessionId ~= currentSession then
			return false
		end
		task.wait(0.2)
	end
	return true
end

---------------------------------------------------------
-- REMOTE INITIALIZATION & CACHING
---------------------------------------------------------
local validRemotes = {}
local function initRemotesOnce()
	if RemotesFolder then
		for _, r in ipairs(RemotesFolder:GetChildren()) do
			if r:IsA("RemoteFunction") or r:IsA("RemoteEvent") then
				validRemotes[r.Name] = r
			end
		end
	end

	if getnilinstances then
		for _, v in pairs(getnilinstances()) do
			if (v.ClassName == "RemoteFunction" or v.ClassName == "RemoteEvent") and not validRemotes[v.Name] then
				validRemotes[v.Name] = v
			end
		end
	end
end
initRemotesOnce()

local okReq, CoreRemotes = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Core", 3):WaitForChild("Remotes", 3))
end)

local function safeInvoke(remoteName, ...)
	if not CONFIG.enabled or _G.__AutoFarmRebirthStop then return false end
	
	local remote = validRemotes[remoteName] or (RemotesFolder and RemotesFolder:FindFirstChild(remoteName))
	if remote then
		local ok, res = pcall(function(...)
			if remote:IsA("RemoteFunction") then
				return remote:InvokeServer(...)
			elseif remote:IsA("RemoteEvent") then
				remote:FireServer(...)
				return "Fired"
			end
		end, ...)
		if ok then return true, res end
	end

	if okReq and CoreRemotes and CoreRemotes.defs and CoreRemotes.defs[remoteName] then
		local ok, res = pcall(function(...)
			return CoreRemotes.invoke(CoreRemotes.defs[remoteName], ...)
		end, ...)
		if ok then return true, res end
	end

	return false, nil
end

-- Progressive Generator Upgrade & Step-by-Step Coop Expansion
local function tryBuyAndUpgradeGenerators()
	if not CONFIG.enabled or _G.__AutoFarmRebirthStop then return end

	if currentGeneratorTarget > CONFIG.maxGenerators then
		currentGeneratorTarget = CONFIG.maxGenerators
	end

	-- 1. If target is generator 3 or higher, expand coop first
	if currentGeneratorTarget >= 3 then
		safeInvoke("ExpandCoop")
	end

	-- 2. Unlock / Buy current generator slot
	if validRemotes["BuyGenerator"] then
		safeInvoke("BuyGenerator", currentGeneratorTarget)
	elseif validRemotes["PurchaseGenerator"] then
		safeInvoke("PurchaseGenerator", currentGeneratorTarget)
	else
		safeInvoke("BuyGenerator", currentGeneratorTarget)
	end

	-- 3. Turbo Upgrade current target generator
	for _ = 1, 3 do
		local ok, res = safeInvoke("UpgradeGenerator", currentGeneratorTarget)

		local isMax = false
		if ok and type(res) == "table" and res.error then
			local err = tostring(res.error):lower()
			if (string.find(err, "max") or string.find(err, "full")) and not string.find(err, "coop") and not string.find(err, "money") and not string.find(err, "cash") and not string.find(err, "afford") then
				isMax = true
			end
		end

		if isMax then
			if currentGeneratorTarget < CONFIG.maxGenerators then
				currentGeneratorTarget = currentGeneratorTarget + 1
				if currentGeneratorTarget >= 3 then
					safeInvoke("ExpandCoop")
				end
			end
			break
		end
		task.wait(0.04)
	end
end

local function getTowerTargets()
	local highestBeaten = 0
	local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
	if leaderstats then
		local stat = leaderstats:FindFirstChild("Tower") or leaderstats:FindFirstChild("MaxTower") or leaderstats:FindFirstChild("Floor")
		if stat then
			highestBeaten = tonumber(stat.Value) or 0
		end
	end

	local nextFloor = highestBeaten + 1
	local checkpointFloor = math.floor(highestBeaten / 5) * 5
	if checkpointFloor < 5 then checkpointFloor = 5 end

	return nextFloor, checkpointFloor
end

local function startTower(skipCooldown, currentSession)
	if not CONFIG.enabled or _G.__AutoFarmRebirthStop or sessionId ~= currentSession then return end

	if not skipCooldown and CONFIG.cooldownBeforeTower > 0 then
		if not smartWait(CONFIG.cooldownBeforeTower, currentSession) then return end
	end

	if not CONFIG.enabled or _G.__AutoFarmRebirthStop or sessionId ~= currentSession then return end

	safeInvoke("TowerContinueDecline")
	task.wait(0.1)

	local nextFloor, checkpointFloor = getTowerTargets()

	safeInvoke("TowerElevator", nextFloor)
	task.wait(0.15)

	if checkpointFloor ~= nextFloor then
		safeInvoke("TowerElevator", checkpointFloor)
		task.wait(0.15)
	end

	safeInvoke("TowerStart")
end

local function tryRebirth()
	local ok, result = safeInvoke("Rebirth")
	if ok then
		if type(result) == "table" and result.ok == false then return false, result.error or "ok=false" end
		if result ~= false then return true, result end
	end

	if okReq and CoreRemotes and CoreRemotes.defs and CoreRemotes.defs.Rebirth then
		local okCore, resultCore = pcall(function()
			return CoreRemotes.invoke(CoreRemotes.defs.Rebirth)
		end)
		if okCore then
			if type(resultCore) == "table" and resultCore.ok == false then return false, resultCore.error or "ok=false" end
			if resultCore ~= false then return true, resultCore end
		end
	end

	return false, tostring(result)
end

---------------------------------------------------------
-- 🐔 DYNAMIC EVENT MOB SEARCH & TRACKING LOGIC
---------------------------------------------------------
local function getTargetChickenMob()
	local folder = workspace:FindFirstChild("ChickenBodies")
	if folder then
		for _, npc in ipairs(folder:GetChildren()) do
			-- Finds any NPC starting with "ChickenBody_npc" regardless of the trailing ID number
			if npc.Name:find("ChickenBody_npc") then
				local root = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Head") or npc:FindFirstChildWhichIsA("BasePart")
				if root then
					return npc, root
				end
			end
		end
	end
	return nil, nil
end

local function updateEventTrackingState(enable)
	if eventTrackingConnection then
		eventTrackingConnection:Disconnect()
		eventTrackingConnection = nil
	end

	if not enable then return end

	eventTrackingConnection = RunService.Heartbeat:Connect(function()
		if not CONFIG.autoTrackEventMob or not CONFIG.enabled or _G.__AutoFarmRebirthStop then
			if eventTrackingConnection then
				eventTrackingConnection:Disconnect()
				eventTrackingConnection = nil
			end
			return
		end

		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")

		if hrp and hum and hum.Health > 0 then
			local _, targetRoot = getTargetChickenMob()
			if targetRoot then
				-- Hover smoothly above target NPC
				hrp.CFrame = CFrame.new(targetRoot.Position + Vector3.new(0, CONFIG.hoverHeight, 0))
				hrp.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end)
end

local function stopAll()
	CONFIG.enabled = false
	_G.__AutoFarmRebirthStop = true
	_G.__AutoFarmRebirthRunning = false
	isLoopRunning = false
	sessionId = sessionId + 1

	if eventTrackingConnection then
		eventTrackingConnection:Disconnect()
		eventTrackingConnection = nil
	end
end

local function startLoops()
	if isLoopRunning then return end
	isLoopRunning = true
	
	CONFIG.enabled = true
	_G.__AutoFarmRebirthStop = false
	_G.__AutoFarmRebirthRunning = true
	
	sessionId = sessionId + 1
	local currentSession = sessionId

	if CONFIG.autoTrackEventMob then
		updateEventTrackingState(true)
	end

	task.spawn(function()
		tryBuyAndUpgradeGenerators()
		if CONFIG.autoClaimIncubator then
			safeInvoke("IncubatorClaim")
		end
		startTower(false, currentSession)
	end)

	-- 1. Loop Auto Buy/Upgrade Feeder
	task.spawn(function()
		while CONFIG.enabled and not _G.__AutoFarmRebirthStop and sessionId == currentSession do
			if CONFIG.autoUpgrade then
				safeInvoke("TowerContinueDecline")
				tryBuyAndUpgradeGenerators()
			end
			if not smartWait(CONFIG.upgradeInterval, currentSession) then break end
		end
	end)

	-- 2. Loop Tower Keep-Alive
	task.spawn(function()
		while CONFIG.enabled and not _G.__AutoFarmRebirthStop and sessionId == currentSession do
			if not smartWait(CONFIG.towerRestartInterval, currentSession) then break end
			if CONFIG.enabled and not _G.__AutoFarmRebirthStop and sessionId == currentSession then
				startTower(true, currentSession)
			end
		end
	end)

	-- 3. Loop Auto Incubator Claim
	task.spawn(function()
		while CONFIG.enabled and not _G.__AutoFarmRebirthStop and sessionId == currentSession do
			if not smartWait(CONFIG.incubatorInterval, currentSession) then break end
			if CONFIG.enabled and CONFIG.autoClaimIncubator and not _G.__AutoFarmRebirthStop and sessionId == currentSession then
				safeInvoke("IncubatorClaim")
			end
		end
	end)

	-- 4. Loop Auto Rebirth
	task.spawn(function()
		while CONFIG.enabled and not _G.__AutoFarmRebirthStop and sessionId == currentSession do
			local ok, _ = tryRebirth()

			if ok then
				safeInvoke("TowerSurrender")

				if okReq and CoreRemotes and CoreRemotes.defs and (CoreRemotes.defs.ClaimRebirthMilestones or CoreRemotes.defs.ClaimRebirthMilestone) then
					local def = CoreRemotes.defs.ClaimRebirthMilestones or CoreRemotes.defs.ClaimRebirthMilestone
					pcall(function() CoreRemotes.invoke(def) end)
				else
					safeInvoke("ClaimRebirthMilestones")
				end

				currentGeneratorTarget = 1

				task.wait(1.0)
				tryBuyAndUpgradeGenerators()

				if not smartWait(CONFIG.cooldownAfterRebirth, currentSession) then break end

				if CONFIG.enabled and not _G.__AutoFarmRebirthStop and sessionId == currentSession then
					startTower(false, currentSession)
				end
			end
			if not smartWait(CONFIG.rebirthCheckInterval, currentSession) then break end
		end
		if sessionId == currentSession then
			isLoopRunning = false
			_G.__AutoFarmRebirthRunning = false
		end
	end)
end

---------------------------------------------------------
-- OBSIDIAN UI SETUP
---------------------------------------------------------
local Window = Library:CreateWindow({
	Title = "Chicken By Lilsky1",
	Footer = "version: 1.0.0",
	NotifySide = "Right",
	ShowCustomCursor = true,
})

local Tabs = {
	Main = Window:AddTab("Main", "user"),
	AntiAFK = Window:AddTab("Anti AFK", "shield"),
	["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

-- TAB 1: Main Automation & Event Controls
local LeftGroupBox = Tabs.Main:AddLeftGroupbox("Automation Controls")

LeftGroupBox:AddToggle("MasterAutoFarm", {
	Text = "Enable Auto Farm & Rebirth",
	Default = true,
	Tooltip = "Master switch for all automated farming, tower climbs, and rebirths.",
	Callback = function(Value)
		if Value then
			startLoops()
			Library:Notify("Auto Farm & Rebirth Enabled", 3)
		else
			stopAll()
			Library:Notify("Auto Farm & Rebirth Disabled", 3)
		end
	end,
})

LeftGroupBox:AddToggle("AutoFeeder", {
	Text = "Auto Feeder (Max & Expand)",
	Default = true,
	Tooltip = "Upgrades feeder slots sequentially to max level and auto expands coop.",
	Callback = function(Value)
		CONFIG.autoUpgrade = Value
	end,
})

LeftGroupBox:AddToggle("AutoIncubator", {
	Text = "Auto Claim Incubator",
	Default = true,
	Tooltip = "Automatically claims finished eggs from the incubator.",
	Callback = function(Value)
		CONFIG.autoClaimIncubator = Value
	end,
})

LeftGroupBox:AddDivider()

LeftGroupBox:AddSlider("MaxGenSlider", {
	Text = "Max Feeder Generators",
	Default = 6,
	Min = 1,
	Max = 6,
	Rounding = 0,
	Compact = false,
	Tooltip = "Set the maximum generator count to purchase and upgrade.",
	Callback = function(Value)
		CONFIG.maxGenerators = math.floor(Value)
	end,
})

local RightGroupBox = Tabs.Main:AddRightGroupbox("Auto Event")

RightGroupBox:AddToggle("AutoTrackMob", {
	Text = "Golden Goose",
	Default = false,
	Tooltip = "Continuously follows and hovers directly above active ChickenBody_npc:* targets.",
	Callback = function(Value)
		CONFIG.autoTrackEventMob = Value
		updateEventTrackingState(Value)
		if Value then
			Library:Notify("Event Mob Tracking: Active", 2)
		else
			Library:Notify("Event Mob Tracking: Stopped", 2)
		end
	end,
})

RightGroupBox:AddSlider("HoverHeightSlider", {
	Text = "Hover Height Distance",
	Default = 10,
	Min = 4,
	Max = 35,
	Rounding = 0,
	Compact = false,
	Tooltip = "Adjust vertical offset above the mob.",
	Callback = function(Value)
		CONFIG.hoverHeight = math.floor(Value)
	end,
})

RightGroupBox:AddDivider()

RightGroupBox:AddButton({
	Text = "📍 Teleport to Current Event Mob",
	Func = function()
		local npc, root = getTargetChickenMob()
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")

		if root and hrp then
			hrp.CFrame = CFrame.new(root.Position + Vector3.new(0, CONFIG.hoverHeight, 0))
			Library:Notify("Teleported to " .. npc.Name, 3)
		else
			Library:Notify("No active ChickenBody NPC found in Workspace", 3)
		end
	end,
	Tooltip = "Instantly teleports above the current ChickenBody_npc in workspace.",
})

RightGroupBox:AddButton({
	Text = "❌ Kill Script & Destroy UI",
	Func = function()
		stopAll()
		Library:Unload()
	end,
	Tooltip = "Halts all automation and unloads the UI.",
})

-- TAB 2: Anti AFK Controls
local AntiAFKLeftBox = Tabs.AntiAFK:AddLeftGroupbox("Anti-AFK System")

AntiAFKLeftBox:AddToggle("EnableAntiAFKToggle", {
	Text = "Enable Anti-AFK",
	Default = true,
	Tooltip = "Simulates human walking forward 3 studs & back every 10 minutes to prevent Roblox 20-min AFK disconnects.",
	Callback = function(Value)
		CONFIG.autoAntiAFK = Value
		if Value then
			Library:Notify("Anti-AFK Walk Enabled", 2)
		else
			Library:Notify("Anti-AFK Walk Disabled", 2)
		end
	end,
})

AntiAFKLeftBox:AddSlider("AntiAFKIntervalSlider", {
	Text = "Anti-AFK Interval (Minutes)",
	Default = 10,
	Min = 1,
	Max = 15,
	Rounding = 0,
	Compact = false,
	Tooltip = "Frequency of walking simulation in minutes.",
	Callback = function(Value)
		CONFIG.antiAFKInterval = math.floor(Value) * 60
	end,
})

local AntiAFKRightBox = Tabs.AntiAFK:AddRightGroupbox("Manual Testing")

AntiAFKRightBox:AddButton({
	Text = "🚶 Walk Simulation Test",
	Func = function()
		pcall(function()
			local char = LocalPlayer.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local hrp = char and char:FindFirstChild("HumanoidRootPart")

			if hum and hrp and hum.Health > 0 then
				local startPos = hrp.Position
				hum:MoveTo(startPos + (hrp.CFrame.LookVector * 3))
				task.wait(0.6)
				hum:MoveTo(startPos)
				task.wait(0.6)
				hum:Move(Vector3.zero)
				Library:Notify("Anti-AFK walk simulation executed", 2)
			end
		end)
	end,
	Tooltip = "Triggers the 3-stud walk forward & back test immediately.",
})

-- TAB 3: UI Settings
local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu Configuration")

MenuGroup:AddToggle("KeybindMenuOpen", {
	Default = Library.KeybindFrame.Visible,
	Text = "Open Keybind Menu",
	Callback = function(value)
		Library.KeybindFrame.Visible = value
	end,
})

MenuGroup:AddToggle("ShowCustomCursor", {
	Text = "Custom Cursor",
	Default = true,
	Callback = function(Value)
		Library.ShowCustomCursor = Value
	end,
})

MenuGroup:AddDropdown("NotificationSide", {
	Values = { "Left", "Right" },
	Default = "Right",
	Text = "Notification Side",
	Callback = function(Value)
		Library:SetNotifySide(Value)
	end,
})

MenuGroup:AddDivider()

MenuGroup:AddLabel("Menu Keybind"):AddKeyPicker("MenuKeybind", {
	Default = "RightControl",
	NoUI = true,
	Text = "Menu Keybind"
})

MenuGroup:AddButton("❌ Kill Script & Destroy UI", function()
	stopAll()
	Library:Unload()
end)

Library.ToggleKeybind = Options.MenuKeybind

-- Theme & Config Managers
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

ThemeManager:SetFolder("ChickenHub")
SaveManager:SetFolder("ChickenHub/specific-game")

SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])

SaveManager:LoadAutoloadConfig()

-- Create Top-Right Window Close Button (✕) next to drag handle
task.spawn(function()
	task.wait(0.5)
	pcall(function()
		local outer = Library.Outer
		if not outer then return end

		local oldBtn = outer:FindFirstChild("HeaderCloseButton", true)
		if oldBtn then oldBtn:Destroy() end

		local topContainer = outer:FindFirstChild("TopBar") or outer:FindFirstChild("Header") or outer

		local closeBtn = Instance.new("TextButton")
		closeBtn.Name = "HeaderCloseButton"
		closeBtn.Size = UDim2.new(0, 22, 0, 22)
		closeBtn.Position = UDim2.new(1, -30, 0, 4)
		closeBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
		closeBtn.Text = "✕"
		closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		closeBtn.Font = Enum.Font.GothamBold
		closeBtn.TextSize = 13
		closeBtn.BorderSizePixel = 0
		closeBtn.ZIndex = 99999
		closeBtn.Parent = topContainer

		local corner = Instance.new("UICorner", closeBtn)
		corner.CornerRadius = UDim.new(0, 4)

		closeBtn.MouseButton1Click:Connect(function()
			stopAll()
			Library:Unload()
		end)
	end)
end)

-- Start Automation
startLoops()