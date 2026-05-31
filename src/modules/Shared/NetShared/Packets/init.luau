--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

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

function Packets.Init(): ()
	return
end

Packets.init = Packets.Init

return Packets
