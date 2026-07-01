local require = require(script.Parent.loader).load(script)


local CmdrUtils = require("CmdrUtils")
local PlayerServiceServer = require("PlayerServiceServer")

local function setFlyEnabled(player: Player, enabledRaw: any, speedRaw: any): number
	local enabled = enabledRaw == true
	local speed = CmdrUtils.CoerceFlySpeed(speedRaw, CmdrUtils.DEFAULT_FLY_SPEED)

	player:SetAttribute(CmdrUtils.FLY_ENABLED_ATTRIBUTE, enabled)
	if enabled then
		player:SetAttribute(CmdrUtils.FLY_SPEED_ATTRIBUTE, speed)
		PlayerServiceServer:SetMovementLocked(player, false, true)
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

	return `Enabled fly for {table.concat(updated, ", ")} at speed {speed}.`
end
