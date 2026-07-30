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
function Util.logger(tag: string, enabled: boolean)
	return function(fmt: string, ...)
		if enabled then
			print(("[%s] %s"):format(tag, string.format(fmt, ...)))
		end
	end
end

return Util
