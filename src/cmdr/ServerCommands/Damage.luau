--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local HpServiceServer = require(ServerScriptService.Services.HpService.HpServiceServer)

return function(_context, players: { Player }, amountRaw: number)
	local damaged = {}
	local failed = {}

	for _, player in players do
		local nextHealth = HpServiceServer:damagePlayer(player, amountRaw)
		if nextHealth ~= nil then
			damaged[#damaged + 1] = (`{player.Name} ({math.floor(nextHealth + 0.5)} HP)`)
		else
			failed[#failed + 1] = player.Name
		end
	end

	local responseParts = {}
	if #damaged > 0 then
		responseParts[#responseParts + 1] = (`Damaged {table.concat(damaged, ", ")}.`)
	end
	if #failed > 0 then
		responseParts[#responseParts + 1] =
			(`Could not damage {table.concat(failed, ", ")} because their humanoid was unavailable.`)
	end

	return table.concat(responseParts, " ")
end
