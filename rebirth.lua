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
	upgradeAllAtOnce = false,   -- false: Sequential 1-by-1 | true: Upgrade All Simultaneously
	autoClaimIncubator = true,
	maxGenerators = 6,          -- Configurable from 1 to 6
	upgradeInterval = 0.10,     -- Turbo Delay (0.10s)
	towerRestartInterval = 16,
	rebirthCheckInterval = 5,
	incubatorInterval = 180,    -- 3 Minutes
	cooldownBeforeTower = 6,
	cooldownAfterRebirth = 8,

	-- Anti-AFK Configuration
	autoAntiAFK = true,
	antiAFKInterval = 600,     -- 10 Minutes (600s)

	-- Nest Egg Collection Configuration
	autoCollectNestEggs = true,
	nestEggCheckInterval = 3,  -- Every 3 seconds

	-- Golden Goose Tracker Configuration
	autoTrackGoldenGoose = false,
	autoAttackGoldenGoose = false,
	goldenGooseHoverHeight = 6,
	goldenGooseTeleportInterval = 3, -- Teleport once every 3 seconds (Anti-Kick)
}

local sessionId = 0
local isLoopRunning = false
local currentGeneratorTarget = 1
local goldenGooseConnection = nil

---------------------------------------------------------
-- 🛡️ SAFE ANTI-AFK (Human-like Walk Simulation Every 10 Mins)
---------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(CONFIG.antiAFKInterval or 600)
		if _G.__AutoFarmRebirthStop then break end
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
	if _G.__AutoFarmRebirthStop then return false end
	
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

---------------------------------------------------------
-- 🔄 REBIRTH UI COLOR CHECK LOGIC
---------------------------------------------------------
local function getRebirthBar()
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then return nil end

	-- 1. Try direct path provided: PlayerGui:GetChildren()[11].Frame.window.panel.face.content.content.body.reqCard.face.content.bar
	local ok, bar = pcall(function()
		local children = playerGui:GetChildren()
		if children[11] then
			return children[11].Frame.window.panel.face.content.content.body.reqCard.face.content.bar
		end
	end)
	if ok and bar then return bar end

	-- 2. Fallback: Dynamic search across all ScreenGuis in PlayerGui for reqCard -> bar
	for _, gui in ipairs(playerGui:GetChildren()) do
		local reqCard = gui:FindFirstChild("reqCard", true)
		if reqCard then
			local foundBar = reqCard:FindFirstChild("bar", true)
			if foundBar then
				return foundBar
			end
		end
	end

	return nil
end

local function isRebirthReadyFromUI()
	local bar = getRebirthBar()
	if not bar then return nil end

	-- Collect candidate colors from bar and its descendants
	local candidateColors = {}
	if bar:IsA("GuiObject") then
		table.insert(candidateColors, bar.BackgroundColor3)
		if bar:IsA("ImageLabel") or bar:IsA("ImageButton") then
			table.insert(candidateColors, bar.ImageColor3)
		end
	end

	for _, child in ipairs(bar:GetDescendants()) do
		if child:IsA("GuiObject") then
			table.insert(candidateColors, child.BackgroundColor3)
			if child:IsA("ImageLabel") or child:IsA("ImageButton") then
				table.insert(candidateColors, child.ImageColor3)
			end
		end
	end

	for _, color in ipairs(candidateColors) do
		local r = math.floor(color.R * 255 + 0.5)
		local g = math.floor(color.G * 255 + 0.5)
		local b = math.floor(color.B * 255 + 0.5)

		-- Ready color: RGB (8, 78, 15) - Greenish
		if (math.abs(r - 8) <= 12 and math.abs(g - 78) <= 15 and math.abs(b - 15) <= 12) or (g > r + 30 and g > b + 30) then
			return true
		end

		-- Not ready color: RGB (0, 57, 89) - Blueish
		if (math.abs(r - 0) <= 12 and math.abs(g - 57) <= 15 and math.abs(b - 89) <= 15) or (b > r + 30 and b > g + 10) then
			return false
		end
	end

	return nil
end

-- Progressive Generator Upgrade & Step-by-Step Coop Expansion
local function tryBuyAndUpgradeGenerators()
	if not CONFIG.enabled or _G.__AutoFarmRebirthStop then return end
	if isRebirthReadyFromUI() == true then return end

	if CONFIG.upgradeAllAtOnce then
		-- Mode: Upgrade All Generators Simultaneously (Round-Robin)
		for i = 1, CONFIG.maxGenerators do
			if not CONFIG.enabled or _G.__AutoFarmRebirthStop then break end

			if i >= 3 then
				safeInvoke("ExpandCoop")
			end

			if validRemotes["BuyGenerator"] then
				safeInvoke("BuyGenerator", i)
			elseif validRemotes["PurchaseGenerator"] then
				safeInvoke("PurchaseGenerator", i)
			else
				safeInvoke("BuyGenerator", i)
			end

			safeInvoke("UpgradeGenerator", i)
			task.wait(0.02)
		end
	else
		-- Mode: Sequential Upgrade (1-by-1 to Max Level)
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
	if isRebirthReadyFromUI() == true then
		safeInvoke("TowerSurrender")
		return
	end

	if not skipCooldown and CONFIG.cooldownBeforeTower > 0 then
		if not smartWait(CONFIG.cooldownBeforeTower, currentSession) then return end
	end

	if not CONFIG.enabled or _G.__AutoFarmRebirthStop or sessionId ~= currentSession then return end
	if isRebirthReadyFromUI() == true then
		safeInvoke("TowerSurrender")
		return
	end

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
	local uiReady = isRebirthReadyFromUI()
	if uiReady == false then
		-- Rebirth requirement is explicitly NOT ready yet according to UI bar color (0, 57, 89)
		return false, "UI bar indicates not ready (color 0, 57, 89)"
	end

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
-- 🥚 AUTOMATED NEST EGG COLLECTION LOGIC
---------------------------------------------------------
local function tryCollectNestEggs()
	if not CONFIG.autoCollectNestEggs or _G.__AutoFarmRebirthStop then return end

	local folder = workspace:FindFirstChild("NestEggs")
	if not folder then return end

	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")

	for _, nestEgg in ipairs(folder:GetChildren()) do
		if not CONFIG.enabled or _G.__AutoFarmRebirthStop then break end

		local ownerAttr = nestEgg:GetAttribute("owner")
		local isMyEgg = false

		if ownerAttr then
			if tonumber(ownerAttr) == LocalPlayer.UserId or tostring(ownerAttr) == tostring(LocalPlayer.UserId) or tostring(ownerAttr) == LocalPlayer.Name then
				isMyEgg = true
			end
		else
			isMyEgg = true
		end

		if isMyEgg then
			-- 1. Fire Remote collection if available
			local eggId = nestEgg:GetAttribute("eggId")
			if eggId then
				safeInvoke("CollectNestEgg", eggId)
				safeInvoke("ClaimNestEgg", eggId)
				safeInvoke("CollectEgg", eggId)
			end
			safeInvoke("CollectNestEgg", nestEgg)

			-- 2. Touch Interest collection (firetouchinterest)
			if hrp then
				local targetPart = nestEgg:IsA("BasePart") and nestEgg or nestEgg:FindFirstChildWhichIsA("BasePart", true)
				if targetPart then
					if firetouchinterest then
						pcall(function()
							firetouchinterest(hrp, targetPart, 0)
							task.wait(0.02)
							firetouchinterest(hrp, targetPart, 1)
						end)
					end
				end
			end
		end
	end
end

---------------------------------------------------------
-- 🐔 GOLDEN GOOSE STRICT TARGETING & TRACKING LOGIC
---------------------------------------------------------
local function findRootPart(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") then
		if inst.PrimaryPart then return inst.PrimaryPart end
		local hrp = inst:FindFirstChild("HumanoidRootPart", true) or inst:FindFirstChild("Head", true) or inst:FindFirstChild("Torso", true) or inst:FindFirstChildWhichIsA("BasePart", true)
		if hrp then return hrp end
	end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local lastDebugNotifyTime = 0
local lastFoundTargetName = ""
local lastPrintLogTime = 0

local function isGoldenGooseMob(npc)
	if not npc then return false end

	-- Must be a Model or BasePart inside workspace.ChickenBodies
	if not (npc:IsA("Model") or npc:IsA("BasePart")) then
		return false
	end

	local name = npc.Name:lower()

	-- 1. Exclude coop chickens and tower rivals
	if name:find("coop") or name:find("tower") or name:find("rival") then
		return false
	end

	-- 2. Check ovName attribute: MUST NOT be "Chicken Boss"
	local ovName = npc:GetAttribute("ovName")
	if ovName then
		local ovStr = tostring(ovName):lower()
		if ovStr:find("boss") or ovStr:find("chicken boss") then
			return false
		end
		if ovStr:find("golden") or ovStr:find("goose") then
			print("[Goose Tracker Debug] MATCHED by ovName 'Golden Goose': " .. npc.Name)
			return true
		end
	end

	-- 3. Check ovNameKey attribute: MUST NOT be boss.chickenBoss
	local ovNameKey = npc:GetAttribute("ovNameKey")
	if ovNameKey then
		local keyStr = tostring(ovNameKey):lower()
		if keyStr:find("boss") then
			return false
		end
		if keyStr:find("golden") or keyStr:find("goose") then
			print("[Goose Tracker Debug] MATCHED by ovNameKey: " .. npc.Name)
			return true
		end
	end

	-- 4. Check cos_color attribute: Must contain "golden"
	local cosColor = npc:GetAttribute("cos_color")
	if cosColor and tostring(cosColor):lower():find("golden") then
		print("[Goose Tracker Debug] MATCHED by cos_color 'golden': " .. npc.Name)
		return true
	end

	-- 5. Direct child GooseDamagePodium (GooseDamagePodium is UNIQUE to Golden Goose!)
	if npc:FindFirstChild("GooseDamagePodium") then
		print("[Goose Tracker Debug] MATCHED by GooseDamagePodium: " .. npc.Name)
		return true
	end

	return false
end

local function getTargetGoldenGoose()
	local folder = workspace:FindFirstChild("ChickenBodies")
	if not folder then
		print("[Goose Tracker Debug] workspace.ChickenBodies folder does not exist!")
		return nil, nil, 0
	end

	local children = folder:GetChildren()
	local checkedCount = #children

	for _, npc in ipairs(children) do
		if isGoldenGooseMob(npc) then
			local root = findRootPart(npc)
			if root then
				if npc.Name ~= lastFoundTargetName and tick() - lastDebugNotifyTime > 3 then
					lastFoundTargetName = npc.Name
					lastDebugNotifyTime = tick()
					Library:Notify("[Goose Debug] Target Acquired: " .. npc.Name, 3)
					print(string.format("[Goose Tracker Debug] >>> TARGET ACQUIRED: workspace.ChickenBodies['%s'] (Root: %s, Pos: %.1f, %.1f, %.1f)", npc.Name, root.Name, root.Position.X, root.Position.Y, root.Position.Z))
				end
				return npc, root, checkedCount
			end
		end
	end

	return nil, nil, checkedCount
end

local GoldenGooseStatusLabel = nil
local trackerSessionId = 0

local function updateGoldenGooseTracker(enable)
	_G.__GoldenGooseTrackerActive = enable
	trackerSessionId = trackerSessionId + 1
	local currentTrackerSession = trackerSessionId

	print("[Goose Tracker Debug] updateGoldenGooseTracker state changed to: " .. tostring(enable))

	if not enable then
		if GoldenGooseStatusLabel then GoldenGooseStatusLabel:SetText("Status: Tracker Disabled") end
		return
	end

	task.spawn(function()
		while CONFIG.autoTrackGoldenGoose and _G.__GoldenGooseTrackerActive and not _G.__AutoFarmRebirthStop and trackerSessionId == currentTrackerSession do
			pcall(function()
				local char = LocalPlayer.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")

				if hrp and hum and hum.Health > 0 then
					local targetNpc, targetRoot, checkedCount = getTargetGoldenGoose()
					if targetRoot then
						local displayName = targetNpc:GetAttribute("ovName") or targetNpc.Name
						if GoldenGooseStatusLabel then
							GoldenGooseStatusLabel:SetText("Status: Teleporting every 3s to " .. tostring(displayName) .. " (" .. targetNpc.Name .. ")")
						end

						print(string.format("[Goose Tracker Debug] >>> Teleporting player to Golden Goose '%s' (%s) at CFrame Pos: %.1f, %.1f, %.1f", tostring(displayName), targetNpc.Name, targetRoot.Position.X, targetRoot.Position.Y + CONFIG.goldenGooseHoverHeight, targetRoot.Position.Z))

						-- 1. Teleport player once every 3 seconds above Golden Goose
						hrp.CFrame = CFrame.new(targetRoot.Position + Vector3.new(0, CONFIG.goldenGooseHoverHeight, 0))

						-- 2. Remote Attacks
						local fired = safeInvoke("SetChickenOrder", "chaos")
						if fired then
							print("[Goose Tracker Debug] Fired Remote 'SetChickenOrder' ('chaos')")
						end

						if CONFIG.autoAttackGoldenGoose and targetNpc then
							safeInvoke("AttackMob", targetNpc)
							safeInvoke("HitMob", targetNpc)
							safeInvoke("DamageMob", targetNpc)
						end
					else
						print(string.format("[Goose Tracker Debug] Searching... Checked %d items in ChickenBodies. No Golden Goose target active.", checkedCount))
						if GoldenGooseStatusLabel then
							GoldenGooseStatusLabel:SetText("Status: Searching in ChickenBodies (" .. tostring(checkedCount) .. " items checked)...")
						end
					end
				end
			end)

			task.wait(CONFIG.goldenGooseTeleportInterval or 3)
		end
	end)
end

local function stopAll()
	CONFIG.enabled = false
	_G.__AutoFarmRebirthStop = true
	_G.__AutoFarmRebirthRunning = false
	_G.__GoldenGooseTrackerActive = false
	isLoopRunning = false
	sessionId = sessionId + 1
	trackerSessionId = trackerSessionId + 1
end

local function startLoops()
	if isLoopRunning then return end
	isLoopRunning = true
	
	CONFIG.enabled = true
	_G.__AutoFarmRebirthStop = false
	_G.__AutoFarmRebirthRunning = true
	
	sessionId = sessionId + 1
	local currentSession = sessionId

	if CONFIG.autoTrackGoldenGoose then
		updateGoldenGooseTracker(true)
	end

	task.spawn(function()
		tryBuyAndUpgradeGenerators()
		tryCollectNestEggs()
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
			local uiReady = isRebirthReadyFromUI()

			if uiReady == true then
				-- 1. Stop tower & exit/surrender immediately so player comes down
				safeInvoke("TowerSurrender")
				task.wait(0.5)

				-- 2. Once down, stop doing everything else and spam Rebirth until bar color turns to 0, 57, 89
				while CONFIG.enabled and not _G.__AutoFarmRebirthStop and sessionId == currentSession do
					local currentState = isRebirthReadyFromUI()
					if currentState == false then
						-- Bar turned into 0, 57, 89 (Not ready) -> Rebirth success!
						break
					end

					-- Fire Rebirth remotes repeatedly
					safeInvoke("Rebirth")
					if okReq and CoreRemotes and CoreRemotes.defs and CoreRemotes.defs.Rebirth then
						pcall(function() CoreRemotes.invoke(CoreRemotes.defs.Rebirth) end)
					end
					task.wait(0.2)
				end

				-- 3. Post-Rebirth milestone claim & restart sequence
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
			else
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
			end

			if not smartWait(CONFIG.rebirthCheckInterval, currentSession) then break end
		end
		if sessionId == currentSession then
			isLoopRunning = false
			_G.__AutoFarmRebirthRunning = false
		end
	end)

	-- 5. Loop Auto Collect Nest Eggs
	task.spawn(function()
		while CONFIG.enabled and not _G.__AutoFarmRebirthStop and sessionId == currentSession do
			if CONFIG.autoCollectNestEggs then
				tryCollectNestEggs()
			end
			if not smartWait(CONFIG.nestEggCheckInterval or 3, currentSession) then break end
		end
	end)
end

---------------------------------------------------------
-- 🎪 EVENT CARD & INFO LOGIC
---------------------------------------------------------
local function getEventInfo()
	local anchor = workspace:FindFirstChild("EventCardAnchor")
	if not anchor then return "No Event Anchor", "N/A", "N/A" end

	local eventCard = anchor:FindFirstChild("EventCard")
	if not eventCard then return "No Event Card", "N/A", "N/A" end

	for _, child in ipairs(eventCard:GetChildren()) do
		if child:IsA("GuiObject") or child:IsA("CanvasGroup") or child.Name:find("@") or child.Name:find("idle") or child.Name:find("active") then
			-- Name Label (e.g. "CHICKEN BOSS")
			local nameLabel = child:FindFirstChild("name", true)
			local eventName = (nameLabel and nameLabel:IsA("TextLabel") and nameLabel.Text ~= "" and nameLabel.Text) or "Unknown Event"

			-- Sub Label (e.g. "UPCOMING")
			local subLabel = child:FindFirstChild("sub", true)
			local eventSub = (subLabel and subLabel:IsA("TextLabel") and subLabel.Text ~= "" and subLabel.Text) or "N/A"

			-- Time Label (e.g. time.label -> "3:32")
			local timeObj = child:FindFirstChild("time", true)
			local eventTime = "N/A"
			if timeObj then
				if timeObj:IsA("TextLabel") and timeObj.Text ~= "" then
					eventTime = timeObj.Text
				else
					local labelInTime = timeObj:FindFirstChild("label", true) or timeObj:FindFirstChildWhichIsA("TextLabel", true)
					if labelInTime and labelInTime:IsA("TextLabel") and labelInTime.Text ~= "" then
						eventTime = labelInTime.Text
					end
				end
			end

			return eventName, eventSub, eventTime
		end
	end

	return "No Active Event", "N/A", "N/A"
end

---------------------------------------------------------
-- OBSIDIAN UI SETUP
---------------------------------------------------------
local Window = Library:CreateWindow({
	Title = "Grow a Chicken Fighter",
	Footer = "Powered by Lilsky1",
	NotifySide = "Right",
	ShowCustomCursor = true,
})

local Tabs = {
	Main = Window:AddTab("Auto Farm", "user"),
	Event = Window:AddTab("Event", "sparkles"),
	AntiAFK = Window:AddTab("Anti AFK", "shield"),
	["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

-- TAB 1: Main Automation & Event Controls
local MainLeftBox = Tabs.Main:AddLeftGroupbox("Feeder Automation")

MainLeftBox:AddToggle("AutoFeeder", {
	Text = "Buy Feeder & Upgrade",
	Default = true,
	Tooltip = "Automates feeder slot purchases, upgrades, and coop expansion.",
	Callback = function(Value)
		CONFIG.autoUpgrade = Value
	end,
})

MainLeftBox:AddToggle("UpgradeAllAtOnce", {
	Text = "Upgrade All Feeders",
	Default = false,
	Tooltip = "OFF: Upgrades generators sequentially 1-by-1 to max level.\nON: Upgrades all unlocked generators simultaneously.",
	Callback = function(Value)
		CONFIG.upgradeAllAtOnce = Value
	end,
})

MainLeftBox:AddSlider("MaxGenSlider", {
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

local MainRightBox = Tabs.Main:AddRightGroupbox("Tower & Rebirth")

MainRightBox:AddToggle("MasterAutoFarm", {
	Text = "Auto Rebirth & Tower",
	Default = true,
	Tooltip = "Master switch for automated tower climbs, rebirths, and feeder loops.",
	Callback = function(Value)
		if Value then
			startLoops()
			Library:Notify("Auto Rebirth & Tower Enabled", 3)
		else
			stopAll()
			Library:Notify("Auto Rebirth & Tower Disabled", 3)
		end
	end,
})

local RebirthStatusLabel = MainRightBox:AddLabel("Status: Loading...")

-- Live auto-refresh loop for Rebirth Status Label
task.spawn(function()
	while true do
		task.wait(0.5)
		if _G.__AutoFarmRebirthStop then break end
		pcall(function()
			if RebirthStatusLabel then
				if RebirthStatusLabel.TextLabel then
					RebirthStatusLabel.TextLabel.RichText = true
				end

				local readyState = isRebirthReadyFromUI()
				if readyState == true then
					RebirthStatusLabel:SetText('Status: <font color="#00FF7F"><b>🟢 READY TO REBIRTH</b></font>')
				elseif readyState == false then
					RebirthStatusLabel:SetText('Status: <font color="#FF4D4D"><b>🔴 NOT READY</b></font>')
				else
					RebirthStatusLabel:SetText('Status: <font color="#AAAAAA"><b>⚪ SEARCHING UI...</b></font>')
				end
			end
		end)
	end
end)

MainRightBox:AddToggle("AutoIncubator", {
	Text = "Auto Claim Incubator",
	Default = true,
	Tooltip = "Automatically claims finished eggs from the incubator.",
	Callback = function(Value)
		CONFIG.autoClaimIncubator = Value
	end,
})

MainRightBox:AddToggle("AutoCollectNestEggs", {
	Text = "Auto Collect Nest Eggs",
	Default = true,
	Tooltip = "Automatically collects nest eggs in workspace.NestEggs that belong to your player UserId.",
	Callback = function(Value)
		CONFIG.autoCollectNestEggs = Value
	end,
})

MainRightBox:AddDivider()

MainRightBox:AddButton({
	Text = "❌ Kill Script & Destroy UI",
	Func = function()
		stopAll()
		Library:Unload()
	end,
	Tooltip = "Halts all automation threads and unloads the UI.",
})

-- TAB 2: Event Information & Controls
local EventLeftBox = Tabs.Event:AddLeftGroupbox("Event Status & Countdown")

local EventNameLabel = EventLeftBox:AddLabel("Event: Loading...")
local EventSubLabel = EventLeftBox:AddLabel("Status: Loading...")
local EventTimeLabel = EventLeftBox:AddLabel("Time Until Start: Loading...")

EventLeftBox:AddDivider()

EventLeftBox:AddButton({
	Text = "🔄 Refresh Event Info",
	Func = function()
		local name, sub, timeStr = getEventInfo()
		EventNameLabel:SetText("Event: " .. name)
		EventSubLabel:SetText("Status: " .. sub)
		EventTimeLabel:SetText("Time Until Start: " .. timeStr)
		Library:Notify("Event Info Refreshed", 2)
	end,
	Tooltip = "Manually updates event information from Workspace.",
})

-- Live auto-refresh loop for Event Info
task.spawn(function()
	while true do
		task.wait(1)
		if _G.__AutoFarmRebirthStop then break end
		pcall(function()
			if EventNameLabel and EventSubLabel and EventTimeLabel then
				local name, sub, timeStr = getEventInfo()
				EventNameLabel:SetText("Event: " .. name)
				EventSubLabel:SetText("Status: " .. sub)
				EventTimeLabel:SetText("Time Until Start: " .. timeStr)
			end
		end)
	end
end)

local EventRightBox = Tabs.Event:AddRightGroupbox("Golden Goose Tracker & Attack")

EventRightBox:AddToggle("AutoTrackGoldenGoose", {
	Text = "Golden Goose Tracker",
	Default = false,
	Tooltip = "Strictly targets and hovers directly above active Golden Goose (GooseDamagePodium / ovName=Golden Goose).",
	Callback = function(Value)
		CONFIG.autoTrackGoldenGoose = Value
		updateGoldenGooseTracker(Value)
		if Value then
			Library:Notify("Golden Goose Tracker: Active", 2)
		else
			Library:Notify("Golden Goose Tracker: Stopped", 2)
		end
	end,
})

EventRightBox:AddToggle("AutoAttackGoldenGoose", {
	Text = "Auto Attack Golden Goose",
	Default = true,
	Tooltip = "Automatically sends chickens to attack Golden Goose on arena ('chaos') while hovering.",
	Callback = function(Value)
		CONFIG.autoAttackGoldenGoose = Value
	end,
})

EventRightBox:AddSlider("GooseHoverHeightSlider", {
	Text = "Hover Distance",
	Default = 10,
	Min = 4,
	Max = 35,
	Rounding = 0,
	Compact = false,
	Tooltip = "Adjust vertical hover height above Golden Goose.",
	Callback = function(Value)
		CONFIG.goldenGooseHoverHeight = math.floor(Value)
	end,
})

GoldenGooseStatusLabel = EventRightBox:AddLabel("Status: Tracker Disabled")

EventRightBox:AddDivider()

EventRightBox:AddButton({
	Text = "📍 Teleport to Golden Goose",
	Func = function()
		local npc, root = getTargetGoldenGoose()
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")

		if root and hrp then
			hrp.CFrame = CFrame.new(root.Position + Vector3.new(0, CONFIG.goldenGooseHoverHeight, 0))
			local name = npc:GetAttribute("ovName") or npc.Name
			Library:Notify("Teleported to " .. tostring(name), 3)
		else
			Library:Notify("Golden Goose not found in Workspace", 3)
		end
	end,
	Tooltip = "Instantly teleports above active Golden Goose target.",
})

-- TAB 3: Anti AFK Controls
local AntiAFKLeftBox = Tabs.AntiAFK:AddLeftGroupbox("AFK Protection")

AntiAFKLeftBox:AddToggle("EnableAntiAFKToggle", {
	Text = "Enable Anti-AFK",
	Default = true,
	Tooltip = "Simulates human walking forward 3 studs & back every 10 minutes to prevent 20-min AFK disconnects.",
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
	Text = "Walk Interval (Minutes)",
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

local AntiAFKRightBox = Tabs.AntiAFK:AddRightGroupbox("Testing")

AntiAFKRightBox:AddButton({
	Text = "🚶 Test Walk Simulation",
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

-- TAB 4: UI Settings
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