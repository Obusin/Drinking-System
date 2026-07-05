-- See my work @Rookstun for more stuff! You can support me by buying my UGC on the catalog. Thanks!

local SOCKET_SETTINGS_R15 = {
	head = {MaxFrictionTorque = 55, UpperAngle = 15, TwistLowerAngle = -25, TwistUpperAngle = 25}, 
	upperTorso = {MaxFrictionTorque = 100, UpperAngle = 30, TwistLowerAngle = -40, TwistUpperAngle = 40},  
	lowerTorso = {MaxFrictionTorque = 100, UpperAngle = 30, TwistLowerAngle = -180, TwistUpperAngle = 180},  
	upperArms = {MaxFrictionTorque = 100, UpperAngle = 35, TwistLowerAngle = -180, TwistUpperAngle = 180},  
	lowerArms = {MaxFrictionTorque = 100, UpperAngle = 0, TwistLowerAngle = -5, TwistUpperAngle = 160},  
	upperLegs = {MaxFrictionTorque = 100, UpperAngle = 30, TwistLowerAngle = -5, TwistUpperAngle = 20},  
	lowerLegs = {MaxFrictionTorque = 100, UpperAngle = 0, TwistLowerAngle = -45, TwistUpperAngle = 10},  
	handsFeets = {MaxFrictionTorque = 100, UpperAngle = 10, TwistLowerAngle = -45, TwistUpperAngle = 25},  
}

local function limbManager(limbName)
	local rigUpperArms = {"RightUpperArm", "LeftUpperArm"}
	local rigLowerArms = {"RightLowerArm", "LeftLowerArm"}
	local rigUpperLegs = {"RightUpperLeg", "LeftUpperLeg"}
	local rigLowerLegs = {"RightLowerLeg", "LeftLowerLeg"}
	local rigHandsFeets = {"RightHand", "LeftHand", "RightFoot", "LeftFoot"}
	if limbName == "Head" then 
		return "head"
	elseif limbName == "UpperTorso" then 
		return "upperTorso"
	elseif limbName == "LowerTorso" then 
		return "lowerTorso"
	elseif table.find(rigUpperArms, limbName) then
		return "upperArms"
	elseif table.find(rigLowerArms, limbName) then
		return "lowerArms"
	elseif table.find(rigUpperLegs, limbName) then
		return "upperLegs"
	elseif table.find(rigLowerLegs, limbName) then
		return "lowerLegs"
	elseif table.find(rigHandsFeets, limbName) then
		return "handsFeets"
	else 
		return nil
	end
end

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")

local a0 = Instance.new("Attachment")
local s0 = Instance.new("BallSocketConstraint")
local nc = Instance.new("NoCollisionConstraint")

local function addNoCollisionConstraint(part0, part1, parent) --Part0, to connect to Part1, Parent of collision instance. 
	-- Check for an existing constraint between the two parts
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("NoCollisionConstraint") and 
			((child.Part0 == part0 and child.Part1 == part1) or 
				(child.Part0 == part1 and child.Part1 == part0)) then
			return  -- Exit early — constraint already exists.
		end
	end

	-- Create and parent the new constraint
	local nc = Instance.new("NoCollisionConstraint")
	nc.Part0 = part0
	nc.Part1 = part1
	nc.Parent = parent
end

local function noCollideR15() 
	addNoCollisionConstraint(character.RightUpperLeg, character.LowerTorso, character.LowerTorso)
	addNoCollisionConstraint(character.RightLowerLeg, character.UpperTorso, character.UpperTorso)
	addNoCollisionConstraint(character.RightFoot, character.RightLowerLeg, character.RightLowerLeg)
	addNoCollisionConstraint(character.LeftFoot, character.LeftLowerLeg, character.LeftLowerLeg)
	addNoCollisionConstraint(character.LeftUpperLeg, character.UpperTorso, character.UpperTorso)
	addNoCollisionConstraint(character.LeftLowerLeg, character.LowerTorso, character.LowerTorso)
	addNoCollisionConstraint(character.LeftUpperLeg, character.RightUpperLeg, character.LeftUpperLeg)
	addNoCollisionConstraint(character.UpperTorso, character.LowerTorso, character.LowerTorso)
	addNoCollisionConstraint(character.UpperTorso, character.Head, character.Head)
	addNoCollisionConstraint(character.RightUpperArm, character.Head, character.Head)
	addNoCollisionConstraint(character.LeftUpperArm, character.Head, character.Head)
	addNoCollisionConstraint(character.RightLowerArm, character.Head, character.Head)
	addNoCollisionConstraint(character.LeftLowerArm, character.Head, character.Head)
	addNoCollisionConstraint(character.LeftHand, character.LeftUpperArm, character.LeftHand)
	addNoCollisionConstraint(character.RightHand, character.RightUpperArm, character.RightHand)
	addNoCollisionConstraint(character.LeftHand, character.UpperTorso, character.UpperTorso)
	addNoCollisionConstraint(character.LeftHand, character.LowerTorso, character.LowerTorso)
	addNoCollisionConstraint(character.RightHand, character.UpperTorso, character.UpperTorso)
	addNoCollisionConstraint(character.RightHand, character.LowerTorso, character.LowerTorso)
end

humanoid.AutomaticScalingEnabled = false	--Keep false on NPCs, and if must do all scaling via serverside.
humanoid.BreakJointsOnDeath = false
character.HumanoidRootPart.CanCollide = false
character.HumanoidRootPart.CollisionGroup = "Players"

for i,limb in ipairs(character:GetChildren()) do
	if limb:IsA("Accessory") then
		limb.Handle.CanCollide = false
		limb.Handle.CollisionGroup = "Players"
		limb.Handle.CanTouch = false
		limb.Handle.Massless = true
	end

	for i,motor6d in ipairs(limb:GetChildren()) do	
		if motor6d:IsA("Motor6D") and motor6D ~= "Root" then	--Getting motor6D joints as joints. Their parents are the parts. 

			local nc0 = nc:Clone()
			local socket = s0:Clone()
			local a1 = a0:Clone()
			local a2 = a0:Clone()

			a1.Parent = motor6d.Part0
			a2.Parent = motor6d.Part1
			a1.CFrame = motor6d.C0
			a2.CFrame = motor6d.C1

			motor6d.Parent.CollisionGroup = "Players"
			nc0.Part0 = motor6d.Part0
			nc0.Part1 = motor6d.Part1
			nc0.Parent = motor6d.Parent

			socket.Attachment0 = a1
			socket.Attachment1 = a2
			socket.LimitsEnabled = true
			socket.TwistLimitsEnabled = true
			socket.Parent = motor6d.Parent	--Joint parents are parts themselves. Assign parent of socket. 

			local limbMgr = limbManager(motor6d.Parent.Name)
			if limbMgr ~= nil then
			
			local limbDir = SOCKET_SETTINGS_R15[limbMgr]
				for key,value in pairs (limbDir) do
					if socket[key] then
						socket[key] = value
					end
				end
			end
		end	
	end
end

noCollideR15()

script:Destroy()