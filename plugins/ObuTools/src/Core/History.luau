--[[
	History — every change this plugin makes must be one Ctrl+Z.

	THIS IS THE RULE THAT SEPARATES A USABLE PLUGIN FROM A DANGEROUS ONE.
	A tool that scatters forty cones and cannot undo them is worse than no
	tool, because the cleanup costs more than the placement saved.

	TryBeginRecording/FinishRecording is the modern API and it does the
	thing the old SetWaypoint pair could not: it groups everything between
	the two calls into a SINGLE undo step. Forty cones, one Ctrl+Z.

	IT CANCELS ON ERROR. If a tool throws halfway through, the recording
	is discarded rather than committed, so a half-applied change never
	becomes an undo entry you have to pick apart by hand. That is also
	why the work goes through this wrapper instead of being written
	inline everywhere.
--]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local History = {}

-- Runs `fn` as one undoable operation. Returns whatever `fn` returned.
function History.run<T>(name: string, fn: () -> T): T?
	local id = ChangeHistoryService:TryBeginRecording(name)

	-- Nil means a recording is already open — Studio only allows one at a
	-- time. Doing the work anyway is correct: it still lands inside the
	-- OUTER recording, so it is still undoable, just grouped with it.
	if not id then
		local ok, result = pcall(fn)
		if not ok then
			warn(("[ObuTools] %s failed: %s"):format(name, tostring(result)))
			return nil
		end
		return result
	end

	local ok, result = pcall(fn)
	ChangeHistoryService:FinishRecording(
		id,
		if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
	)

	if not ok then
		warn(("[ObuTools] %s failed and was rolled back: %s"):format(name, tostring(result)))
		return nil
	end
	return result
end

--=====================================================================
--  STROKES
--
--  For work that spans several frames — dragging the brush — where
--  there is no single function to wrap. A whole stroke of forty cones
--  is then one undo, exactly like a single click is.
--
--  ALWAYS PAIR THEM. A recording left open blocks every later one:
--  TryBeginRecording returns nil until it is finished, so a leaked
--  stroke quietly turns every subsequent tool into "grouped with
--  whatever came before".
--=====================================================================

function History.open(name: string): string?
	return ChangeHistoryService:TryBeginRecording(name)
end

function History.close(id: string?, commit: boolean)
	if not id then
		return
	end
	ChangeHistoryService:FinishRecording(
		id,
		if commit then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
	)
end

return History
