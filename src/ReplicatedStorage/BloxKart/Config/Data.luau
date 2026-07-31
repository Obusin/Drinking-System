--[[
	Data — persistence.

	OFF BY DEFAULT. Turning this on makes the profile the source of
	truth, and the client is still authoritative on finish time and on
	upward progress. Currency saved from numbers a modified client can
	choose is an exploit with a database behind it, so the order is:
	close those two seams, THEN set Enabled.

	The plan is in the vault at "BloxKart Data Security and Drops".
--]]

return {
	-- The gate. See above — this is not a convenience toggle.
	Enabled = false,

	-- Store name. The `_v1` is a HARD RESET marker, not a migration
	-- path: changing it abandons every existing profile. Migration is
	-- the `schema` field inside the profile. Never rename a store to
	-- migrate — that is a deletion with extra steps.
	StoreName = "BloxKart_Profile_v1",

	-- Force the mock store even in a published place. Studio uses the
	-- mock automatically regardless, so this is only for testing a live
	-- server without touching live data.
	Mock = false,
}
