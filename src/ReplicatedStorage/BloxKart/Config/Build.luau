--[[
	Build — which version of the code is this server running?

	Every place in the experience runs the SAME source tree, and nothing
	currently enforces that. One Argon session syncs into whichever place
	is open in Studio, so the lobby can get a fix that a race place does
	not, and the resulting bug looks like a place-specific problem
	instead of a stale copy.

	Both entry points print this line at startup. Comparing two servers'
	output is then a glance rather than an investigation.

	WHY THIS IS TYPED BY HAND AND NOT STAMPED FROM GIT
	-------------------------------------------------
	The obvious version writes the commit hash in from `check.sh`. It
	chases its own tail: stamping changes a tracked file, committing that
	changes HEAD, and the stamp is immediately out of date again.

	The stamp belongs to a DEPLOY step — build once, publish to every
	place, write the version as part of that — and there is no deploy
	step yet. Until there is, this is a number you bump on purpose, which
	is honest about being manual rather than automatic and wrong.

	BUMP IT WHEN YOU PUBLISH, not when you edit. The question it answers
	is "are these two servers running the same code", and an edit that
	never reached a place is not a difference between places.
--]]

return {
	-- Bumped by hand at publish. Any format that sorts and that you can
	-- read out loud over a call is fine; this one is date + a letter for
	-- the second publish of a day.
	Version = "2026-08-02a",

	-- What changed, in a few words. Shows up next to the version, so a
	-- server can say what it is rather than only which number it is.
	Note = "places split: lobby vs race",

	-- Off only if the startup lines ever become noise. They are two
	-- prints per server, once.
	Announce = true,
}
