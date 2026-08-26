--!nocheck
--[[
  Chicken Auto Hub - Obsidian / LinoriaLib UI
  (Full English Edition: Automation, Target Maxing, Expand Coop, Smart Tower, Incubator & Safe Anti-AFK)
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
}

local sessionId = 0
local isLoopRunning = false
local currentGeneratorTarget = 1

---------------------------------------------------------
-- 🛡️ SAFE ANTI-AFK (Native Physics Simulation)
---------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(600)
		pcall(function()
			local char = LocalPlayer.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				hum.Jump = true
			end
		end)
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

	-- Expand Coop before buying slots 3 and above
	if currentGeneratorTarget >= 3 then
		safeInvoke("ExpandCoop")
	end

	-- Unlock / Buy generator slot
	if validRemotes["BuyGenerator"] then
		safeInvoke("BuyGenerator", currentGeneratorTarget)
	elseif validRemotes["PurchaseGenerator"] then
		safeInvoke("PurchaseGenerator", currentGeneratorTarget)
	end

	-- Turbo Upgrade current target generator
	for _ = 1, 3 do
		local ok, res = safeInvoke("UpgradeGenerator", currentGeneratorTarget)

		local isMax = false
		if ok and type(res) == "table" and res.error then
			local err = tostring(res.error):lower()
			if string.find(err, "max") or string.find(err, "full") or string.find(err, "limit") then
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
		task.wait(0.03)
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

local function stopAll()
	CONFIG.enabled = false
	_G.__AutoFarmRebirthStop = true
	_G.__AutoFarmRebirthRunning = false
	isLoopRunning = false
	sessionId = sessionId + 1
end

local function startLoops()
	if isLoopRunning then return end
	isLoopRunning = true
	
	CONFIG.enabled = true
	_G.__AutoFarmRebirthStop = false
	_G.__AutoFarmRebirthRunning = true
	
	sessionId = sessionId + 1
	local currentSession = sessionId

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

				-- Reset target generator to slot 1 after rebirth
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
	Title = "Chicken Auto Hub",
	Footer = "version: 1.0.0",
	Icon = 95816097006870,
	NotifySide = "Right",
	ShowCustomCursor = true,
})

local Tabs = {
	Main = Window:AddTab("Main", "user"),
	["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

-- Left Column: Automation Controls
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
	Text = "Auto Feeder (Max 1-by-1 & Expand)",
	Default = true,
	Tooltip = "Upgrades feeder slots sequentially to max level and auto expands coop.",
	Callback = function(Value)
		CONFIG.autoUpgrade = Value
	end,
})

LeftGroupBox:AddToggle("AutoIncubator", {
	Text = "Auto Claim Incubator (Every 3 Min)",
	Default = true,
	Tooltip = "Automatically claims finished eggs from the incubator every 3 minutes.",
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

-- Right Column: Manual Actions & Script Termination
local RightGroupBox = Tabs.Main:AddRightGroupbox("Manual & System Controls")

RightGroupBox:AddButton({
	Text = "🚀 Send Chicken to Tower",
	Func = function()
		startTower(true, sessionId)
		Library:Notify("Chicken dispatched to Tower", 2)
	end,
	Tooltip = "Instantly sends chicken to highest available Tower floor.",
})

RightGroupBox:AddButton({
	Text = "🥚 Claim Incubator Now",
	Func = function()
		safeInvoke("IncubatorClaim")
		Library:Notify("Incubator Claim invoked", 2)
	end,
	Tooltip = "Manually triggers incubator reward collection.",
})

RightGroupBox:AddButton({
	Text = "🔄 Attempt Rebirth Now",
	Func = function()
		local ok, res = tryRebirth()
		if ok then
			Library:Notify("🎉 Rebirth Successful!", 3)
		else
			Library:Notify("❌ Rebirth Failed: " .. tostring(res), 3)
		end
	end,
	Tooltip = "Attempts to trigger Rebirth immediately.",
})

RightGroupBox:AddDivider()

RightGroupBox:AddButton({
	Text = "❌ Kill Script & Destroy UI",
	Func = function()
		stopAll()
		Library:Unload()
	end,
	Tooltip = "Completely halts automation threads and destroys the UI screen.",
	Risky = true,
})

-- UI Settings Tab
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

MenuGroup:AddButton("Unload UI", function()
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

-- Start Automation
startLoops()