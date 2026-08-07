--[[
	Brush — paint copies of a thing onto surfaces.

	Pick a template, hold the left mouse button, drag across the world.
	Cones down a track edge, rocks on a hillside, bollards along a kerb —
	the jobs where placing forty of something by hand is the reason the
	detail never gets added.

	A GHOST FOLLOWS THE CURSOR. You see the thing you are about to place,
	at the angle it will land, before you press anything. Without it the
	first click of every session is a guess about scale and orientation,
	and the answer arrives as an object you then have to undo.

	WHY IT MUST EXCLUDE WHAT IT HAS ALREADY PAINTED
	-----------------------------------------------
	The ray has to reach the GROUND. If the things already painted are
	raycastable, the second cone lands on the first, the third lands on
	the second, and the brush builds a tower instead of a trail. So every
	clone joins the ray filter for the rest of the stroke — along with the
	template itself, which is otherwise the first thing you paint onto.
	The ghost is exempt by construction: Ghost makes every part
	non-queryable, so the cursor cannot be what the cursor lands on.

	ONE STROKE IS ONE UNDO. The recording opens on mouse-down and closes
	on mouse-up, so a drag that placed sixty rocks is a single Ctrl+Z. A
	scatter tool without that is a tool you are afraid to use.

	IT SITS ON THE SURFACE. Placement lifts each clone by half its own
	height along the surface normal, measured from the template's real
	bounding box — so a tall cone and a flat rock both land ON the ground
	rather than half inside it.
--]]

local Ghost = require(script.Parent.Parent.Core.Ghost)
local History = require(script.Parent.Parent.Core.History)
local Sel = require(script.Parent.Parent.Core.Sel)
local Ui = require(script.Parent.Parent.Core.Ui)

local Brush = {}

-- The template's upright size, whether it is a Model or a bare part.
local function sizeOf(inst: Instance): Vector3
	if inst:IsA("BasePart") then
		return inst.Size
	elseif inst:IsA("Model") then
		local ok, _, size = pcall(inst.GetBoundingBox, inst)
		if ok and typeof(size) == "Vector3" then
			return size
		end
	end
	return Vector3.one
end

local function setPivot(inst: Instance, cf: CFrame)
	if inst:IsA("BasePart") then
		inst.CFrame = cf
	elseif inst:IsA("Model") then
		inst:PivotTo(cf)
	end
end

local function scaleBy(inst: Instance, factor: number)
	if math.abs(factor - 1) < 1e-4 then
		return
	end
	if inst:IsA("Model") then
		pcall(function()
			inst:ScaleTo(inst:GetScale() * factor)
		end)
	elseif inst:IsA("BasePart") then
		inst.Size *= factor
	end
end

function Brush.build(page: Instance, ctx, plugin: Plugin)
	local template: Instance? = nil
	local painting = false
	local spacing, scaleMin, scaleMax = 6, 0.9, 1.15
	local alignToSurface, randomYaw = true, true

	local mouse = plugin:GetMouse()
	local ghost = Ghost.new("Brush")
	local rng = Random.new()

	--=====================================================================
	--  PLACEMENT MATHS — shared by the ghost and the real thing, so the
	--  preview cannot disagree with what you get.
	--=====================================================================

	local function poseFor(hit: RaycastResult, factor: number, yaw: number): CFrame
		local tpl = template :: Instance
		local up = if alignToSurface then hit.Normal else Vector3.yAxis
		-- An arbitrary perpendicular; the yaw rotates within the plane
		-- anyway, so which one it starts from does not matter.
		local ref = if math.abs(up.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
		local rightV = up:Cross(ref)
		rightV = if rightV.Magnitude > 1e-3 then rightV.Unit else Vector3.xAxis
		local backV = rightV:Cross(up).Unit
		local lift = up * (sizeOf(tpl).Y * factor / 2)
		return CFrame.fromMatrix(hit.Position + lift, rightV, up, backV) * CFrame.Angles(0, yaw, 0)
	end

	local filter: { Instance } = {}

	local function cast(): RaycastResult?
		local ray = mouse.UnitRay
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = filter
		params.IgnoreWater = true
		return workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
	end

	--=====================================================================
	--  PANEL
	--=====================================================================

	local sec = Ui.section(page, "Template", "brush1")
	local templateLabel = Ui.label(sec, "No template set.", true)

	Ui.button(sec, "Use selection as template", function()
		local picked = Sel.get()[1]
		if not picked or not (picked:IsA("BasePart") or picked:IsA("Model")) then
			templateLabel.Text = "Select one Part or Model first."
			return
		end
		template = picked
		templateLabel.Text = ("Template: %s"):format(picked.Name)
	end)

	local opts = Ui.section(page, "Scatter", "brush2")
	Ui.slider(opts, "Spacing (studs)", 0, 60, spacing, 0.5, function(v)
		spacing = v
	end)
	Ui.slider(opts, "Scale min", 0.1, 3, scaleMin, 0.05, function(v)
		scaleMin = v
	end)
	Ui.slider(opts, "Scale max", 0.1, 3, scaleMax, 0.05, function(v)
		scaleMax = v
	end)

	local alignBtn, yawBtn
	alignBtn = Ui.toggle(opts, "Follow surface angle", function()
		return alignToSurface
	end, function()
		alignToSurface = not alignToSurface
		Ui.repaint(alignBtn)
	end)
	yawBtn = Ui.toggle(opts, "Random rotation", function()
		return randomYaw
	end, function()
		randomYaw = not randomYaw
		Ui.repaint(yawBtn)
	end)

	--=====================================================================
	--  PAINTING
	--=====================================================================

	local stroke: string? = nil
	local placed: { Instance } = {}
	local lastAt: Vector3? = nil

	-- The cursor ghost uses the MIDDLE of the scale range rather than a
	-- fresh random value, because rerolling it on every mouse-move would
	-- make the preview flicker between sizes and tell you nothing.
	local function showCursor()
		local tpl = template
		if not tpl or not tpl.Parent or not painting then
			ghost:clear()
			return
		end
		local hit = cast()
		if not hit then
			ghost:clear()
			return
		end
		ghost:update(tpl, { poseFor(hit, (scaleMin + scaleMax) / 2, 0) })
	end

	local function place()
		local tpl = template
		if not tpl or not tpl.Parent then
			return
		end
		local hit = cast()
		if not hit then
			return
		end

		-- Spacing is measured against the last placement in this stroke,
		-- which is what stops a slow drag piling fifty copies on one spot.
		if lastAt and (hit.Position - lastAt).Magnitude < spacing then
			return
		end
		lastAt = hit.Position

		local factor = rng:NextNumber(math.min(scaleMin, scaleMax), math.max(scaleMin, scaleMax))
		local yaw = if randomYaw then rng:NextNumber(0, math.pi * 2) else 0

		local clone = tpl:Clone()
		scaleBy(clone, factor)
		setPivot(clone, poseFor(hit, factor, yaw))
		clone.Parent = tpl.Parent or workspace

		table.insert(placed, clone)
		-- Joins the filter so the next ray goes past it to the ground.
		table.insert(filter, clone)
	end

	-- Only the mouse hooks live here. The Deactivation hook below is
	-- deliberately NOT in this list: it has to outlive a stop, or the
	-- first time you switch tools it disconnects itself and never fires
	-- again.
	local mouseConns: { RBXScriptConnection } = {}
	local paintBtn: TextButton

	local function stopPainting(alsoDeactivate: boolean)
		painting = false
		-- Committed rather than cancelled: whatever was painted before you
		-- stopped is work you meant to do. Cancelling would delete it.
		History.close(stroke, true)
		stroke = nil
		for _, c in mouseConns do
			c:Disconnect()
		end
		table.clear(mouseConns)
		ghost:clear()
		if alsoDeactivate then
			plugin:Deactivate()
		end
		Ui.repaint(paintBtn)
	end

	local function startPainting()
		local tpl = template
		if not tpl or not tpl.Parent then
			ctx.status("Set a template first.")
			return
		end
		painting = true
		plugin:Activate(true)
		filter = { tpl }

		local down = false
		table.insert(mouseConns, mouse.Button1Down:Connect(function()
			down = true
			table.clear(placed)
			lastAt = nil
			-- The template is excluded from the very first ray, otherwise
			-- the first thing you paint on is the thing you are painting.
			filter = { tpl }
			stroke = History.open("Brush stroke")
			place()
		end))
		table.insert(mouseConns, mouse.Move:Connect(function()
			if down then
				place()
			else
				showCursor()
			end
		end))
		table.insert(mouseConns, mouse.Button1Up:Connect(function()
			down = false
			History.close(stroke, true)
			stroke = nil
			ctx.status(("Painted %d."):format(#placed))
			showCursor()
		end))

		showCursor()
	end

	paintBtn = Ui.toggle(page, "Paint", function()
		return painting
	end, function()
		if painting then
			stopPainting(true)
		else
			startPainting()
			Ui.repaint(paintBtn)
		end
	end)

	-- Studio fires this when another tool takes the mouse. Without it the
	-- button stays lit while the brush is no longer receiving anything,
	-- which reads as the plugin having broken.
	plugin.Deactivation:Connect(function()
		if painting then
			stopPainting(false)
		end
	end)

	-- Leaving the panel puts the mouse back. A brush still armed behind a
	-- closed window would eat clicks in the viewport with nothing on
	-- screen to explain why.
	ctx.onHide(function()
		if painting then
			stopPainting(true)
		end
		ghost:clear()
	end)

	Ui.label(page, "Drag on a surface to scatter. One stroke is one undo.", true)
end

return Brush
