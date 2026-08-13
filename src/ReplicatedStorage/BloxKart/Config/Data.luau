--[[
	Data — persistence.

	Profiles are authoritative server data. Finish time, route progress and
	lap banking are server-observed before rewards are issued; never add a
	client-reported reward path without equivalent server proof.

	The plan is in the vault at "BloxKart Data Security and Drops".
--]]

return {
	-- The gate. See above — this is not a convenience toggle.
	--
	-- ON as of 2026-08-01. Safe in Studio, which forces ProfileStore's
	-- mock store regardless of this flag, so nothing here can touch a
	-- real profile.
	Enabled = true,

	-- Store name. The `_v1` is a HARD RESET marker, not a migration
	-- path: changing it abandons every existing profile. Migration is
	-- the `schema` field inside the profile. Never rename a store to
	-- migrate — that is a deletion with extra steps.
	StoreName = "BloxKart_Profile_v1",

	-- Force the mock store even in a published place. Only for testing a
	-- live server without touching live data.
	Mock = false,

	-- LET STUDIO WRITE TO THE REAL DATASTORE.
	--
	-- Off by default, and that default is deliberate: a test that writes
	-- to a real profile is indistinguishable from a bug that does, and
	-- the mock store behaves the same in every way except surviving.
	--
	-- But "does it actually store" is not a question the mock can
	-- answer, and it is a question worth answering before launch. Turn
	-- this on, play, rejoin, and check the numbers came back — then turn
	-- it off again.
	--
	-- It writes to the SAME KEYS a published server would, so anything
	-- saved here is real player data on your own account.
	--
	-- Turned on 2026-08-01 to prove a profile survives a rejoin. It did.
	-- OFF again 2026-08-02 — it had been left on, so every playtest was
	-- reading and writing the real profile, and a test that corrupts
	-- data looks exactly like a bug that does.
	LiveInStudio = false,
}
