--!strict

local require = require(script.Parent.loader).load(assert(script:FindFirstAncestor("AquariaBackup"), "Missing AquariaBackup package root"))

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local sharedPackets = gameRoot.Shared.NetShared.Packets

local Packets = {
	AnimationService = require(sharedPackets.AnimationService),
	AudioService = require(sharedPackets.AudioService),
	BossService = require(sharedPackets.BossService),
	BreathService = require(sharedPackets.BreathService),
	BuildService = require(sharedPackets.BuildService),
	CameraService = require(sharedPackets.CameraService),
	CraftingService = require(sharedPackets.CraftingService),
	GoreService = require(sharedPackets.GoreService),
	HpService = require(sharedPackets.HpService),
	InventoryService = require(sharedPackets.InventoryService),
	LiquidService = require(sharedPackets.LiquidService),
	LootService = require(sharedPackets.LootService),
	MagicService = require(sharedPackets.MagicService),
	ManaService = require(sharedPackets.ManaService),
	MeleeService = require(sharedPackets.MeleeService),
	NpcService = require(sharedPackets.NpcService),
	PlayerDataService = require(sharedPackets.PlayerDataService),
	PlayerService = require(sharedPackets.PlayerService),
	RagdollService = require(sharedPackets.RagdollService),
	VFXService = require(sharedPackets.VFXService),
	WeatherService = require(sharedPackets.WeatherService),
	WorldGenerationService = require(sharedPackets.WorldGenerationService),
	WorldSimulationService = require(sharedPackets.WorldSimulationService),
} :: any

function Packets.Init(): ()
	return
end

Packets.init = Packets.Init

return Packets
