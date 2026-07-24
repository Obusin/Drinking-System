-- Birthday Party: Soda Water + Sugar → low gravity + bouncy jumps for a
-- while. A VectorForce counteracts a fraction of real gravity (computed from
-- the character's ACTUAL assembly mass, not a hardcoded guess) for the
-- floaty feel, plus a JumpPower boost for the bounce.

local BirthdayParty = {}

-- ctx: { Player, Tool, Remaining, SipAmount, Services }
function BirthdayParty.OnSip(ctx)
	local tool = ctx.Tool
	if tool then
		if tool:GetAttribute("DS_BirthdayPartyTriggered") == true then
			return
		end
		tool:SetAttribute("DS_BirthdayPartyTriggered", true)
	end

	local player = ctx.Player
	local char = player.Character
	if not char then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not hrp then
		return
	end

	local Settings = ctx.Services.Settings
	local duration = Settings.BirthdayPartyDuration or 12
	local counterFraction = Settings.BirthdayPartyGravityCounterFraction or 0.6
	local boostedJumpPower = Settings.BirthdayPartyJumpPower or 90

	local origJumpPower = humanoid.JumpPower
	local origJumpHeight = humanoid.JumpHeight

	humanoid.JumpPower = boostedJumpPower
	humanoid.JumpHeight = math.max(humanoid.JumpHeight, 12)

	local attachment = Instance.new("Attachment")
	attachment.Name = "DS_BirthdayPartyAttach"
	attachment.Parent = hrp

	local force = Instance.new("VectorForce")
	force.Name = "DS_BirthdayPartyForce"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.new(0, hrp.AssemblyMass * workspace.Gravity * counterFraction, 0)
	force.Parent = hrp

	task.delay(duration, function()
		if force.Parent then
			force:Destroy()
		end
		if attachment.Parent then
			attachment:Destroy()
		end
		if humanoid.Parent then
			humanoid.JumpPower = origJumpPower
			humanoid.JumpHeight = origJumpHeight
		end
	end)
end

return BirthdayParty
