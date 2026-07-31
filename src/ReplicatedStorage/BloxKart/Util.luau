--[[
	Util — shared maths. No state, no services.
--]]

local Util = {}

-- Frame-rate independent approach toward a target. `rate` is roughly
-- "how many times per second it closes the remaining gap".
function Util.approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * math.min(rate * dt, 1)
end

-- Shortest-path angle approach, so recentring from -170° doesn't take
-- the long way round.
function Util.approachAngle(current: number, target: number, rate: number, dt: number): number
	local diff = (target - current + math.pi) % (math.pi * 2) - math.pi
	return current + diff * math.min(rate * dt, 1)
end

-- Zero slope at both ends. This is what stops the drift snapping.
function Util.smoothstep(t: number): number
	return t * t * (3 - 2 * t)
end

-- Rotate `v` about `axis`. Steering spins the forward vector about
-- whatever the current up happens to be, so it behaves the same on a
-- ceiling as on flat ground.
-- Sample an evenly-spaced curve table at t (0..1), interpolating between
-- points. Lets a feel curve live in config as a readable list of numbers
-- — the shape you'd sketch on a graph — instead of a formula nobody can
-- picture. Index 1 is t=0, the last index is t=1.
function Util.sampleCurve(curve: { number }, t: number): number
	local n = #curve
	if n == 0 then
		return 1
	elseif n == 1 then
		return curve[1]
	end

	t = math.clamp(t, 0, 1)
	local pos = t * (n - 1) + 1
	local i = math.clamp(math.floor(pos), 1, n - 1)
	return curve[i] + (curve[i + 1] - curve[i]) * (pos - i)
end

function Util.rotateAbout(v: Vector3, axis: Vector3, angle: number): Vector3
	return CFrame.fromAxisAngle(axis, angle):VectorToWorldSpace(v)
end

-- Re-orthogonalise forward against up and normalise both.
function Util.orthonormal(forward: Vector3, up: Vector3): (Vector3, Vector3)
	if up.Magnitude < 1e-4 then
		up = Vector3.yAxis
	end
	up = up.Unit
	local flattened = forward - up * forward:Dot(up)
	if flattened.Magnitude < 1e-4 then
		-- forward collapsed onto up; pick any perpendicular
		flattened = up:Cross(Vector3.xAxis)
		if flattened.Magnitude < 1e-4 then
			flattened = up:Cross(Vector3.zAxis)
		end
	end
	return flattened.Unit, up
end

-- Tagged logger that compiles out when disabled.
-- Resolve a font by name, falling back if it isn't installed.
--
-- Font.fromName THROWS on an unknown name, so every HUD wrapped it in
-- the same pcall — seven identical copies, which is seven chances for
-- one of them to be missing the fallback and take the whole client down
-- with it just because a font wasn't uploaded.
--
-- Takes the name rather than reading Config, so Util stays free of
-- dependencies.
function Util.font(name: string, weight: Enum.FontWeight): Font
	local ok, font = pcall(function()
		return Font.fromName(name, weight)
	end)
	if ok and font then
		return font
	end
	warn(("[Util] font %q unavailable, falling back."):format(tostring(name)))
	return Font.fromEnum(Enum.Font.GothamBold)
end

-- C0/C1 for a Motor6D that rotates `part` about ITS OWN PIVOT rather
-- than about its CFrame origin.
--
-- Identical for a plain Part, where the two coincide. Different for an
-- imported mesh, whose pivot sits wherever the artist left the origin in
-- Blender — often the world centre or the base of the model rather than
-- the middle of the wheel.
--
-- Anchoring to the CFrame origin in that case makes a wheel ORBIT that
-- point instead of spinning on its axle, which reads as the wheel having
-- come off rather than turning.
--
-- Transform = identity still reproduces the part's original position, so
-- this is always safe to use in place of a plain object-space C0.
function Util.pivotJoint(root: BasePart, part: BasePart): (CFrame, CFrame)
	local pivot = part:GetPivot()
	return root.CFrame:ToObjectSpace(pivot), part.CFrame:ToObjectSpace(pivot)
end

function Util.logger(tag: string, enabled: boolean)
	return function(fmt: string, ...)
		if enabled then
			print(("[%s] %s"):format(tag, string.format(fmt, ...)))
		end
	end
end

--=====================================================================
--  IMAGE DIAGNOSTIC
--
--  An ImageLabel with a bad id renders nothing and says nothing, which
--  is indistinguishable from a layout bug.
--
--  By far the usual cause: the number Roblox shows you after an upload
--  is the DECAL asset, and rbxassetid://<decalId> does not render in an
--  ImageLabel — you need the underlying IMAGE id. Get it from the
--  Creator Dashboard, or insert the asset in Studio and read back the
--  Image property.
--
--  Lives here rather than in each HUD because it was already written
--  twice, and the second copy is how the two answers start to drift.
--=====================================================================
local warnedImages = {}

function Util.verifyImage(label: ImageLabel, id: string, tag: string)
	if id == "" or warnedImages[id] then
		return
	end
	warnedImages[id] = true
	task.delay(3, function()
		if label.Parent and label.Image == id and not label.IsLoaded then
			warn(
				("[%s] image failed to load: %s — if that's a Decal id it won't render; use the Image id instead."):format(
					tag,
					id
				)
			)
		end
	end)
end

return Util
