--!strict
local gameRoot = script:FindFirstAncestor("game")
assert(gameRoot ~= nil, "Missing Nevermore game root for FlyServer.")

local CmdrUtils = require(gameRoot.Shared.Cmdr.CmdrUtils)
local PlayerServiceServer = require(gameRoot.Server.Services.PlayerServiceServer)

local function setFlyEnabled(player: Player, enabledRaw: any, speedRaw: any): number
	local enabled = enabledRaw == true
	local speed = CmdrUtils.sanitizeFlySpeed(speedRaw, CmdrUtils.DEFAULT_FLY_SPEED)

	player:SetAttribute(CmdrUtils.FLY_ENABLED_ATTRIBUTE, enabled)
	if enabled then
		player:SetAttribute(CmdrUtils.FLY_SPEED_ATTRIBUTE, speed)
		PlayerServiceServer:setMovementLocked(player, false, true)
	else
		player:SetAttribute(CmdrUtils.FLY_SPEED_ATTRIBUTE, nil)
	end

	return speed
end

return function(_context, players: { Player }, speedRaw: number)
	local updated = {}
	local speed = 0

	for index, player in players do
		speed = setFlyEnabled(player, true, speedRaw)
		updated[index] = player.Name
	end

	return (`Enabled fly for {table.concat(updated, ", ")} at speed {speed}.`)
end
