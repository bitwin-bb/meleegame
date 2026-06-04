--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local function isEarlyPlayerChannelError(errRaw: any): boolean
	local err = tostring(errRaw)
	return string.find(err, "bufferWriter", 1, true) ~= nil and string.find(err, "size", 1, true) ~= nil
end

local function bindServerSendRetry(serviceName: string, methodName: string, packet: any)
	local sendTo = packet.sendTo
	if typeof(sendTo) ~= "function" then
		return
	end

	packet.sendTo = function(data: any, player: Player)
		local ok, err = pcall(sendTo, data, player)
		if ok then
			return
		end
		if not isEarlyPlayerChannelError(err) then
			warn(`ByteNet send failed for {serviceName}.{methodName}: {tostring(err)}`)
			return
		end

		task.defer(function()
			local retryOk, retryErr = pcall(sendTo, data, player)
			if not retryOk then
				warn(`ByteNet send retry failed for {serviceName}.{methodName}: {tostring(retryErr)}`)
			end
		end)
	end
end

local function bindServerPacketRetries(packets: { [string]: any })
	for serviceName, servicePackets in packets do
		if typeof(servicePackets) == "table" then
			for methodName, packet in servicePackets do
				if typeof(packet) == "table" then
					bindServerSendRetry(serviceName, methodName, packet)
				end
			end
		end
	end
end

local Packets = {
	AnimationService = require(gameRoot.Shared.NetShared.Packets.AnimationService),
	AudioService = require(gameRoot.Shared.NetShared.Packets.AudioService),
	BossService = require(gameRoot.Shared.NetShared.Packets.BossService),
	BreathService = require(gameRoot.Shared.NetShared.Packets.BreathService),
	BuildService = require(gameRoot.Shared.NetShared.Packets.BuildService),
	CameraService = require(gameRoot.Shared.NetShared.Packets.CameraService),
	CraftingService = require(gameRoot.Shared.NetShared.Packets.CraftingService),
	GoreService = require(gameRoot.Shared.NetShared.Packets.GoreService),
	HpService = require(gameRoot.Shared.NetShared.Packets.HpService),
	InventoryService = require(gameRoot.Shared.NetShared.Packets.InventoryService),
	LiquidService = require(gameRoot.Shared.NetShared.Packets.LiquidService),
	LootService = require(gameRoot.Shared.NetShared.Packets.LootService),
	MagicService = require(gameRoot.Shared.NetShared.Packets.MagicService),
	ManaService = require(gameRoot.Shared.NetShared.Packets.ManaService),
	MeleeService = require(gameRoot.Shared.NetShared.Packets.MeleeService),
	NpcService = require(gameRoot.Shared.NetShared.Packets.NpcService),
	PlayerDataService = require(gameRoot.Shared.NetShared.Packets.PlayerDataService),
	PlayerService = require(gameRoot.Shared.NetShared.Packets.PlayerService),
	RagdollService = require(gameRoot.Shared.NetShared.Packets.RagdollService),
	VFXService = require(gameRoot.Shared.NetShared.Packets.VFXService),
	WeatherService = require(gameRoot.Shared.NetShared.Packets.WeatherService),
	WorldGenerationService = require(gameRoot.Shared.NetShared.Packets.WorldGenerationService),
	WorldSimulationService = require(gameRoot.Shared.NetShared.Packets.WorldSimulationService),
} :: any

bindServerPacketRetries(Packets)

function Packets.Init(): ()
	return
end

Packets.init = Packets.Init

return Packets
