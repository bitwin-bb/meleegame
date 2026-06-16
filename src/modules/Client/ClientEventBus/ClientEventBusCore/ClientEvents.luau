local require = require(script.Parent.loader).load(script)

return {
	UIOpened = "UIOpened",
	UIClosed = "UIClosed",
	HotbarSelected = "HotbarSelected",
	InventoryOpened = "InventoryOpened",
	InventoryClosed = "InventoryClosed",
	CraftingOpened = "CraftingOpened",
	CraftingClosed = "CraftingClosed",
	CameraShakeRequested = "CameraShakeRequested",
	LocalEffectPlayed = "LocalEffectPlayed",
	SoundRequested = "SoundRequested",
	StateMachineChanged = "StateMachineChanged",
	InputModeChanged = "InputModeChanged",
	TooltipRequested = "TooltipRequested",
	DebugOverlayToggled = "DebugOverlayToggled",
}
