--!strict
local gameRoot = script:FindFirstAncestor("game")
assert(gameRoot ~= nil, "Missing Nevermore game root for MatterDebugServer.")

local CmdrUtils = require(gameRoot.Shared.Cmdr.CmdrUtils)

local function joinParts(parts: { string }): string
	return table.concat(parts, ", ")
end

return function(_context, players: { Player }, enabledRaw: boolean?)
	local enabledPlayers = {}
	local disabledPlayers = {}

	for _, player in players do
		local currentlyEnabled = player:GetAttribute(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE) == true
		local nextEnabled = if enabledRaw == nil then not currentlyEnabled else enabledRaw
		player:SetAttribute(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE, nextEnabled)

		if nextEnabled then
			enabledPlayers[#enabledPlayers + 1] = player.Name
		else
			disabledPlayers[#disabledPlayers + 1] = player.Name
		end
	end

	local responseParts = {}
	if #enabledPlayers > 0 then
		responseParts[#responseParts + 1] = (`Enabled Matter debug menu for {joinParts(enabledPlayers)}.`)
	end
	if #disabledPlayers > 0 then
		responseParts[#responseParts + 1] = (`Disabled Matter debug menu for {joinParts(disabledPlayers)}.`)
	end

	return table.concat(responseParts, " ")
end
