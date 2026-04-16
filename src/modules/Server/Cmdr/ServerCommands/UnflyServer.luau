--!strict
local gameRoot = script:FindFirstAncestor("game")
assert(gameRoot ~= nil, "Missing Nevermore game root for UnflyServer.")

local CmdrUtils = require(gameRoot.Shared.Cmdr.CmdrUtils)

local function setFlyEnabled(player: Player, enabledRaw: any)
	local enabled = enabledRaw == true

	player:SetAttribute(CmdrUtils.FLY_ENABLED_ATTRIBUTE, enabled)
	if enabled then
		player:SetAttribute(CmdrUtils.FLY_SPEED_ATTRIBUTE, CmdrUtils.DEFAULT_FLY_SPEED)
	else
		player:SetAttribute(CmdrUtils.FLY_SPEED_ATTRIBUTE, nil)
	end
end

return function(_context, players: { Player })
	local updated = {}

	for index, player in players do
		setFlyEnabled(player, false)
		updated[index] = player.Name
	end

	return (`Disabled fly for {table.concat(updated, ", ")}.`)
end
