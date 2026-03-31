--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local HpServiceServer = require(ServerScriptService.Services.HpService.HpServiceServer)

local function joinParts(parts: { string }): string
	return table.concat(parts, ", ")
end

return function(_context, players: { Player }, amountRaw: number)
	local updated = {}

	for _, player in players do
		local nextMaxHealth = HpServiceServer:setPlayerMaxHealth(player, amountRaw, true)
		if nextMaxHealth ~= nil then
			updated[#updated + 1] = (`{player.Name} ({math.floor(nextMaxHealth + 0.5)} HP)`)
		end
	end

	if #updated <= 0 then
		return "No players could be updated."
	end

	return (`Set permanent max health for {joinParts(updated)} and refilled them.`)
end
