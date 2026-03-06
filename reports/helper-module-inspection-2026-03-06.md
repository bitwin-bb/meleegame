# Helper Module Inspection Report (2026-03-06)

## Scope
- Static inspection of all Luau/Lua files under `src/` (310 scripts).
- Dependency map built from 664 `require(...)` edges.
- Script-relative cycle analysis: **0 cycles detected**.
- Unresolved script-relative requires (1):
  - `src/services/GoreService/Client.luau` -> `script.Parent.GoreServiceUtils`

## Package Inventory
- `classes`: 34
- `modules`: 93
- `services`: 96
- `startup`: 2
- `ui`: 85

## Helper Usage Map
### Core Helpers
- **Codec**: 6 requiring scripts
  - `src/modules/Core/Codec.luau`
  - `src/modules/Core/Infrastructure/AttributeCache.luau`
  - `src/modules/Core/Infrastructure/BinaryStreaming.luau`
  - `src/modules/Core/Infrastructure/TileMetadataRegistry.luau`
  - `src/modules/Core/Infrastructure/WorldMutationQueue.luau`
  - `src/modules/Core/Infrastructure/init.luau`
- **BinaryStreaming**: 4 requiring scripts
  - `src/modules/Core/BinaryStream.luau`
  - `src/modules/Core/BinaryStreaming.luau`
  - `src/modules/Core/Infrastructure/WorldMutationQueue.luau`
  - `src/modules/Core/Infrastructure/init.luau`
- **TickScheduler**: 4 requiring scripts
  - `src/modules/Core/Infrastructure/init.luau`
  - `src/modules/Core/Runtime.luau`
  - `src/modules/Core/TickSchedular.luau`
  - `src/modules/Core/TickScheduler.luau`
- **TickSchedular**: 0 requiring scripts
- **AttributeCache**: 2 requiring scripts
  - `src/modules/Core/AttributeCache.luau`
  - `src/modules/Core/Infrastructure/init.luau`
- **DamagePipeline**: 2 requiring scripts
  - `src/modules/Core/DamagePipeline.luau`
  - `src/modules/Core/Infrastructure/init.luau`
- **ObjectPool**: 3 requiring scripts
  - `src/modules/Core/Infrastructure/init.luau`
  - `src/modules/Core/ObjectPool.luau`
  - `src/services/WorldSimulationService/Cache.luau`
- **WorldMutationQueue**: 2 requiring scripts
  - `src/modules/Core/Infrastructure/init.luau`
  - `src/modules/Core/WorldMutationQueue.luau`

### UI Helpers
- **UIController**: 0 requiring scripts
- **UISpringAnimator**: 0 requiring scripts
- **VirtualizedList**: 0 requiring scripts
- **ReactiveState**: 0 requiring scripts
- **TooltipManager**: 0 requiring scripts
- **NotificationBus**: 0 requiring scripts
- **HUDLayoutEngine**: 0 requiring scripts

### String Helpers
- **RichTextFormatter**: 2 requiring scripts
  - `src/modules/UI/StatStringBuilder.luau`
  - `src/modules/UI/TooltipManager.luau`
- **StatStringBuilder**: 1 requiring scripts
  - `src/modules/UI/TooltipManager.luau`
- **LocalizationEngine**: 0 requiring scripts
- **DynamicTextResolver**: 2 requiring scripts
  - `src/modules/UI/LocalizationEngine.luau`
  - `src/modules/UI/TooltipManager.luau`
- **TextMeasurementCache**: 1 requiring scripts
  - `src/modules/UI/TooltipManager.luau`
- **AbbreviationFormatter**: 2 requiring scripts
  - `src/modules/UI/DynamicTextResolver.luau`
  - `src/modules/UI/StatStringBuilder.luau`

### Platform Helpers
- **Platform**: 2 requiring scripts
  - `src/modules/Core/Runtime.luau`
  - `src/modules/UI/UIController.luau`
- **Input**: 2 requiring scripts
  - `src/modules/Core/Runtime.luau`
  - `src/ui/features/info/state/infoThunks.luau`
- **HUDScaler**: 1 requiring scripts
  - `src/modules/Core/Runtime.luau`
- **Gestures**: 1 requiring scripts
  - `src/modules/Core/Runtime.luau`
- **GamepadNav**: 1 requiring scripts
  - `src/modules/Core/Runtime.luau`
- **PerfTier**: 1 requiring scripts
  - `src/modules/Core/Runtime.luau`
- **Haptics**: 1 requiring scripts
  - `src/modules/Core/Runtime.luau`
- **Cursor**: 1 requiring scripts
  - `src/modules/Core/Runtime.luau`

## Repetition Signals (Opportunities)
- UserInputService.InputBegan:Connect: 12 matches across 12 files
- UserInputService.InputChanged:Connect: 9 matches across 9 files
- UserInputService.InputEnded:Connect: 8 matches across 8 files
- RunService.RenderStepped:Connect: 27 matches across 26 files
- RunService.Heartbeat:Connect: 28 matches across 28 files
- task.delay: 27 matches across 19 files
- task.wait: 14 matches across 8 files
- :GetAttribute: 93 matches across 24 files
- :SetAttribute: 77 matches across 12 files
- buffer.* usage: 68 matches across 4 files
- TextService:GetTextSize: 1 matches across 1 files
- custom createObjectPool: 1 matches across 1 files

### Input Centralization Candidates
- `src/modules/Platform/Cursor.luau`
- `src/modules/Platform/GamepadNav.luau`
- `src/modules/Platform/Gestures.luau`
- `src/modules/Platform/Input.luau`
- `src/modules/UI/UIController.luau`
- `src/services/BuildService/Client.luau`
- `src/services/MagicService/Client.luau`
- `src/services/MeleeService/Client.luau`
- `src/ui/features/crafting/hooks/useCraftMenuDrag.luau`
- `src/ui/features/info/state/infoThunks.luau`
- `src/ui/features/infoPlayer/state/infoPlayerThunks.luau`
- `src/ui/features/inventory/hud/inventoryHotbar.luau`
- `src/ui/features/item/hooks/useDrag.luau`
- `src/ui/features/mouse/state/mouseThunks.luau`

### TickScheduler Candidates (frame/heartbeat loops + task scheduling)
- `src/classes/EnemyHitbox/init.luau`
- `src/classes/Gore/Gib.luau`
- `src/classes/Npc/AiTypes/slime.luau`
- `src/classes/Npc/init.luau`
- `src/classes/Rubble.luau`
- `src/classes/WorldGeneration/init.luau`
- `src/modules/Core/Runtime.luau`
- `src/modules/Platform/Cursor.luau`
- `src/modules/Platform/PerfTier.luau`
- `src/modules/UI/NotificationBus.luau`
- `src/modules/UI/TooltipManager.luau`
- `src/modules/UI/UISpringAnimator.luau`
- `src/services/BuildService/Client.luau`
- `src/services/BuildService/Server.luau`
- `src/services/CraftingService/Client.luau`
- `src/services/CraftingService/Server.luau`
- `src/services/CraftingService/Utils.luau`
- `src/services/GoreService/Client.luau`
- `src/services/LootService/Server.luau`
- `src/services/MagicService/Client.luau`
- `src/services/MagicService/Server.luau`
- `src/services/ManaService/Server.luau`
- `src/services/NpcService/Server.luau`
- `src/services/RagdollService/Server.luau`
- `src/services/SoundService/Client.luau`
- `src/services/WeatherService/Client.luau`
- `src/services/WeatherService/Server.luau`
- `src/services/WorldAnimatorService/Client.luau`
- `src/services/WorldGenerationService/Client.luau`
- `src/services/WorldGenerationService/Server.luau`
- `src/services/WorldSimulationService/Client.luau`
- `src/services/WorldSimulationService/Server.luau`
- `src/ui/core/components/DropsInfo.luau`
- `src/ui/core/primitives/TextLabel.luau`
- `src/ui/features/biome/hooks/useBiomeNameAppearance.luau`
- `src/ui/features/biome/hooks/useTextUnderline.luau`
- `src/ui/features/biome/state/biomeThunks.luau`
- `src/ui/features/crafting/hooks/useCraftMenuDrag.luau`
- `src/ui/features/crafting/hooks/useCraftSlide.luau`
- `src/ui/features/death/hooks/useCountDown.luau`
- `src/ui/features/death/hooks/useDeathScreen.luau`
- `src/ui/features/entityInfo/screens/entityInfoScreen.luau`
- `src/ui/features/entityInfo/state/entityInfoThunks.luau`
- `src/ui/features/hp/hooks/useBeatMotion.luau`
- `src/ui/features/infoPlayer/hooks/useInfoPopUp.luau`
- `src/ui/features/inventory/hooks/useCoinEmerge.luau`
- `src/ui/features/inventory/hooks/useInventorySlide.luau`
- `src/ui/features/inventory/hooks/useSlotSelect.luau`
- `src/ui/features/inventory/hooks/useTrashAppear.luau`
- `src/ui/features/item/hooks/useDrag.luau`
- `src/ui/features/mana/hooks/useManaTransparency.luau`
- `src/ui/features/miningProgress/hooks/useProgressBarSmoothing.luau`
- `src/ui/features/mouse/state/mouseThunks.luau`
- `src/ui/shared/Gif.luau`

### AttributeCache Candidates (direct attribute IO)
- `src/classes/Gore/LimbDestruction.luau`
- `src/classes/Gore/init.luau`
- `src/classes/Magic.luau`
- `src/classes/WorldGeneration/Tree.luau`
- `src/classes/WorldGeneration/init.luau`
- `src/modules/Core/Infrastructure/AttributeCache.luau`
- `src/modules/Platform/Cursor.luau`
- `src/modules/UI/ReactiveState.luau`
- `src/modules/UI/StatStringBuilder.luau`
- `src/services/AnimationService/Client.luau`
- `src/services/BuildService/Client.luau`
- `src/services/BuildService/Server.luau`
- `src/services/GoreService/Client.luau`
- `src/services/HpService/Server.luau`
- `src/services/InventoryService/Server.luau`
- `src/services/LootService/Server.luau`
- `src/services/MagicService/Server.luau`
- `src/services/MagicService/Utils.luau`
- `src/services/MeleeService/Utils.luau`
- `src/services/NpcService/Utils.luau`
- `src/services/PlayerService/Client.luau`
- `src/services/PlayerService/Server.luau`
- `src/services/WorldAnimatorService/Client.luau`
- `src/services/WorldAnimatorService/Utils.luau`
- `src/services/WorldGenerationService/Client.luau`
- `src/services/WorldSimulationService/Render.luau`
- `src/ui/features/mouse/state/mouseThunks.luau`

### ObjectPool Candidates
- `src/services/WorldSimulationService/Render.luau`

### Codec/BinaryStreaming Candidates (raw buffer/data paths)
- `src/modules/Core/Infrastructure/BinaryStreaming.luau`
- `src/modules/Core/Infrastructure/WorldMutationQueue.luau`
- `src/services/WorldSimulationService/Cache.luau`
- `src/services/WorldSimulationService/Data.luau`

### TextMeasurementCache Candidates
- `src/modules/UI/TextMeasurementCache.luau`

## Empty Platform Modules
- `src/modules/Platform/Haptics.luau`: 7141 bytes
- `src/modules/Platform/Cursor.luau`: 15033 bytes

## Safe Refactors Applied In This Pass
- `src/modules/UI/UIController.luau`
  - Added missing `clearArray` helper used in `:destroy()` cleanup.
  - Integrated optional Platform helper wiring (`platform:init`, `platform:onChanged`) with fallback to `UserInputService.LastInputTypeChanged`.
- `src/ui/features/info/state/infoThunks.luau`
  - Switched hover pointer tracking to Platform `Input` helper via `bindAction`.
  - Kept legacy `UserInputService.InputChanged` fallback if binding fails.
- `src/services/WorldSimulationService/Cache.luau`
  - Replaced local ad-hoc object pool internals with shared Core `ObjectPool` backend and preserved local API shape.
- Added canonical wrapper modules:
  - `src/modules/Core/TickScheduler.luau`
  - `src/modules/Core/BinaryStreaming.luau`

## Notes
- No script-relative circular dependencies were found in this static pass.
- Most listed helper modules are currently only referenced by their own module definitions; adoption across services/UI remains low and should be phased.
