--!nocheck
--[[
  Auto Farm, Progressive Upgrade, Step-by-Step Expand Coop, Smart Tower & Rebirth
  (Dynamic Expand Coop per Generator Edition)
]]

-- ปิดการทำงานของสคริปต์เก่า
if _G.__AutoFarmRebirthRunning then
	_G.__AutoFarmRebirthStop = true
	_G.__AutoFarmRebirthRunning = false
	task.wait(0.3)
end
_G.__AutoFarmRebirthRunning = true
_G.__AutoFarmRebirthStop = false

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes", 5)

local CONFIG = {
	enabled = true,
	autoUpgrade = true,
	autoClaimIncubator = true,
	maxGenerators = 6,          -- ปรับใน UI ได้ 1 ถึง 6 เครื่อง
	upgradeInterval = 0.10,     -- จังหวะอัปเกรดเร็ว Turbo
	towerRestartInterval = 16,
	rebirthCheckInterval = 5,
	incubatorInterval = 180,
	cooldownBeforeTower = 6,
	cooldownAfterRebirth = 8,
}

local sessionId = 0
local isLoopRunning = false
local currentGeneratorTarget = 1

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
-- ONE-TIME REMOTE INITIALIZATION
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
	
	local remote = validRemotes[remoteName]
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

-- ระบบซื้อ, ขยายเล้าไก่ และอัปเกรด Feeder อัตโนมัติแบบทีละ 1 ลำดับ
local function tryBuyAndUpgradeGenerators()
	if not CONFIG.enabled or _G.__AutoFarmRebirthStop then return end

	if currentGeneratorTarget > CONFIG.maxGenerators then
		currentGeneratorTarget = CONFIG.maxGenerators
	end

	-- 1. ถ้าเป้าหมายคือเครื่องที่ 3 ขึ้นไป ให้ยิงขยายเล้าไก่ (ExpandCoop) เผื่อไว้เสมอ
	if currentGeneratorTarget >= 3 then
		safeInvoke("ExpandCoop")
	end

	-- 2. ยิงซื้อเปิดช่องเครื่องเป้าหมายปัจจุบัน
	if validRemotes["BuyGenerator"] then
		safeInvoke("BuyGenerator", currentGeneratorTarget)
	elseif validRemotes["PurchaseGenerator"] then
		safeInvoke("PurchaseGenerator", currentGeneratorTarget)
	end

	-- 3. Turbo Upgrade: ยิงอัปเกรดเครื่องปัจจุบันรัวๆ
	for _ = 1, 3 do
		local ok, res = safeInvoke("UpgradeGenerator", currentGeneratorTarget)

		-- ตรวจสอบว่าเครื่องนี้อัปเกรดจนเต็ม (Max Level) หรือยัง
		if ok and type(res) == "table" then
			if res.error and (string.find(tostring(res.error):lower(), "max") or string.find(tostring(res.error):lower(), "full")) then
				-- ถ้ายังไม่ถึงขีดจำกัดที่ตั้งไว้ใน UI ให้ขยับเป้าหมายไปเครื่องถัดไป
				if currentGeneratorTarget < CONFIG.maxGenerators then
					currentGeneratorTarget = currentGeneratorTarget + 1
					
					-- 🌟 ถ้าจะเริ่มทำเครื่องที่ 3 เป็นต้นไป ให้สั่งขยายเล้าไก่ทันที
					if currentGeneratorTarget >= 3 then
						safeInvoke("ExpandCoop")
					end
				end
				break
			end
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

	-- 1. Loop Auto Buy/Upgrade Feeder & Step-by-Step Expand Coop
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

	-- 4. Loop Rebirth
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

				-- รีเซ็ตเป้าหมายกลับไปเริ่มที่เครื่อง 1 เสมอ
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
-- NATIVE UI
---------------------------------------------------------
local parentGui = (gethui and gethui()) or CoreGui:FindFirstChild("RobloxGui") or LocalPlayer:WaitForChild("PlayerGui")

if parentGui:FindFirstChild("ChickenFarmHubUI") then
	parentGui.ChickenFarmHubUI:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ChickenFarmHubUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = parentGui

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 270, 0, 430)
MainFrame.Position = UDim2.new(0.05, 0, 0.2, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner", MainFrame)
UICorner.CornerRadius = UDim.new(0, 10)

local UIStroke = Instance.new("UIStroke", MainFrame)
UIStroke.Color = Color3.fromRGB(60, 60, 75)
UIStroke.Thickness = 1.5

local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1, -20, 0, 35)
Title.Position = UDim2.new(0, 10, 0, 5)
Title.BackgroundTransparency = 1
Title.Text = "🐔 Chicken Auto Hub (Max 6)"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 15
Title.TextXAlignment = Enum.TextXAlignment.Left

local Container = Instance.new("Frame", MainFrame)
Container.Size = UDim2.new(1, -20, 1, -45)
Container.Position = UDim2.new(0, 10, 0, 40)
Container.BackgroundTransparency = 1

local UIList = Instance.new("UIListLayout", Container)
UIList.Padding = UDim.new(0, 7)
UIList.SortOrder = Enum.SortOrder.LayoutOrder

local function createButton(text, bgColor, callback)
	local btn = Instance.new("TextButton", Container)
	btn.Size = UDim2.new(1, 0, 0, 34)
	btn.BackgroundColor3 = bgColor
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.GothamSemibold
	btn.TextSize = 13
	btn.BorderSizePixel = 0

	local corner = Instance.new("UICorner", btn)
	corner.CornerRadius = UDim.new(0, 6)

	btn.MouseButton1Click:Connect(callback)
	return btn
end

-- 1. Toggle Auto Farm
local toggleBtn
toggleBtn = createButton("🟢 ระบบ Auto Farm: เปิดอยู่", Color3.fromRGB(45, 140, 70), function()
	if CONFIG.enabled then
		stopAll()
		toggleBtn.Text = "🔴 ระบบ Auto Farm: ปิดอยู่"
		toggleBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
	else
		startLoops()
		toggleBtn.Text = "🟢 ระบบ Auto Farm: เปิดอยู่"
		toggleBtn.BackgroundColor3 = Color3.fromRGB(45, 140, 70)
	end
end)

-- 2. Toggle Auto Feeder
local feedBtn
feedBtn = createButton("🌽 Auto Feeder (ดันทีละเครื่อง): เปิด", Color3.fromRGB(50, 100, 160), function()
	CONFIG.autoUpgrade = not CONFIG.autoUpgrade
	if CONFIG.autoUpgrade then
		feedBtn.Text = "🌽 Auto Feeder (ดันทีละเครื่อง): เปิด"
		feedBtn.BackgroundColor3 = Color3.fromRGB(50, 100, 160)
	else
		feedBtn.Text = "🌽 Auto Feeder (ดันทีละเครื่อง): ปิด"
		feedBtn.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
	end
end)

-- 3. Toggle Auto Claim Incubator
local incBtn
incBtn = createButton("🥚 Auto Claim Incubator: เปิด", Color3.fromRGB(90, 60, 140), function()
	CONFIG.autoClaimIncubator = not CONFIG.autoClaimIncubator
	if CONFIG.autoClaimIncubator then
		incBtn.Text = "🥚 Auto Claim Incubator: เปิด"
		incBtn.BackgroundColor3 = Color3.fromRGB(90, 60, 140)
	else
		incBtn.Text = "🥚 Auto Claim Incubator: ปิด"
		incBtn.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
	end
end)

-- 4. ควบคุมจำนวนเครื่องให้อาหาร (1 - 6 เครื่อง)
local genSelectorFrame = Instance.new("Frame", Container)
genSelectorFrame.Size = UDim2.new(1, 0, 0, 36)
genSelectorFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
genSelectorFrame.BorderSizePixel = 0
Instance.new("UICorner", genSelectorFrame).CornerRadius = UDim.new(0, 6)

local minusBtn = Instance.new("TextButton", genSelectorFrame)
minusBtn.Size = UDim2.new(0, 35, 1, 0)
minusBtn.Position = UDim2.new(0, 0, 0, 0)
minusBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
minusBtn.Text = "➖"
minusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minusBtn.Font = Enum.Font.GothamBold
minusBtn.TextSize = 14
Instance.new("UICorner", minusBtn).CornerRadius = UDim.new(0, 6)

local countLabel = Instance.new("TextLabel", genSelectorFrame)
countLabel.Size = UDim2.new(1, -70, 1, 0)
countLabel.Position = UDim2.new(0, 35, 0, 0)
countLabel.BackgroundTransparency = 1
countLabel.Text = "ซื้อ/อัปเกรด: " .. CONFIG.maxGenerators .. " เครื่อง"
countLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
countLabel.Font = Enum.Font.GothamBold
countLabel.TextSize = 12

local plusBtn = Instance.new("TextButton", genSelectorFrame)
plusBtn.Size = UDim2.new(0, 35, 1, 0)
plusBtn.Position = UDim2.new(1, -35, 0, 0)
plusBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
plusBtn.Text = "➕"
plusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
plusBtn.Font = Enum.Font.GothamBold
plusBtn.TextSize = 14
Instance.new("UICorner", plusBtn).CornerRadius = UDim.new(0, 6)

minusBtn.MouseButton1Click:Connect(function()
	if CONFIG.maxGenerators > 1 then
		CONFIG.maxGenerators = CONFIG.maxGenerators - 1
		countLabel.Text = "ซื้อ/อัปเกรด: " .. CONFIG.maxGenerators .. " เครื่อง"
	end
end)

plusBtn.MouseButton1Click:Connect(function()
	if CONFIG.maxGenerators < 6 then
		CONFIG.maxGenerators = CONFIG.maxGenerators + 1
		countLabel.Text = "ซื้อ/อัปเกรด: " .. CONFIG.maxGenerators .. " เครื่อง"
	end
end)

-- 5. ปุ่ม Action
createButton("🥚 เก็บไข่ตู้ฟักทันที (Claim)", Color3.fromRGB(70, 60, 110), function()
	safeInvoke("IncubatorClaim")
end)

createButton("🚀 ส่งไก่ไป Tower ทันที", Color3.fromRGB(55, 55, 65), function()
	startTower(true, sessionId)
end)

createButton("🔄 ลอง Rebirth ทันที", Color3.fromRGB(55, 55, 65), function()
	tryRebirth()
end)

createButton("❌ ปิดสคริปต์ & ลบ UI", Color3.fromRGB(180, 45, 45), function()
	stopAll()
	ScreenGui:Destroy()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.RightShift then
		MainFrame.Visible = not MainFrame.Visible
	end
end)

startLoops()