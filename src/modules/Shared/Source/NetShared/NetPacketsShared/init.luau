local require = require(script.Parent.loader).load(script)
local Packets = {
	AnimationService = require(script:WaitForChild("AnimationService")),
	AudioService = require(script:WaitForChild("AudioService")),
	BossService = require(script:WaitForChild("BossService")),
	BreathService = require(script:WaitForChild("BreathService")),
	BuildService = require(script:WaitForChild("BuildService")),
	CameraService = require(script:WaitForChild("CameraService")),
	CraftingService = require(script:WaitForChild("CraftingService")),
	GoreService = require(script:WaitForChild("GoreService")),
	HpService = require(script:WaitForChild("HpService")),
	InventoryService = require(script:WaitForChild("InventoryService")),
	LiquidService = require(script:WaitForChild("LiquidService")),
	LootService = require(script:WaitForChild("LootService")),
	MagicService = require(script:WaitForChild("MagicService")),
	ManaService = require(script:WaitForChild("ManaService")),
	MeleeService = require(script:WaitForChild("MeleeService")),
	NpcService = require(script:WaitForChild("NpcService")),
	PlayerDataService = require(script:WaitForChild("PlayerDataService")),
	PlayerService = require(script:WaitForChild("PlayerService")),
	RagdollService = require(script:WaitForChild("RagdollServicePackets")),
	VFXService = require(script:WaitForChild("VfxService")),
	WeatherService = require(script:WaitForChild("WeatherService")),
	WorldGenerationService = require(script:WaitForChild("WorldGenerationService")),
	WorldSimulationService = require(script:WaitForChild("WorldSimulationService")),
} :: any

function Packets.Init(): ()
	return
end
return Packets
