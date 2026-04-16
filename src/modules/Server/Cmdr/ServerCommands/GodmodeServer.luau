--!strict
local gameRoot = script:FindFirstAncestor("game")
assert(gameRoot ~= nil, "Missing Nevermore game root for GodmodeServer.")

local CmdrUtils = require(gameRoot.Shared.Cmdr.CmdrUtils)
local HpServiceServer = require(gameRoot.Server.Services.HpService.HpServiceServer)

local function joinParts(parts: { string }): string
	return table.concat(parts, ", ")
end

return function(_context, players: { Player }, enabledRaw: boolean?)
	local enabledPlayers = {}
	local disabledPlayers = {}

	for _, player in players do
		local currentlyEnabled = player:GetAttribute(CmdrUtils.GODMODE_ENABLED_ATTRIBUTE) == true
		local nextEnabled = if enabledRaw == nil then not currentlyEnabled else enabledRaw
		player:SetAttribute(CmdrUtils.GODMODE_ENABLED_ATTRIBUTE, nextEnabled)

		if nextEnabled then
			local state = HpServiceServer:getState(player)
			HpServiceServer:setPlayerHealth(player, state.maxHealth)
			enabledPlayers[#enabledPlayers + 1] = player.Name
		else
			disabledPlayers[#disabledPlayers + 1] = player.Name
		end
	end

	local responseParts = {}
	if #enabledPlayers > 0 then
		responseParts[#responseParts + 1] = (`Enabled godmode for {joinParts(enabledPlayers)}.`)
	end
	if #disabledPlayers > 0 then
		responseParts[#responseParts + 1] = (`Disabled godmode for {joinParts(disabledPlayers)}.`)
	end

	return table.concat(responseParts, " ")
end
