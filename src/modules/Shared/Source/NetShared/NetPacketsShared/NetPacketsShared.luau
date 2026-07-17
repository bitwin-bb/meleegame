local require = require(script.Parent.loader).load(script)
local Packets = {
	AnimationService = require("AnimationService"),
	AudioService = require("AudioService"),
	BossService = require("BossService"),
	BreathService = require("BreathService"),
	BuildService = require("BuildService"),
	CameraService = require("CameraService"),
	CraftingService = require("CraftingService"),
	CropService = require("CropServicePackets"),
	GoreService = require("GoreService"),
	HpService = require("HpService"),
	InventoryService = require("InventoryService"),
	LiquidService = require("LiquidService"),
	LootService = require("LootService"),
	MagicService = require("MagicService"),
	ManaService = require("ManaService"),
	MeleeService = require("MeleeService"),
	NpcService = require("NpcService"),
	PlayerDataService = require("PlayerDataService"),
	PlayerService = require("PlayerService"),
	RagdollService = require("RagdollServicePackets"),
	VFXService = require("VfxService"),
	WeatherService = require("WeatherService"),
	WorldGenerationService = require("WorldGenerationService"),
	WorldSimulationService = require("WorldSimulationService"),
} :: any

function Packets.Init(): ()
	return
end
return Packets
