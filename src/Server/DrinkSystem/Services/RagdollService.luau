local RagdollService = {}

type CharacterState = {
	Rigged: boolean,
	Motors: { Motor6D },
	Constraints: { BallSocketConstraint },
	CollisionParts: { BasePart },
	OriginalCollisions: { [BasePart]: boolean },
}

local characterStates: { [Model]: CharacterState } = {}

local function shouldRagdollMotor(motor: Motor6D): boolean
	if motor.Name == "RootJoint" then
		return false
	end

	local part0 = motor.Part0
	local part1 = motor.Part1
	if not part0 or not part1 then
		return false
	end

	return true
end

local function createConstraintForMotor(motor: Motor6D): BallSocketConstraint?
	local part0 = motor.Part0
	local part1 = motor.Part1
	if not part0 or not part1 then
		return nil
	end

	local attachment0 = Instance.new("Attachment")
	attachment0.Name = motor.Name .. "_RagdollA0"
	attachment0.CFrame = motor.C0
	attachment0.Parent = part0

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = motor.Name .. "_RagdollA1"
	attachment1.CFrame = motor.C1
	attachment1.Parent = part1

	local constraint = Instance.new("BallSocketConstraint")
	constraint.Name = motor.Name .. "_Ragdoll"
	constraint.Attachment0 = attachment0
	constraint.Attachment1 = attachment1
	constraint.Enabled = false
	constraint.LimitsEnabled = true
	constraint.UpperAngle = 35
	constraint.TwistLimitsEnabled = true
	constraint.TwistLowerAngle = -25
	constraint.TwistUpperAngle = 25
	constraint.Parent = motor.Parent

	return constraint
end

local function ensureCharacterState(character: Model): CharacterState
	local existing = characterStates[character]
	if existing then
		return existing
	end

	local state: CharacterState = {
		Rigged = false,
		Motors = {},
		Constraints = {},
		CollisionParts = {},
		OriginalCollisions = {},
	}
	characterStates[character] = state

	return state
end

function RagdollService.rigCharacter(character: Model)
	local state = ensureCharacterState(character)
	if state.Rigged then
		return state
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") and shouldRagdollMotor(descendant) then
			local constraint = createConstraintForMotor(descendant)
			if constraint then
				table.insert(state.Motors, descendant)
				table.insert(state.Constraints, constraint)
			end
		elseif descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			table.insert(state.CollisionParts, descendant)
			state.OriginalCollisions[descendant] = descendant.CanCollide
		end
	end

	state.Rigged = true
	return state
end

function RagdollService.setRagdolled(character: Model, enabled: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local state = RagdollService.rigCharacter(character)

	for _, motor in ipairs(state.Motors) do
		motor.Enabled = not enabled
	end

	for _, constraint in ipairs(state.Constraints) do
		constraint.Enabled = enabled
	end

	for _, part in ipairs(state.CollisionParts) do
		part.CanCollide = if enabled then true else (state.OriginalCollisions[part] == true)
	end

	humanoid.AutoRotate = not enabled
	humanoid.PlatformStand = enabled

	if enabled then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	else
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

function RagdollService.clearCharacter(character: Model)
	local state = characterStates[character]
	if not state then
		return
	end

	for _, constraint in ipairs(state.Constraints) do
		if constraint and constraint.Parent then
			local attachment0 = constraint.Attachment0
			local attachment1 = constraint.Attachment1
			constraint:Destroy()
			if attachment0 then
				attachment0:Destroy()
			end
			if attachment1 then
				attachment1:Destroy()
			end
		end
	end

	characterStates[character] = nil
end

return RagdollService
