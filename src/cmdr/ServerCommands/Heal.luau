--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local HpServiceServer = require(ServerScriptService.Services.HpService.HpServiceServer)

return function(_context, players: { Player }, amountRaw: number?)
	local healed = {}
	local failed = {}

	for _, player in players do
		local nextHealth = nil :: number?
		if amountRaw == nil then
			local state = HpServiceServer:getState(player)
			nextHealth = HpServiceServer:setPlayerHealth(player, state.maxHealth)
		else
			nextHealth = HpServiceServer:healPlayer(player, amountRaw)
		end

		if nextHealth ~= nil then
			healed[#healed + 1] = (`{player.Name} ({math.floor(nextHealth + 0.5)} HP)`)
		else
			failed[#failed + 1] = player.Name
		end
	end

	local responseParts = {}
	if #healed > 0 then
		responseParts[#responseParts + 1] = (`Healed {table.concat(healed, ", ")}.`)
	end
	if #failed > 0 then
		responseParts[#responseParts + 1] =
			(`Could not heal {table.concat(failed, ", ")} because their humanoid was unavailable.`)
	end

	return table.concat(responseParts, " ")
end
