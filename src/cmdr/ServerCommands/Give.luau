--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemRegistry = require(ReplicatedStorage.Shared.Modules.Items.Registry)
local InventoryServiceServer = require(ServerScriptService.Services.InventoryService.InventoryServiceServer)

local function joinNames(names: { string }): string
	return table.concat(names, ", ")
end

return function(_context, itemIdRaw: string, players: { Player }, amountRaw: number)
	local itemId = ItemRegistry.resolveCanonicalItemId(itemIdRaw)
	if itemId == nil then
		return (`Unknown item "{itemIdRaw}".`)
	end

	local definition = ItemRegistry.resolveDefinition(itemId)
	local itemName = if typeof(definition) == "table" and typeof((definition :: any).name) == "string"
		then (definition :: any).name
		else itemId
	local amount = math.max(1, math.floor(amountRaw))

	local delivered = {}
	local partial = {}
	local failed = {}

	for _, player in players do
		local result = InventoryServiceServer:addItem(player, itemId, amount, nil)
		if result.added >= amount and result.leftover <= 0 then
			delivered[#delivered + 1] = player.Name
		elseif result.added > 0 then
			partial[#partial + 1] = (`{player.Name} (+{result.added}, {result.leftover} leftover)`)
		else
			failed[#failed + 1] = player.Name
		end
	end

	local responseParts = {}
	if #delivered > 0 then
		responseParts[#responseParts + 1] = (`Gave {itemName} x{amount} to {joinNames(delivered)}.`)
	end
	if #partial > 0 then
		responseParts[#responseParts + 1] = (`Partially added for {joinNames(partial)}.`)
	end
	if #failed > 0 then
		responseParts[#responseParts + 1] =
			(`Failed for {joinNames(failed)} because their inventory was unavailable or full.`)
	end

	return table.concat(responseParts, " ")
end
