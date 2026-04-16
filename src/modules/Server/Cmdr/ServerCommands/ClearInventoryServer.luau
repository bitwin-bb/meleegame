--!strict
local Resolver = require(script.Parent.CmdrPackageResolver)

local InventoryServiceServer = Resolver.requireFromGameRoot("Server", "Services", "InventoryService", "InventoryServiceServer")

return function(_context, players: { Player })
	local cleared = {}
	local unchanged = {}

	for _, player in players do
		if InventoryServiceServer:clearInventory(player) then
			cleared[#cleared + 1] = player.Name
		else
			unchanged[#unchanged + 1] = player.Name
		end
	end

	local responseParts = {}
	if #cleared > 0 then
		responseParts[#responseParts + 1] = (`Cleared inventory for {table.concat(cleared, ", ")}.`)
	end
	if #unchanged > 0 then
		responseParts[#responseParts + 1] =
			(`No inventory changes were needed for {table.concat(unchanged, ", ")}.`)
	end

	return table.concat(responseParts, " ")
end
