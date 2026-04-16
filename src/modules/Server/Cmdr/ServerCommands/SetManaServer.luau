--!strict
local Resolver = require(script.Parent.CmdrPackageResolver)

local ManaServiceServer = Resolver.requireFromGameRoot("Server", "Services", "ManaService", "ManaServiceServer")

local function joinParts(parts: { string }): string
	return table.concat(parts, ", ")
end

return function(_context, players: { Player }, amountRaw: number)
	local updated = {}
	local failed = {}

	for _, player in players do
		local nextMaxMana = ManaServiceServer:setMaxMana(player, amountRaw)
		if nextMaxMana == nil then
			failed[#failed + 1] = player.Name
			continue
		end

		ManaServiceServer:setMana(player, nextMaxMana)
		updated[#updated + 1] = (`{player.Name} ({math.floor(nextMaxMana + 0.5)} mana)`)
	end

	local responseParts = {}
	if #updated > 0 then
		responseParts[#responseParts + 1] = (`Set permanent max mana for {joinParts(updated)} and refilled it.`)
	end
	if #failed > 0 then
		responseParts[#responseParts + 1] =
			(`Could not update {joinParts(failed)} because their mana runtime was unavailable.`)
	end

	return table.concat(responseParts, " ")
end
