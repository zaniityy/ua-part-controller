local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- State
local selectMode = false
local selectedParts = {}
local highlights = {}
local firingActive = false
local firingParts = {}
local targetRoot = nil
local PULL_STRENGTH = 100
local STOP_DISTANCE = 5

-- Mode: "teleport" or "orbit" or "fling" or "bring"
local currentMode = "teleport"
local ORBIT_RADIUS = 10
local ORBIT_SPEED = 3
local orbitAngle = 0

-- Fling mode settings
local FLING_SPIN_SPEED = 100
local FLING_SPIN_DURATION = 1.5
local flingStartTime = 0

-- Movement method: "velocity" or "weld"
local movementMethod = "velocity"
local activeWelds = {}

-- Check if part is unanchored
local function isUnanchored(part)
	if not part or not part:IsA("BasePart") then return false end
	if part.Anchored then return false end
	
	for _, joint in pairs(part:GetJoints()) do
		if joint:IsA("Weld") or joint:IsA("WeldConstraint") then
			local other = joint.Part0 == part and joint.Part1 or joint.Part0
			if other and other.Anchored then
				return false
			end
		end
	end
	
	return true
end

-- Check if local player has network ownership of a part
local function isNetworkOwned(part)
	if not part or not part:IsA("BasePart") then return false end
	
	local success, owner = pcall(function()
		return part:GetNetworkOwner()
	end)
	
	if success then
		return owner == player
	end
	
	-- If GetNetworkOwner fails, fallback to checking if we can move it
	-- Parts near the player are usually network owned
	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			local distance = (part.Position - root.Position).Magnitude
			return distance < 200 -- Approximate network ownership range
		end
	end
	
	return false
end

-- Check if part is moveable (unanchored AND network owned)
local function isMoveable(part)
	return isUnanchored(part) and isNetworkOwned(part)
end

-- Check if a model has any unanchored parts
local function hasUnanchoredParts(model)
	for _, part in pairs(model:GetDescendants()) do
		if isUnanchored(part) then
			return true
		end
	end
	return false
end

-- Get the top-level model or the part itself
-- Smart selection: if parent has anchored parts, find the highest unanchored-only group
local function getSelectableObject(part)
	if not part then return nil end
	
	-- Walk up to find the top model (but not workspace)
	local topModel = part
	while topModel.Parent and topModel.Parent ~= workspace and topModel.Parent:IsA("Model") do
		topModel = topModel.Parent
	end
	
	-- If we found a model, check if it has any anchored parts
	if topModel:IsA("Model") then
		local hasAnchored = false
		for _, child in pairs(topModel:GetDescendants()) do
			if child:IsA("BasePart") and child.Anchored then
				hasAnchored = true
				break
			end
		end
		
		-- If no anchored parts, return the whole model
		if not hasAnchored then
			return topModel
		end
		
		-- Parent has anchored parts - find the best sub-group to select
		-- Walk up from the clicked part and find the highest parent that has NO anchored parts
		local current = part
		local bestGroup = part -- Default to just the part
		
		while current and current ~= topModel and current.Parent ~= workspace do
			local parentHasAnchored = false
			
			if current:IsA("Model") then
				for _, child in pairs(current:GetDescendants()) do
					if child:IsA("BasePart") and child.Anchored then
						parentHasAnchored = true
						break
					end
				end
				
				if not parentHasAnchored then
					bestGroup = current
				end
			end
			
			current = current.Parent
		end
		
		return bestGroup
	end
	
	return part
end

-- Get all unanchored parts from an object (model or single part)
local function getUnanchoredParts(obj)
	local parts = {}
	if obj:IsA("BasePart") and isUnanchored(obj) then
		table.insert(parts, obj)
	elseif obj:IsA("Model") then
		for _, part in pairs(obj:GetDescendants()) do
			if isUnanchored(part) then
				table.insert(parts, part)
			end
		end
	end
	return parts
end

-- Find player by partial name/display name
local function findPlayer(query)
	query = query:lower()
	for _, p in pairs(Players:GetPlayers()) do
		if p.Name:lower():sub(1, #query) == query or p.DisplayName:lower():sub(1, #query) == query then
			return p
		end
	end
	return nil
end

-- Add highlight to part
local function addHighlight(part)
	local highlight = Instance.new("Highlight")
	highlight.Adornee = part
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.5
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = 0
	highlight.Parent = part
	return highlight
end

-- Remove highlight from part
local function removeHighlight(part)
	if highlights[part] then
		highlights[part]:Destroy()
		highlights[part] = nil
	end
end

-- Clear all selections
local function clearSelections()
	-- Destroy all highlights first
	for part, highlight in pairs(highlights) do
		if highlight and highlight.Parent then
			highlight:Destroy()
		end
	end
	-- Then clear the tables
	selectedParts = {}
	highlights = {}
end

-- Check if object is a player character
local function isPlayerCharacter(obj)
	for _, p in pairs(Players:GetPlayers()) do
		if p.Character and (obj == p.Character or obj:IsDescendantOf(p.Character)) then
			return true
		end
	end
	return false
end

-- Toggle object selection (model or part)
local function toggleObjectSelection(obj)
	-- Don't select player characters
	if isPlayerCharacter(obj) then
		return
	end
	
	if selectedParts[obj] then
		selectedParts[obj] = nil
		removeHighlight(obj)
	else
		-- Only select if it has unanchored parts
		local unanchoredParts = getUnanchoredParts(obj)
		if #unanchoredParts > 0 then
			selectedParts[obj] = true
			highlights[obj] = addHighlight(obj)
		end
	end
end

-- Create GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PartLauncherGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 200, 0, 295)
mainFrame.Position = UDim2.new(0, 10, 0.5, -147)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = mainFrame

-- Close button (red dot)
local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.new(0, 20, 0, 20)
closeButton.Position = UDim2.new(1, -25, 0, 5)
closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeButton.BorderSizePixel = 0
closeButton.Text = ""
closeButton.Parent = mainFrame

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(1, 0)
closeCorner.Parent = closeButton

closeButton.MouseButton1Click:Connect(function()
	screenGui:Destroy()
end)

-- Make GUI draggable
local dragging = false
local dragInput
local dragStart
local startPos

mainFrame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = mainFrame.Position
		
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

mainFrame.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input == dragInput and dragging then
		local delta = input.Position - dragStart
		mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "UA Part Controller"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 16
title.Font = Enum.Font.GothamBold
title.Parent = mainFrame

local targetInput = Instance.new("TextBox")
targetInput.Name = "TargetInput"
targetInput.Size = UDim2.new(1, -20, 0, 30)
targetInput.Position = UDim2.new(0, 10, 0, 35)
targetInput.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
targetInput.BorderSizePixel = 0
targetInput.PlaceholderText = "Target name..."
targetInput.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
targetInput.Text = ""
targetInput.TextColor3 = Color3.new(1, 1, 1)
targetInput.TextSize = 14
targetInput.Font = Enum.Font.Gotham
targetInput.Parent = mainFrame

local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 4)
inputCorner.Parent = targetInput

local selectButton = Instance.new("TextButton")
selectButton.Name = "SelectButton"
selectButton.Size = UDim2.new(1, -20, 0, 30)
selectButton.Position = UDim2.new(0, 10, 0, 70)
selectButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
selectButton.BorderSizePixel = 0
selectButton.Text = "Select Part: OFF"
selectButton.TextColor3 = Color3.new(1, 1, 1)
selectButton.TextSize = 14
selectButton.Font = Enum.Font.GothamBold
selectButton.Parent = mainFrame

local selectCorner = Instance.new("UICorner")
selectCorner.CornerRadius = UDim.new(0, 4)
selectCorner.Parent = selectButton

local fireButton = Instance.new("TextButton")
fireButton.Name = "FireButton"
fireButton.Size = UDim2.new(0.5, -15, 0, 35)
fireButton.Position = UDim2.new(0, 10, 0, 105)
fireButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
fireButton.BorderSizePixel = 0
fireButton.Text = "FIRE!!!"
fireButton.TextColor3 = Color3.new(1, 1, 1)
fireButton.TextSize = 18
fireButton.Font = Enum.Font.GothamBlack
fireButton.Parent = mainFrame

local fireCorner = Instance.new("UICorner")
fireCorner.CornerRadius = UDim.new(0, 4)
fireCorner.Parent = fireButton

local stopButton = Instance.new("TextButton")
stopButton.Name = "StopButton"
stopButton.Size = UDim2.new(0.5, -15, 0, 35)
stopButton.Position = UDim2.new(0.5, 5, 0, 105)
stopButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
stopButton.BorderSizePixel = 0
stopButton.Text = "STOP"
stopButton.TextColor3 = Color3.new(1, 1, 1)
stopButton.TextSize = 18
stopButton.Font = Enum.Font.GothamBlack
stopButton.Parent = mainFrame

local stopCorner = Instance.new("UICorner")
stopCorner.CornerRadius = UDim.new(0, 4)
stopCorner.Parent = stopButton

local unselectButton = Instance.new("TextButton")
unselectButton.Name = "UnselectButton"
unselectButton.Size = UDim2.new(1, -20, 0, 30)
unselectButton.Position = UDim2.new(0, 10, 0, 145)
unselectButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
unselectButton.BorderSizePixel = 0
unselectButton.Text = "Unselect All"
unselectButton.TextColor3 = Color3.new(1, 1, 1)
unselectButton.TextSize = 14
unselectButton.Font = Enum.Font.GothamBold
unselectButton.Parent = mainFrame

local unselectCorner = Instance.new("UICorner")
unselectCorner.CornerRadius = UDim.new(0, 4)
unselectCorner.Parent = unselectButton

local highlightAllButton = Instance.new("TextButton")
highlightAllButton.Name = "HighlightAllButton"
highlightAllButton.Size = UDim2.new(1, -20, 0, 30)
highlightAllButton.Position = UDim2.new(0, 10, 0, 180)
highlightAllButton.BackgroundColor3 = Color3.fromRGB(50, 100, 150)
highlightAllButton.BorderSizePixel = 0
highlightAllButton.Text = "Highlight All Unanchored"
highlightAllButton.TextColor3 = Color3.new(1, 1, 1)
highlightAllButton.TextSize = 12
highlightAllButton.Font = Enum.Font.GothamBold
highlightAllButton.Parent = mainFrame

local highlightAllCorner = Instance.new("UICorner")
highlightAllCorner.CornerRadius = UDim.new(0, 4)
highlightAllCorner.Parent = highlightAllButton

local modeButton = Instance.new("TextButton")
modeButton.Name = "ModeButton"
modeButton.Size = UDim2.new(0.5, -15, 0, 30)
modeButton.Position = UDim2.new(0, 10, 0, 215)
modeButton.BackgroundColor3 = Color3.fromRGB(150, 100, 50)
modeButton.BorderSizePixel = 0
modeButton.Text = "TELEPORT"
modeButton.TextColor3 = Color3.new(1, 1, 1)
modeButton.TextSize = 12
modeButton.Font = Enum.Font.GothamBold
modeButton.Parent = mainFrame

local modeCorner = Instance.new("UICorner")
modeCorner.CornerRadius = UDim.new(0, 4)
modeCorner.Parent = modeButton

local methodButton = Instance.new("TextButton")
methodButton.Name = "MethodButton"
methodButton.Size = UDim2.new(0.5, -15, 0, 30)
methodButton.Position = UDim2.new(0.5, 5, 0, 215)
methodButton.BackgroundColor3 = Color3.fromRGB(60, 120, 180)
methodButton.BorderSizePixel = 0
methodButton.Text = "VELOCITY"
methodButton.TextColor3 = Color3.new(1, 1, 1)
methodButton.TextSize = 12
methodButton.Font = Enum.Font.GothamBold
methodButton.Parent = mainFrame

local methodCorner = Instance.new("UICorner")
methodCorner.CornerRadius = UDim.new(0, 4)
methodCorner.Parent = methodButton

local methodLabel = Instance.new("TextLabel")
methodLabel.Name = "MethodLabel"
methodLabel.Size = UDim2.new(1, -20, 0, 20)
methodLabel.Position = UDim2.new(0, 10, 0, 250)
methodLabel.BackgroundTransparency = 1
methodLabel.Text = "BodyPos = Stronger physics pull"
methodLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
methodLabel.TextSize = 10
methodLabel.Font = Enum.Font.Gotham
methodLabel.Parent = mainFrame

-- Toggle mode
modeButton.MouseButton1Click:Connect(function()
	if currentMode == "teleport" then
		currentMode = "orbit"
		modeButton.Text = "ORBIT"
		modeButton.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
	elseif currentMode == "orbit" then
		currentMode = "fling"
		modeButton.Text = "FLING"
		modeButton.BackgroundColor3 = Color3.fromRGB(200, 150, 50)
	elseif currentMode == "fling" then
		currentMode = "bring"
		modeButton.Text = "FOLLOW"
		modeButton.BackgroundColor3 = Color3.fromRGB(50, 150, 100)
	else
		currentMode = "teleport"
		modeButton.Text = "TELEPORT"
		modeButton.BackgroundColor3 = Color3.fromRGB(150, 100, 50)
	end
end)

-- Toggle movement method (2 options)
methodButton.MouseButton1Click:Connect(function()
	if movementMethod == "velocity" then
		movementMethod = "weld"
		methodButton.Text = "BODYPOS"
		methodButton.BackgroundColor3 = Color3.fromRGB(50, 180, 100)
		methodLabel.Text = "BodyPos = Stronger physics pull"
	else
		movementMethod = "velocity"
		methodButton.Text = "VELOCITY"
		methodButton.BackgroundColor3 = Color3.fromRGB(60, 120, 180)
		methodLabel.Text = "Velocity = Standard physics"
	end
end)

-- Helper function to clean up all active body movers
local function cleanupWelds()
	for part, data in pairs(activeWelds) do
		if data then
			if data.bodyPos and data.bodyPos.Parent then
				data.bodyPos:Destroy()
			end
			if data.bodyAV and data.bodyAV.Parent then
				data.bodyAV:Destroy()
			end
		end
	end
	activeWelds = {}
end

-- Helper function to set up BodyPosition for a part (replicates via physics)
local function setupBodyMover(part, targetPos, stabilize)
	-- Remove existing body mover if any
	if activeWelds[part] then
		if activeWelds[part].bodyPos and activeWelds[part].bodyPos.Parent then
			activeWelds[part].bodyPos:Destroy()
		end
		if activeWelds[part].bodyAV and activeWelds[part].bodyAV.Parent then
			activeWelds[part].bodyAV:Destroy()
		end
	end
	
	-- Create BodyPosition to pull part toward target
	local bodyPos = Instance.new("BodyPosition")
	bodyPos.Position = targetPos
	bodyPos.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bodyPos.P = 25000 -- Stronger pull
	bodyPos.D = 1000  -- Higher dampening
	bodyPos.Parent = part
	
	local bodyAV = nil
	if stabilize ~= false then
		-- Create BodyAngularVelocity to stabilize rotation (stop tumbling)
		bodyAV = Instance.new("BodyAngularVelocity")
		bodyAV.AngularVelocity = Vector3.new(0, 0, 0)
		bodyAV.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
		bodyAV.P = 3000
		bodyAV.Parent = part
	end
	
	activeWelds[part] = {
		bodyPos = bodyPos,
		bodyAV = bodyAV
	}
	
	return bodyPos
end

-- Helper function to update BodyPosition target
local function updateBodyMover(part, targetPos)
	local data = activeWelds[part]
	if data and data.bodyPos and data.bodyPos.Parent then
		data.bodyPos.Position = targetPos
	end
end

-- Helper function to ensure we have a body mover and update it
local function movePartWithBodyMover(part, targetPos, stabilize)
	if not activeWelds[part] or not activeWelds[part].bodyPos or not activeWelds[part].bodyPos.Parent then
		setupBodyMover(part, targetPos, stabilize)
	else
		updateBodyMover(part, targetPos)
	end
end

-- Helper function to touch parts periodically to maintain network ownership
local function touchPart(part)
	local character = player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	
	-- Slightly nudge the part's velocity to assert ownership
	local currentVel = part.Velocity
	part.Velocity = currentVel + Vector3.new(0, 0.001, 0)
end

-- Toggle select mode
selectButton.MouseButton1Click:Connect(function()
	selectMode = not selectMode
	if selectMode then
		selectButton.Text = "Select Part: ON"
		selectButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
	else
		selectButton.Text = "Select Part: OFF"
		selectButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	end
end)

-- Unselect all button
unselectButton.MouseButton1Click:Connect(function()
	clearSelections()
	print("Cleared all selections")
end)

-- Highlight all unanchored parts button
highlightAllButton.MouseButton1Click:Connect(function()
	local count = 0
	for _, obj in pairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") and isMoveable(obj) and not isPlayerCharacter(obj) then
			local selectableObj = getSelectableObject(obj)
			if selectableObj and not selectedParts[selectableObj] then
				local unanchoredParts = getUnanchoredParts(selectableObj)
				if #unanchoredParts > 0 then
					selectedParts[selectableObj] = true
					highlights[selectableObj] = addHighlight(selectableObj)
					count = count + 1
				end
			end
		end
	end
	print("Highlighted " .. count .. " moveable objects")
end)

-- Fire button
fireButton.MouseButton1Click:Connect(function()
	local targetName = targetInput.Text
	if targetName == "" then
		warn("Enter a target name!")
		return
	end
	
	local targetPlayer = findPlayer(targetName)
	if not targetPlayer then
		warn("Player not found!")
		return
	end
	
	local targetChar = targetPlayer.Character
	if not targetChar then
		warn("Target has no character!")
		return
	end
	
	local foundRoot = targetChar:FindFirstChild("HumanoidRootPart")
	if not foundRoot then
		warn("Target has no HumanoidRootPart!")
		return
	end
	
	-- Store target root for heartbeat
	targetRoot = foundRoot
	
	-- Teleport all selected parts to target
	local count = 0
	local partsToFire = {}
	
	for obj, _ in pairs(selectedParts) do
		if obj and obj:IsDescendantOf(workspace) then
			local parts = getUnanchoredParts(obj)
			for _, part in pairs(parts) do
				table.insert(partsToFire, part)
				count = count + 1
			end
		end
	end
	
	if count == 0 then
		warn("No parts selected!")
		return
	end
	
	-- Start pulling parts toward target
	firingParts = partsToFire
	firingActive = true
	
	-- Record start time for fling mode
	if currentMode == "fling" then
		flingStartTime = tick()
	end
	
	print("Firing " .. count .. " parts at " .. targetPlayer.Name)
end)

-- Stop button
stopButton.MouseButton1Click:Connect(function()
	if firingActive then
		firingActive = false
		firingParts = {}
		targetRoot = nil
		orbitAngle = 0
		flingStartTime = 0
		cleanupWelds()
		
		print("Stopped firing")
	end
end)

-- Heartbeat to pull parts toward target
RunService.Heartbeat:Connect(function(dt)
	if firingActive and targetRoot and targetRoot.Parent then
		local partsToRemove = {}
		
		if currentMode == "teleport" then
			-- TELEPORT MODE: Pull parts toward target
			
			for i, part in pairs(firingParts) do
				if part and part:IsDescendantOf(workspace) and isUnanchored(part) then
					local direction = (targetRoot.Position - part.Position).Unit
					local distance = (targetRoot.Position - part.Position).Magnitude
					
					if distance <= STOP_DISTANCE then
						table.insert(partsToRemove, i)
						-- Clean up weld for this part
						if activeWelds[part] then
							activeWelds[part]:Destroy()
							activeWelds[part] = nil
						end
					else
						if movementMethod == "weld" then
							-- BODYMOVER METHOD: Use BodyPosition for physics-based replication
							movePartWithBodyMover(part, targetRoot.Position)
							touchPart(part) -- Help maintain network ownership
						else
							-- VELOCITY METHOD: Use Velocity to physically move it toward target
							part.Velocity = direction * PULL_STRENGTH
						end
					end
				else
					table.insert(partsToRemove, i)
					-- Clean up weld for removed part
					if activeWelds[part] then
						activeWelds[part]:Destroy()
						activeWelds[part] = nil
					end
				end
			end
			
			-- Remove parts that arrived or were destroyed
			for j = #partsToRemove, 1, -1 do
				table.remove(firingParts, partsToRemove[j])
			end
			
			-- Stop when all parts arrived
			if #firingParts == 0 then
				firingActive = false
				targetRoot = nil
				cleanupWelds()
			end
		elseif currentMode == "orbit" then
			-- ORBIT MODE: Spin parts in a circle around the target
			
			orbitAngle = orbitAngle + (ORBIT_SPEED * dt)
			
			local numParts = #firingParts
			for i, part in pairs(firingParts) do
				if part and part:IsDescendantOf(workspace) and isUnanchored(part) then
					-- Calculate the angle offset for each part to spread them evenly
					local angleOffset = (i - 1) * (2 * math.pi / numParts)
					local partAngle = orbitAngle + angleOffset
					
					-- Calculate desired orbit position
					local targetPos = targetRoot.Position
					local orbitX = targetPos.X + math.cos(partAngle) * ORBIT_RADIUS
					local orbitY = targetPos.Y
					local orbitZ = targetPos.Z + math.sin(partAngle) * ORBIT_RADIUS
					local desiredPos = Vector3.new(orbitX, orbitY, orbitZ)
					
					local distance = (part.Position - targetPos).Magnitude
					
					if movementMethod == "weld" then
						-- BODYMOVER METHOD: Use BodyPosition for physics-based replication
						movePartWithBodyMover(part, desiredPos)
						touchPart(part)
					else
						-- VELOCITY METHOD: Use velocity to push part toward its orbit position
						local toOrbit = (desiredPos - part.Position)
						local orbitDistance = toOrbit.Magnitude
						
						if orbitDistance > 0.1 then
							-- Stronger velocity when further from orbit position
							local strength = math.min(orbitDistance * 10, PULL_STRENGTH * 2)
							part.Velocity = toOrbit.Unit * strength
						else
							-- Add tangential velocity to keep spinning
							local tangentX = -math.sin(partAngle) * ORBIT_SPEED * ORBIT_RADIUS
							local tangentZ = math.cos(partAngle) * ORBIT_SPEED * ORBIT_RADIUS
							part.Velocity = Vector3.new(tangentX, 0, tangentZ)
						end
					end
				else
					table.insert(partsToRemove, i)
					if activeWelds[part] then
						activeWelds[part]:Destroy()
						activeWelds[part] = nil
					end
				end
			end
			
			-- Remove destroyed parts
			for j = #partsToRemove, 1, -1 do
				table.remove(firingParts, partsToRemove[j])
			end
			
			-- Stop when all parts are gone
			if #firingParts == 0 then
				firingActive = false
				targetRoot = nil
				orbitAngle = 0
				cleanupWelds()
			end
		elseif currentMode == "fling" then
			-- FLING MODE: Spin parts then teleport to player
			
			local elapsed = tick() - flingStartTime
			local spinPhase = elapsed < FLING_SPIN_DURATION
			
			for i, part in pairs(firingParts) do
				if part and part:IsDescendantOf(workspace) and isUnanchored(part) then
					-- ALWAYS apply extreme rotation in fling mode for maximum chaos
					local spinX = math.random(-FLING_SPIN_SPEED, FLING_SPIN_SPEED)
					local spinY = math.random(-FLING_SPIN_SPEED, FLING_SPIN_SPEED)
					local spinZ = math.random(-FLING_SPIN_SPEED, FLING_SPIN_SPEED)
					part.RotVelocity = Vector3.new(spinX, spinY, spinZ)

					if spinPhase then
						-- Spin phase: just gather chaos
						local chaos = Vector3.new(
							math.random(-20, 20),
							math.random(10, 30),
							math.random(-20, 20)
						)
						part.Velocity = chaos
					else
						-- Fling phase: launch at target
						local distance = (targetRoot.Position - part.Position).Magnitude
						local direction = (targetRoot.Position - part.Position).Unit
						
						if movementMethod == "weld" then
							-- BODYMOVER METHOD: Use BodyPosition
							movePartWithBodyMover(part, targetRoot.Position, false)
							touchPart(part)
						else
							-- VELOCITY METHOD
							-- Launch toward target
							part.Velocity = direction * PULL_STRENGTH * 1.5
						end
						
						-- NO STOP DISTANCE CHECK for fling mode - keep attacking!
					end
				else
					table.insert(partsToRemove, i)
					if activeWelds[part] then
						activeWelds[part]:Destroy()
						activeWelds[part] = nil
					end
				end
			end
			
			-- Remove destroyed or arrived parts
			for j = #partsToRemove, 1, -1 do
				table.remove(firingParts, partsToRemove[j])
			end
			
			-- Stop when all parts are gone
			if #firingParts == 0 then
				firingActive = false
				targetRoot = nil
				flingStartTime = 0
				cleanupWelds()
			end
		else
			-- BRING MODE: Continuously pull parts toward target and hold them there
			
			for i, part in pairs(firingParts) do
				if part and part:IsDescendantOf(workspace) and isUnanchored(part) then
					local targetPos = targetRoot.Position
					local partPos = part.Position
					local direction = (targetPos - partPos).Unit
					local distance = (targetPos - partPos).Magnitude
					
					if movementMethod == "weld" then
						-- BODYMOVER METHOD: Use BodyPosition for physics-based replication
						local followPos = targetPos + Vector3.new(0, 2, 0) -- Slightly above target
						movePartWithBodyMover(part, followPos)
						touchPart(part)
					else
						-- VELOCITY METHOD: Strong constant pull
						if distance > 2 then
							-- Pull hard toward target
							part.Velocity = direction * PULL_STRENGTH * 2
						else
							-- When very close, match target velocity to stay with them
							part.Velocity = targetRoot.Velocity + direction * 20
						end
					end
				else
					table.insert(partsToRemove, i)
					if activeWelds[part] then
						activeWelds[part]:Destroy()
						activeWelds[part] = nil
					end
				end
			end
			
			-- Remove destroyed parts
			for j = #partsToRemove, 1, -1 do
				table.remove(firingParts, partsToRemove[j])
			end
			
			-- Stop when all parts are gone
			if #firingParts == 0 then
				firingActive = false
				targetRoot = nil
				cleanupWelds()
			end
		end
	elseif firingActive then
		-- Target lost
		firingActive = false
		firingParts = {}
		targetRoot = nil
		orbitAngle = 0
		flingStartTime = 0
		cleanupWelds()
	end
end)

-- Click to select parts
mouse.Button1Down:Connect(function()
	if not selectMode then return end
	
	local target = mouse.Target
	if target then
		local obj = getSelectableObject(target)
		if obj then
			toggleObjectSelection(obj)
		end
	end
end)
