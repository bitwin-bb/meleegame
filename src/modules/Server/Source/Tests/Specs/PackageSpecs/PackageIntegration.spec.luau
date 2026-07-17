local require = require(script.Parent.loader).load(script)

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Fusion: any = require(ReplicatedStorage.Packages.Fusion)
local Matter = require("Matter")
local TestEZ = require("TestEZ")

local AtlasResolver = require("AtlasResolver")
local AudioServiceUtils = require("AudioServiceUtils")
local AutotileRegistry = require("AutotileRegistry")
local Binder = require("Binder")
local Blocks = require("Blocks")
local Brio: any = require("Brio")
local BuildServiceUtils = require("BuildServiceUtils")
local DirectionBits = require("DirectionBits")
local EightWayBlobRule = require("EightWayBlobRule")
local FourWay16Rule = require("FourWay16Rule")
local GetImageId = require("GetImageId")
local GetItem = require("GetItem")
local ItemIcons = require("ItemIcons")
local ItemRegistry = require("ItemRegistry")
local Maid = require("Maid")
local MaskResolver = require("MaskResolver")
local Octree = require("Octree")
local RectUtil = require("RectUtil")
local Rx: any = require("Rx")
local RxSignal: any = require("RxSignal")
local TileItem = require("TileItem")
local VFXServiceUtils = require("VfxServiceUtils")
local VariantPicker = require("VariantPicker")

local PACKAGE_NAME = "AquariaBackup"

local function GetPackageRoot(): Instance
	return assert(ServerScriptService:FindFirstChild(PACKAGE_NAME), `missing {PACKAGE_NAME} package root`)
end

local function GetClientModule(modulePath: { string }): ModuleScript
	local cursor = GetPackageRoot():FindFirstChild("game")
	for _, childName in modulePath do
		cursor = assert(cursor ~= nil and cursor:FindFirstChild(childName), `missing client module path {childName}`)
	end
	assert(cursor ~= nil and cursor:IsA("ModuleScript"), "client module path did not resolve to a module")
	return cursor :: ModuleScript
end

return function()
	describe("Package integrations", function()
		it("maps shared boss modules into the replicated package tree", function()
			local packageRoot = GetPackageRoot()
			local gameRoot = assert(packageRoot:FindFirstChild("game"), "missing package game root")
			local sharedRealm = assert(gameRoot:FindFirstChild("Shared"), "missing shared root")
			local sharedRoot = assert(sharedRealm:FindFirstChild("Source"), "missing shared source root")
			local eyeRoot = assert(sharedRoot:FindFirstChild("EyeOfCthulhuBoss"), "missing shared eye boss root")
			local motion = assert(eyeRoot:FindFirstChild("Motion"), "missing shared eye boss motion module")
			local presentation =
				assert(eyeRoot:FindFirstChild("Presentation"), "missing shared eye boss presentation module")

			expect(motion:IsA("ModuleScript")).to.equal(true)
			expect(presentation:IsA("ModuleScript")).to.equal(true)
		end)

		it("maps shared boss configs into the replicated package tree", function()
			local packageRoot = GetPackageRoot()
			local gameRoot = assert(packageRoot:FindFirstChild("game"), "missing package game root")
			local sharedRealm = assert(gameRoot:FindFirstChild("Shared"), "missing shared root")
			local sharedRoot = assert(sharedRealm:FindFirstChild("Source"), "missing shared source root")
			local queenBeeConfigs =
				assert(sharedRoot:FindFirstChild("QueenBeeConfigs"), "missing shared QueenBeeConfigs module")

			expect(queenBeeConfigs:IsA("ModuleScript")).to.equal(true)
		end)

		it("maps shared npc definitions into the replicated package tree", function()
			local packageRoot = GetPackageRoot()
			local gameRoot = assert(packageRoot:FindFirstChild("game"), "missing package game root")
			local sharedRealm = assert(gameRoot:FindFirstChild("Shared"), "missing shared root")
			local sharedRoot = assert(sharedRealm:FindFirstChild("Source"), "missing shared source root")
			local definitions =
				assert(sharedRoot:FindFirstChild("NpcDefinitions"), "missing shared NpcDefinitions module")

			expect(definitions:IsA("ModuleScript")).to.equal(true)
		end)

		it("exposes TestEZ through Nevermore from the shared vendor tree", function()
			local packageRoot = GetPackageRoot()
			local gameRoot = assert(packageRoot:FindFirstChild("game"), "missing package game root")
			local sharedRoot = assert(gameRoot:FindFirstChild("Shared"), "missing shared root")
			local vendorRoot = assert(sharedRoot:FindFirstChild("Vendor"), "missing shared vendor root")

			expect(vendorRoot:FindFirstChild("TestEZ") ~= nil).to.equal(true)
			expect(typeof(TestEZ.run)).to.equal("function")
			expect(typeof(TestEZ.TestBootstrap)).to.equal("table")
			expect(TestEZ.Reporters.TextReporter ~= nil).to.equal(true)
		end)

		it("exposes audio utilities through their canonical method names", function()
			expect(typeof(AudioServiceUtils.CollectSoundAssetIds)).to.equal("function")
			expect(typeof(AudioServiceUtils.GetSoundAssetId)).to.equal("function")
			expect(typeof(AudioServiceUtils.CreateDefaultState)).to.equal("function")
			expect(typeof(AudioServiceUtils.SerializePlaybackOptions)).to.equal("function")
			expect(typeof(AudioServiceUtils.CreateSoundInstance)).to.equal("function")
			expect((AudioServiceUtils :: any).collectSoundAssetIds).to.equal(nil)
			expect((AudioServiceUtils :: any).createDefaultState).to.equal(nil)
			expect((AudioServiceUtils :: any).serializePlaybackOptions).to.equal(nil)
		end)

		it("allows Maid to clean Rx subscriptions deterministically", function()
			local bindable = Instance.new("BindableEvent")
			local values = {}
			local maid = Maid.new()

			maid:GiveTask(Rx.fromSignal(bindable.Event):Subscribe(function(value)
				values[#values + 1] = value
			end))

			bindable:Fire(2)
			task.wait()
			bindable:Fire(4)
			task.wait()
			expect(#values).to.equal(2)
			expect(values[1]).to.equal(2)
			expect(values[2]).to.equal(4)

			maid:Destroy()
			bindable:Fire(8)
			expect(#values).to.equal(2)
			bindable:Destroy()
		end)

		it("lets Matter worlds and loops run scheduled systems", function()
			local Position = (Matter.component :: any)("PackageIntegrationPosition")
			local world = (Matter.World.new :: any)()
			local loop = (Matter.Loop.new :: any)(world)
			local tick = Instance.new("BindableEvent")
			local entityId = world:spawn(Position({
				x = 5,
			}))

			loop:scheduleSystem(function(activeWorld)
				for activeEntityId, position in activeWorld:query(Position) do
					activeWorld:insert(
						activeEntityId,
						Position({
							x = position.x + 1,
						})
					)
				end
			end)

			local connections = (loop.begin :: any)(loop, {
				default = tick.Event,
			})

			tick:Fire()
			task.wait()
			tick:Fire()
			task.wait()

			local position = world:Get(entityId, Position)
			expect(position.x).to.equal(7)

			connections.default:Disconnect()
			tick:Destroy()
		end)

		it("supports Brio lifetimes and RxSignal wrappers", function()
			local bindable = Instance.new("BindableEvent")
			local signal = RxSignal.new(Rx.fromSignal(bindable.Event))
			local brio = Brio.new("alive")
			local cleaned = 0
			local values = {}

			brio:ToMaid():GiveTask(function()
				cleaned += 1
			end)

			signal:Connect(function(value)
				values[#values + 1] = value
			end)

			bindable:Fire("hello")
			task.wait()
			brio:Kill()

			expect(values[1]).to.equal("hello")
			expect(cleaned).to.equal(1)
			bindable:Destroy()
		end)

		it("computes a side-view viewport camera without using perspective-heavy framing", function()
			local PlayerMain = require(GetClientModule({
				"Client",
				"Source",
				"Player",
				"Components",
				"PlayerMain",
			}))
			local boundsCFrame = CFrame.new(0, 5, -12)
			local boundsSize = Vector3.new(3, 8, 4)
			local viewportSize = Vector2.new(1280, 720)

			local distance = PlayerMain.GetViewportCameraDistance(boundsSize, viewportSize, 1, 1.18)
			local cameraCFrame = PlayerMain.GetViewportCameraCFrame(boundsCFrame, distance)

			expect(distance > 250).to.equal(true)
			expect(cameraCFrame.Position.X > boundsCFrame.Position.X).to.equal(true)
			expect(math.abs(cameraCFrame.LookVector.X + 1) < 0.001).to.equal(true)
			expect(math.abs(cameraCFrame.UpVector.Y - 1) < 0.001).to.equal(true)
		end)

		it("computes a world-space surface anchor for the side-view player viewport", function()
			local PlayerMain = require(GetClientModule({
				"Client",
				"Source",
				"Player",
				"Components",
				"PlayerMain",
			}))
			local boundsCFrame = CFrame.new(2, 7, -12)
			local boundsSize = Vector3.new(3, 8, 4)

			local anchorSize = PlayerMain.GetSurfaceAnchorSize(boundsSize, 1.18)
			local anchorCFrame = PlayerMain.GetSurfaceAnchorCFrame(boundsCFrame)

			expect(anchorSize.X).to.equal(2)
			expect(anchorSize.Y > boundsSize.Y).to.equal(true)
			expect(anchorSize.Z > boundsSize.Z).to.equal(true)
			expect(anchorCFrame.Position).to.equal(boundsCFrame.Position)
			expect(anchorCFrame.Position.X + anchorSize.X * 0.5).to.equal(boundsCFrame.Position.X + 1)
			expect(anchorCFrame.RightVector.X > 0.999).to.equal(true)
			expect(anchorCFrame.UpVector.Y > 0.999).to.equal(true)
			expect(PlayerMain.GetSurfacePixelsPerStud()).to.equal(8)
		end)

		it("mirrors the player viewport frame instead of flipping the cloned character", function()
			local PlayerMain = require(GetClientModule({
				"Client",
				"Source",
				"Player",
				"Components",
				"PlayerMain",
			}))

			local viewportPosition = PlayerMain.GetViewportFramePosition()
			local viewportSize = PlayerMain.GetViewportFrameSize()

			expect(viewportPosition.X.Scale).to.equal(1)
			expect(viewportPosition.Y.Scale).to.equal(0)
			expect(viewportSize.X.Scale).to.equal(-1)
			expect(viewportSize.Y.Scale).to.equal(1)
		end)

		it("normalizes mirrored player viewport frame measurements for camera math", function()
			local PlayerMain = require(GetClientModule({
				"Client",
				"Source",
				"Player",
				"Components",
				"PlayerMain",
			}))

			local measuredSize = PlayerMain.GetViewportFrameMeasuredSize(Vector2.new(-1280, 720))

			expect(measuredSize).to.equal(Vector2.new(1280, 720))
		end)

		it("keeps player viewport framing stable while animated bounds shift", function()
			local PlayerMain = require(GetClientModule({
				"Client",
				"Source",
				"Player",
				"Components",
				"PlayerMain",
			}))
			local initialBoundsCFrame = CFrame.new(0, 5, -12)
			local shiftedBoundsCFrame = CFrame.new(0, 5.4, -11.8)
			local rootCFrame = CFrame.new(0, 3, -12)

			local center, offset = PlayerMain.GetStableViewportCenter(initialBoundsCFrame, rootCFrame, nil)
			local shiftedCenter = PlayerMain.GetStableViewportCenter(shiftedBoundsCFrame, rootCFrame, offset)
			local stableBoundsSize =
				PlayerMain.GetStableViewportBoundsSize(Vector3.new(2, 7, 3), Vector3.new(1.8, 6.6, 3.5))
			local stableHalfExtents = PlayerMain.GetStableViewportHalfExtents(
				Vector3.new(1, 3.5, 1.5),
				center,
				shiftedBoundsCFrame,
				Vector3.new(2, 7, 3)
			)

			expect(center).to.equal(initialBoundsCFrame.Position)
			expect(shiftedCenter).to.equal(initialBoundsCFrame.Position)
			expect(stableBoundsSize.X).to.equal(2)
			expect(stableBoundsSize.Y).to.equal(7)
			expect(stableBoundsSize.Z).to.equal(3.5)
			expect(stableHalfExtents.X).to.equal(1)
			expect(stableHalfExtents.Y > 3.8).to.equal(true)
			expect(stableHalfExtents.Z > 1.6).to.equal(true)
		end)

		it("computes clamped player viewport smoothing alpha", function()
			local PlayerMain = require(GetClientModule({
				"Client",
				"Source",
				"Player",
				"Components",
				"PlayerMain",
			}))

			local smallFrameAlpha = PlayerMain.GetViewportSmoothingAlpha(30, 1 / 240)
			local normalFrameAlpha = PlayerMain.GetViewportSmoothingAlpha(30, 1 / 60)
			local hitchAlpha = PlayerMain.GetViewportSmoothingAlpha(30, 1)
			local clampedHitchAlpha = PlayerMain.GetViewportSmoothingAlpha(30, 1 / 15)

			expect(smallFrameAlpha > 0).to.equal(true)
			expect(normalFrameAlpha > smallFrameAlpha).to.equal(true)
			expect(normalFrameAlpha < 1).to.equal(true)
			expect(hitchAlpha).to.equal(clampedHitchAlpha)
			expect(PlayerMain.GetViewportSmoothingAlpha(0, 1 / 60)).to.equal(0)
		end)

		it("uses exact player viewport part cframes so facing flips are immediate", function()
			local PlayerMain = require(GetClientModule({
				"Client",
				"Source",
				"Player",
				"Components",
				"PlayerMain",
			}))
			local sourceCFrame = CFrame.new(4, 5, 6) * CFrame.Angles(0, math.pi, 0)

			expect(PlayerMain.GetViewportPartCFrame(sourceCFrame)).to.equal(sourceCFrame)
		end)

		it("only rebuilds the player viewport clone for structural character child changes", function()
			local PlayerMain = require(GetClientModule({
				"Client",
				"Source",
				"Player",
				"Components",
				"PlayerMain",
			}))
			local sound = Instance.new("Sound")
			local attachment = Instance.new("Attachment")
			local tool = Instance.new("Tool")
			local accessory = Instance.new("Accessory")
			local part = Instance.new("Part")

			expect(PlayerMain.ShouldRebuildForCharacterChild(sound)).to.equal(false)
			expect(PlayerMain.ShouldRebuildForCharacterChild(attachment)).to.equal(false)
			expect(PlayerMain.ShouldRebuildForCharacterChild(tool)).to.equal(true)
			expect(PlayerMain.ShouldRebuildForCharacterChild(accessory)).to.equal(true)
			expect(PlayerMain.ShouldRebuildForCharacterChild(part)).to.equal(true)

			sound:Destroy()
			attachment:Destroy()
			tool:Destroy()
			accessory:Destroy()
			part:Destroy()
		end)

		it("creates side-view loot icon models from inventory icons", function()
			local LootItemServer = require("LootItemServer")
			local model = LootItemServer.CreateModel({
				itemId = "CopperOre",
				amount = 3,
				name = "Loot_CopperOre",
				cframe = CFrame.new(2, 3, 4),
			})
			local root = model:FindFirstChild("Root")

			expect(model:IsA("Model")).to.equal(true)
			expect(model.Name).to.equal("Loot_CopperOre")
			expect(root ~= nil).to.equal(true)
			expect((root :: Instance):IsA("BasePart")).to.equal(true)
			expect(model.PrimaryPart).to.equal(root)
			expect((root :: BasePart).CollisionGroup).to.equal("LootItems")
			expect((root :: BasePart).CanCollide).to.equal(true)
			expect((root :: BasePart).AssemblyAngularVelocity).to.equal(Vector3.zero)

			local surfaceGui = (root :: Instance):FindFirstChild("LootIcon")
			expect(surfaceGui ~= nil).to.equal(true)
			expect((surfaceGui :: Instance):IsA("SurfaceGui")).to.equal(true)
			expect((surfaceGui :: SurfaceGui).Face).to.equal(Enum.NormalId.Right)

			local icon = (surfaceGui :: Instance):FindFirstChild("Icon")
			expect(icon ~= nil).to.equal(true)
			expect((icon :: Instance):IsA("ImageLabel")).to.equal(true)
			expect((icon :: ImageLabel).Image).to.equal("rbxassetid://86523519459129")

			model:Destroy()
		end)

		it("creates autotile sprites as Fusion surface gui block faces", function()
			local TileSprite = require(GetClientModule({
				"Client",
				"Source",
				"Autotile",
				"Render",
				"TileSprite",
			}))
			local parent = Instance.new("Folder")
			parent.Name = "AutotileSpriteSpec"

			local sprite = TileSprite.new(parent, 2, 3, {
				cframe = CFrame.new(4, 8, 12),
				size = Vector3.new(2, 2, 2),
				pixelsPerStud = 8,
			})
			sprite:Update({
				Image = "rbxassetid://115586684643692",
				ImageRectOffset = Vector2.new(36, 18),
				ImageRectSize = Vector2.new(16, 16),
			})

			local root = parent:FindFirstChild("AutotileRoot")
			expect(root ~= nil).to.equal(true)
			expect((root :: Instance):IsA("BasePart")).to.equal(true)
			expect((root :: BasePart).Anchored).to.equal(true)
			expect((root :: BasePart).CanCollide).to.equal(false)
			expect((root :: BasePart).CanQuery).to.equal(false)
			expect((root :: BasePart).CanTouch).to.equal(false)
			expect((root :: BasePart).Transparency).to.equal(1)
			expect((root :: BasePart).Material).to.equal(Enum.Material.SmoothPlastic)
			expect((root :: BasePart).MaterialVariant).to.equal("")
			expect((root :: BasePart).Size).to.equal(Vector3.new(2, 2, 2))
			expect((root :: BasePart).CFrame).to.equal(CFrame.new(4, 8, 12))

			local surfaceGui = (root :: Instance):FindFirstChild("AutotileSurface")
			expect(surfaceGui ~= nil).to.equal(true)
			expect((surfaceGui :: Instance):IsA("SurfaceGui")).to.equal(true)
			expect((surfaceGui :: SurfaceGui).Face).to.equal(Enum.NormalId.Right)
			expect((surfaceGui :: SurfaceGui).AlwaysOnTop).to.equal(false)
			expect((surfaceGui :: SurfaceGui).LightInfluence).to.equal(0)
			expect((surfaceGui :: SurfaceGui).SizingMode).to.equal(Enum.SurfaceGuiSizingMode.PixelsPerStud)
			expect((surfaceGui :: SurfaceGui).PixelsPerStud).to.equal(8)
			expect((surfaceGui :: SurfaceGui).Enabled).to.equal(true)

			local image = (surfaceGui :: Instance):FindFirstChild("AutotileImage")
			expect(image ~= nil).to.equal(true)
			expect((image :: Instance):IsA("ImageLabel")).to.equal(true)
			expect((image :: ImageLabel).Image).to.equal("rbxassetid://115586684643692")
			expect((image :: ImageLabel).ImageRectOffset).to.equal(Vector2.new(36, 18))
			expect((image :: ImageLabel).ImageRectSize).to.equal(Vector2.new(16, 16))
			expect((image :: ImageLabel).BackgroundTransparency).to.equal(1)
			expect((image :: ImageLabel).ResampleMode).to.equal(Enum.ResamplerMode.Pixelated)
			expect((image :: ImageLabel).ScaleType).to.equal(Enum.ScaleType.Stretch)

			sprite:Destroy()
			expect(parent:FindFirstChild("AutotileRoot")).to.equal(nil)
			parent:Destroy()
		end)

		it("skips non-surface autotile definitions without reading absent flags", function()
			local TileChunkRenderer = require(GetClientModule({
				"Client",
				"Source",
				"Autotile",
				"Render",
				"TileChunkRenderer",
			}))
			local chunk = Instance.new("Folder")
			chunk:SetAttribute("ChunkX", 0)
			chunk:SetAttribute("ChunkY", 0)
			chunk:SetAttribute("ChunkSize", 1)
			chunk:SetAttribute("Width", 1)
			chunk:SetAttribute("Height", 1)

			local renderService = {}
			function renderService.GetChunkSize(_self: any): number
				return 1
			end
			function renderService.GetTileData(_self: any, _tileX: number, _tileY: number): any
				return {
					TileId = BuildServiceUtils.TILE_ID.STONE,
					ConnectGroup = "Stone",
				}
			end

			local renderer = TileChunkRenderer.new(chunk, {
				renderService = renderService,
			})
			renderer:RenderInitial()

			local layer = chunk:FindFirstChild("AutotileLayer")
			expect(layer ~= nil).to.equal(true)
			expect((layer :: Instance):FindFirstChild("AutotileRoot", true)).to.equal(nil)

			renderer:Destroy()
			chunk:Destroy()
		end)

		it("renders only presentation chunks and clears broken autotiles without duplicates", function()
			local TileChunkClient = require(GetClientModule({
				"Client",
				"Source",
				"Autotile",
				"Binders",
				"TileChunkClient",
			}))
			local tileId = BuildServiceUtils.TILE_ID.DIRT
			local renderService = {}
			function renderService.GetChunkSize(_self: any): number
				return 1
			end
			function renderService.GetTileData(_self: any, tileX: number, tileY: number): any?
				if tileX ~= 0 or tileY ~= 0 or tileId == BuildServiceUtils.AIR_TILE_ID then
					return nil
				end
				return {
					TileId = tileId,
					ConnectGroup = "Soil",
				}
			end
			function renderService.GetTileSurfaceLayout(_self: any): any
				return {
					cframe = CFrame.new(0, 1, 1),
					size = Vector3.new(2, 2, 2),
					pixelsPerStud = 8,
				}
			end

			local function createChunk(isPresentation: boolean): Model
				local chunk = Instance.new("Model")
				chunk:SetAttribute("ChunkKey", "0:0")
				chunk:SetAttribute("ChunkSize", 1)
				chunk:SetAttribute("Width", 1)
				chunk:SetAttribute("Height", 1)
				chunk:SetAttribute("AutotilePresentationChunk", isPresentation)
				return chunk
			end

			local collisionChunk = createChunk(false)
			local presentationChunk = createChunk(true)
			local context = {
				renderService = renderService,
				tags = table.freeze({ "Chunk" }),
			}
			local collisionClient = TileChunkClient.new(collisionChunk, context)
			local presentationClient = TileChunkClient.new(presentationChunk, context)

			expect(collisionClient.renderer).to.equal(nil)
			expect(collisionChunk:FindFirstChild("AutotileLayer")).to.equal(nil)
			expect(presentationClient.renderer ~= nil).to.equal(true)
			local layer = presentationChunk:FindFirstChild("AutotileLayer")
			expect(layer ~= nil).to.equal(true)
			expect(#(layer :: Instance):GetChildren()).to.equal(1)

			tileId = BuildServiceUtils.AIR_TILE_ID
			presentationClient:UpdateTile(0, 0)
			expect(#(layer :: Instance):GetChildren()).to.equal(0)

			tileId = BuildServiceUtils.TILE_ID.DIRT
			presentationClient:UpdateTile(0, 0)
			presentationClient:UpdateTile(0, 0)
			expect(#(layer :: Instance):GetChildren()).to.equal(1)

			collisionClient:Destroy()
			presentationClient:Destroy()
			collisionChunk:Destroy()
			presentationChunk:Destroy()
		end)

		it("deduplicates overlapping autotile neighbor refreshes per delta payload", function()
			local AutotileRenderServiceClient = require(GetClientModule({
				"Client",
				"Source",
				"Autotile",
				"AutotileRenderServiceClient",
			}))
			local updates = {}
			local seen = {}
			local fakeSelf = {
				_chunkBinder = {
					UpdateTile = function(_chunkBinder: any, tileX: number, tileY: number)
						local tileKey = BuildServiceUtils.PackTileKey(tileX, tileY)
						expect(seen[tileKey] == nil).to.equal(true)
						seen[tileKey] = true
						updates[#updates + 1] = tileKey
					end,
				},
			}

			AutotileRenderServiceClient.OnTileDeltas(fakeSelf, {
				{ tileX = 0, tileY = 0 },
				{ tileX = 0, tileY = 0 },
				{ tileX = 1, tileY = 0 },
				{ tileX = nil, tileY = 0 },
			})

			expect(#updates).to.equal(12)
			expect(seen[BuildServiceUtils.PackTileKey(-1, -1)]).to.equal(true)
			expect(seen[BuildServiceUtils.PackTileKey(2, 1)]).to.equal(true)
		end)

		it("queues both sides of a streamed chunk boundary exactly once", function()
			local TileRenderServiceClient = require(GetClientModule({
				"Client",
				"Source",
				"Autotile",
				"TileRenderServiceClient",
			}))
			local updates = {}
			local scheduler = TileRenderServiceClient.new({
				maxTileUpdatesPerHeartbeat = 1000,
				updateTile = function(tileX: number, tileY: number)
					updates[BuildServiceUtils.PackTileKey(tileX, tileY)] = true
				end,
			})

			expect(scheduler:QueueChunkBoundary("0:0", 4)).to.equal(32)
			expect(scheduler:QueueChunkBoundary("0:0", 4)).to.equal(0)
			scheduler._flushRequested = true
			expect(scheduler:Flush()).to.equal(32)
			expect(updates[BuildServiceUtils.PackTileKey(-1, -1)]).to.equal(true)
			expect(updates[BuildServiceUtils.PackTileKey(4, 4)]).to.equal(true)
			expect(updates[BuildServiceUtils.PackTileKey(1, 1)]).to.equal(nil)

			scheduler:Destroy()
		end)

		it("uses indexed autotile chunks before scanning bound chunks", function()
			local TileChunkBinderClient = require(GetClientModule({
				"Client",
				"Source",
				"Autotile",
				"Binders",
				"TileChunkBinderClient",
			}))
			local scanned = false
			local updated = false
			local fakeChunkClient = {
				ContainsTile = function(_chunkClient: any, tileX: number, tileY: number): boolean
					return tileX == 3 and tileY == 4
				end,
				UpdateTile = function(_chunkClient: any, tileX: number, tileY: number)
					updated = tileX == 3 and tileY == 4
				end,
			}
			local fakeSelf = {
				_renderService = {
					GetChunkSize = function(_renderService: any): number
						return 32
					end,
				},
				_chunkClientsByKey = {
					[BuildServiceUtils.PackChunkKey(0, 0)] = fakeChunkClient,
				},
				_binder = {
					GetAll = function(_binder: any): { any }
						scanned = true
						return {}
					end,
				},
			}

			TileChunkBinderClient.UpdateTile(fakeSelf, 3, 4)

			expect(updated).to.equal(true)
			expect(scanned).to.equal(false)
		end)

		it("creates dropped coin icons from their spritesheets for client viewport playback", function()
			local LootItemServer = require("LootItemServer")
			local model = LootItemServer.CreateModel({
				itemId = "CopperCoin",
				amount = 7,
				name = "Loot_CopperCoin",
			})
			local root = model:FindFirstChild("Root")
			expect(root ~= nil).to.equal(true)

			local surfaceGui = (root :: Instance):FindFirstChild("LootIcon")
			expect(surfaceGui ~= nil).to.equal(true)

			local icon = (surfaceGui :: Instance):FindFirstChild("Icon")
			expect(icon ~= nil).to.equal(true)
			expect((icon :: Instance):IsA("ImageLabel")).to.equal(true)
			expect((root :: BasePart).CollisionGroup).to.equal("LootItems")
			expect((root :: BasePart).CanCollide).to.equal(true)
			expect((icon :: ImageLabel).Image).to.equal("rbxassetid://138124828857039")
			expect((icon :: ImageLabel).ImageRectSize).to.equal(Vector2.new(258, 258))
			expect((icon :: ImageLabel).ImageRectOffset).to.equal(Vector2.zero)
			expect((icon :: ImageLabel).ResampleMode).to.equal(Enum.ResamplerMode.Pixelated)
			expect((icon :: Instance):GetAttribute("LootIconAnimated")).to.equal(true)
			expect((icon :: Instance):GetAttribute("LootIconItemId")).to.equal("CopperCoin")

			model:Destroy()
		end)

		it("builds tile tools through TileItem and Blocks", function()
			local scope = Fusion.scoped(Fusion)
			local tileItem = TileItem.new(scope)
			local woodTool = tileItem:NewTile("Wood")

			expect(woodTool:IsA("Tool")).to.equal(true)
			expect(woodTool:GetAttribute("itemId")).to.equal("Wood")
			expect(woodTool:GetAttribute("itemType")).to.equal("Tile")
			expect(woodTool:FindFirstChild("Handle") ~= nil).to.equal(true)
			expect(woodTool:FindFirstChild("Contents") ~= nil).to.equal(true)

			Fusion.doCleanup(scope)
		end)

		it("builds tool templates for every shared tile block", function()
			local tileItemIds = {
				"Wood",
				"Dirt",
				"Stone",
				"Snow",
				"Ice",
				"Mud",
				"RichMahogany",
				"EbonStone",
			}

			for _, itemId in tileItemIds do
				expect(typeof(Blocks[itemId])).to.equal("function")

				local resolution = GetItem.Get(itemId)
				local tool = resolution.toolTemplate

				expect(tool ~= nil).to.equal(true)
				expect((tool :: Tool):IsA("Tool")).to.equal(true)
				expect((tool :: Tool):GetAttribute("itemId")).to.equal(itemId)
				expect((tool :: Tool):GetAttribute("itemType")).to.equal("Tile")
				expect((tool :: Tool):FindFirstChild("Handle") ~= nil).to.equal(true)
				expect((tool :: Tool):FindFirstChild("Contents") ~= nil).to.equal(true)
			end
		end)

		it("gets break drops for every shared tile block", function()
			local expectedDrops = {
				[BuildServiceUtils.TILE_ID.WOOD] = "Wood",
				[BuildServiceUtils.TILE_ID.DIRT] = "Dirt",
				[BuildServiceUtils.TILE_ID.STONE] = "Stone",
				[BuildServiceUtils.TILE_ID.SNOW] = "Snow",
				[BuildServiceUtils.TILE_ID.ICE] = "Ice",
				[BuildServiceUtils.TILE_ID.MUD] = "Mud",
				[BuildServiceUtils.TILE_ID.CORRUPT_STONE] = "EbonStone",
			}

			for tileId, expectedItemId in expectedDrops do
				expect(BuildServiceUtils.GetTileBreakDropItemId(tileId)).to.equal(expectedItemId)
			end
		end)

		it("registers the command-only dirt autotile test item", function()
			local itemId = ItemRegistry.GetCanonicalItemId("Dirt Autotile Test")
			expect(itemId).to.equal("DirtAutotileTest")

			local definition = ItemRegistry.GetDefinition(itemId)
			expect(definition ~= nil).to.equal(true)
			expect((definition :: any).name).to.equal("Dirt Autotile Test")
			expect((definition :: any).commandOnly).to.equal(true)
			expect(ItemIcons.dirtAutotileTest).to.equal(ItemIcons.dirt)

			local placeableConfig = BuildServiceUtils.GetPlaceableItemConfig(itemId)
			expect(placeableConfig ~= nil).to.equal(true)
			expect((placeableConfig :: BuildServiceUtils.PlaceableItemConfig).tileId).to.equal(
				BuildServiceUtils.TILE_ID.DIRT
			)
		end)

		it("resolves autotile masks, atlas cells, and deterministic variants", function()
			local tiles = {
				["0:0"] = { TileId = BuildServiceUtils.TILE_ID.DIRT, ConnectGroup = "soil" },
				["0:1"] = { TileId = BuildServiceUtils.TILE_ID.DIRT, ConnectGroup = "soil" },
				["1:0"] = { TileId = BuildServiceUtils.TILE_ID.MUD, ConnectGroup = "soil" },
				["1:1"] = { TileId = BuildServiceUtils.TILE_ID.DIRT, ConnectGroup = "soil" },
				["-1:0"] = { TileId = BuildServiceUtils.TILE_ID.STONE, ConnectGroup = "stone" },
				["0:-1"] = { TileId = BuildServiceUtils.TILE_ID.STONE, ConnectGroup = "stone" },
				["-1:-1"] = { TileId = BuildServiceUtils.TILE_ID.DIRT, ConnectGroup = "soil" },
			}

			local function getTile(x: number, y: number)
				return tiles[`{x}:{y}`]
			end

			local eightWayMask = MaskResolver.Resolve(getTile, Vector2.new(0, 0), EightWayBlobRule)
			expect(bit32.band(eightWayMask, DirectionBits.N)).to.equal(DirectionBits.N)
			expect(bit32.band(eightWayMask, DirectionBits.E)).to.equal(DirectionBits.E)
			expect(bit32.band(eightWayMask, DirectionBits.NE)).to.equal(DirectionBits.NE)
			expect(bit32.band(eightWayMask, DirectionBits.NW)).to.equal(0)

			local fourWayMask = MaskResolver.Resolve(getTile, Vector2.new(0, 0), FourWay16Rule)
			expect(fourWayMask).to.equal(DirectionBits.N + DirectionBits.E)
			expect(DirectionBits.MirrorHorizontal(DirectionBits.N + DirectionBits.E + DirectionBits.SE)).to.equal(
				DirectionBits.N + DirectionBits.W + DirectionBits.SW
			)
			expect(DirectionBits.MirrorHorizontal(DirectionBits.AllMask)).to.equal(DirectionBits.AllMask)
			expect(DirectionBits.MirrorHorizontal(DirectionBits.MirrorHorizontal(eightWayMask))).to.equal(eightWayMask)

			local rect = RectUtil.FromCell(Vector2.new(2, 3), 16, 1, 2)
			expect(rect.ImageRectOffset).to.equal(Vector2.new(37, 55))
			expect(rect.ImageRectSize).to.equal(Vector2.new(16, 16))
			local imageRectScale = Vector2.new(148 / 288, 1017 / 1980)
			local scaledRect = RectUtil.FromCell(Vector2.new(2, 3), 16, 1, 2, imageRectScale)
			expect(scaledRect.ImageRectOffset).to.equal(
				Vector2.new(37 * imageRectScale.X, 55 * imageRectScale.Y)
			)
			expect(scaledRect.ImageRectSize).to.equal(
				Vector2.new(16 * imageRectScale.X, 16 * imageRectScale.Y)
			)

			local atlas = {
				Image = "rbxassetid://123",
				TileSize = 16,
				Padding = 1,
				Spacing = 2,
				Entries = {
					[3] = { Cell = Vector2.new(3, 0) },
					[255] = {
						Variants = {
							{ Cell = Vector2.new(0, 4), Weight = 70 },
							{ Cell = Vector2.new(1, 4), Weight = 30 },
						},
					},
				},
				Aliases = {
					[DirectionBits.N + DirectionBits.E + DirectionBits.NE] = 3,
				},
				Fallback = { Cell = Vector2.new(9, 9) },
			}

			local resolvedAlias = AtlasResolver.Resolve(atlas, eightWayMask, Vector2.new(0, 0), 17)
			expect(resolvedAlias.Image).to.equal("rbxassetid://123")
			expect(resolvedAlias.ImageRectOffset).to.equal(Vector2.new(55, 1))
			expect(resolvedAlias.ImageRectSize).to.equal(Vector2.new(16, 16))
			expect(resolvedAlias.Mask).to.equal(3)

			local firstVariant = VariantPicker.Pick(atlas.Entries[255].Variants, Vector2.new(12, -4), 255, 42)
			local secondVariant = VariantPicker.Pick(atlas.Entries[255].Variants, Vector2.new(12, -4), 255, 42)
			expect(firstVariant).to.equal(secondVariant)

			local dirtDefinition = AutotileRegistry.GetDefinition(BuildServiceUtils.TILE_ID.DIRT)
			local grassDefinition = AutotileRegistry.GetDefinition(BuildServiceUtils.TILE_ID.GRASS)
			expect(dirtDefinition ~= nil).to.equal(true)
			expect((dirtDefinition :: any).Image).to.equal("rbxassetid://115586684643692")
			expect((dirtDefinition :: any).TileSize).to.equal(16)
			expect((dirtDefinition :: any).Spacing).to.equal(2)
			expect((dirtDefinition :: any).UseSurfaceGui).to.equal(true)
			expect(grassDefinition ~= nil).to.equal(true)
			expect((grassDefinition :: any).Image).to.equal("rbxassetid://104962191554416")
			expect((grassDefinition :: any).TileSize).to.equal(16)
			expect((grassDefinition :: any).Spacing).to.equal(2)
			expect((grassDefinition :: any).ImageRectScale).to.equal(imageRectScale)
			expect((grassDefinition :: any).UseSurfaceGui).to.equal(true)
			expect((grassDefinition :: any).ConnectGroup).to.equal((dirtDefinition :: any).ConnectGroup)

			local filledDirtTiles = {}
			for x = -1, 1 do
				for y = -1, 1 do
					filledDirtTiles[`{x}:{y}`] = { TileId = BuildServiceUtils.TILE_ID.DIRT, ConnectGroup = "soil" }
				end
			end

			local function getFilledDirtTile(x: number, y: number)
				return filledDirtTiles[`{x}:{y}`]
			end

			local filledDirtMask = MaskResolver.Resolve(getFilledDirtTile, Vector2.zero, EightWayBlobRule)
			expect(filledDirtMask).to.equal(DirectionBits.AllMask)

			local expectedDirtCells = {
				[0] = Vector2.new(9, 3),
				[DirectionBits.N] = Vector2.new(6, 3),
				[DirectionBits.E] = Vector2.new(9, 0),
				[DirectionBits.N + DirectionBits.E] = Vector2.new(0, 4),
				[DirectionBits.S] = Vector2.new(6, 0),
				[DirectionBits.N + DirectionBits.S] = Vector2.new(5, 0),
				[DirectionBits.E + DirectionBits.S] = Vector2.new(0, 3),
				[DirectionBits.N + DirectionBits.E + DirectionBits.S] = Vector2.new(0, 0),
				[DirectionBits.W] = Vector2.new(12, 0),
				[DirectionBits.N + DirectionBits.W] = Vector2.new(1, 4),
				[DirectionBits.E + DirectionBits.W] = Vector2.new(6, 4),
				[DirectionBits.N + DirectionBits.E + DirectionBits.W] = Vector2.new(13, 1),
				[DirectionBits.S + DirectionBits.W] = Vector2.new(1, 3),
				[DirectionBits.N + DirectionBits.S + DirectionBits.W] = Vector2.new(4, 0),
				[DirectionBits.E + DirectionBits.S + DirectionBits.W] = Vector2.new(1, 0),
				[DirectionBits.CardinalMask] = Vector2.new(1, 1),
			}

			for mask, expectedCell in expectedDirtCells do
				local entry = (dirtDefinition :: any).Entries[mask]
				expect(#entry.Variants).to.equal(1)
				expect(entry.Variants[1].Cell).to.equal(expectedCell)
			end
			for mask = 0, DirectionBits.AllMask do
				local cardinalMask = bit32.band(mask, DirectionBits.CardinalMask)
				local entry = (dirtDefinition :: any).Entries[mask]
				expect(entry.Variants[1].Cell).to.equal(expectedDirtCells[cardinalMask])
				local grassEntry = (grassDefinition :: any).Entries[mask]
				local expectedGrassCell = if cardinalMask == DirectionBits.N + DirectionBits.E + DirectionBits.W
					then Vector2.new(1, 2)
					else expectedDirtCells[cardinalMask]
				expect(grassEntry.Variants[1].Cell).to.equal(expectedGrassCell)
			end
			local grassBottomEdgeMask = DirectionBits.N + DirectionBits.E + DirectionBits.W
			local grassBottomEdgeResolved = AtlasResolver.Resolve(grassDefinition, grassBottomEdgeMask, Vector2.zero, 0)
			expect(grassBottomEdgeResolved.Cell).to.equal(Vector2.new(1, 2))
			expect(grassBottomEdgeResolved.ImageRectOffset).to.equal(
				Vector2.new(18 * imageRectScale.X, 36 * imageRectScale.Y)
			)
			expect(grassBottomEdgeResolved.ImageRectSize).to.equal(
				Vector2.new(16 * imageRectScale.X, 16 * imageRectScale.Y)
			)
			expect((dirtDefinition :: any).Entries[DirectionBits.CardinalMask].Variants[1].Cell).to.equal(
				Vector2.new(1, 1)
			)
			expect((dirtDefinition :: any).Entries[DirectionBits.AllMask].Variants[1].Cell).to.equal(Vector2.new(1, 1))

			local topEdgeMask = DirectionBits.E
				+ DirectionBits.S
				+ DirectionBits.W
				+ DirectionBits.SE
				+ DirectionBits.SW
			local topEdgeResolved = AtlasResolver.Resolve(dirtDefinition, topEdgeMask, Vector2.zero, 0)
			expect(topEdgeResolved.Mask).to.equal(topEdgeMask)
			expect(topEdgeResolved.Cell).to.equal(Vector2.new(1, 0))

			local cardinalOnlyFullMask = DirectionBits.N + DirectionBits.E + DirectionBits.S + DirectionBits.W
			expect((dirtDefinition :: any).Entries[cardinalOnlyFullMask].Variants[1].Cell).to.equal(Vector2.new(1, 1))

			local topDiagonalGapMask = cardinalOnlyFullMask + DirectionBits.SE
			local rightDiagonalGapMask = cardinalOnlyFullMask + DirectionBits.NW + DirectionBits.SW
			local leftDiagonalGapMask = cardinalOnlyFullMask + DirectionBits.NE + DirectionBits.SE
			expect((dirtDefinition :: any).Entries[topDiagonalGapMask].Variants[1].Cell).to.equal(Vector2.new(1, 1))
			expect((dirtDefinition :: any).Entries[rightDiagonalGapMask].Variants[1].Cell).to.equal(Vector2.new(1, 1))
			expect((dirtDefinition :: any).Entries[leftDiagonalGapMask].Variants[1].Cell).to.equal(Vector2.new(1, 1))

			local filledDirtResolved = AtlasResolver.Resolve(dirtDefinition, DirectionBits.AllMask, Vector2.zero, 0)
			expect(filledDirtResolved.Mask).to.equal(DirectionBits.AllMask)
			expect(filledDirtResolved.Cell).to.equal(Vector2.new(1, 1))
			expect(filledDirtResolved.ImageRectOffset.Y).to.equal(18)
			expect(filledDirtResolved.ImageRectSize).to.equal(Vector2.new(16, 16))

			for mask = 0, DirectionBits.AllMask do
				local resolved = AtlasResolver.Resolve(dirtDefinition, mask, Vector2.zero, 0)
				expect(resolved ~= nil).to.equal(true)
				expect(resolved.Mask).to.equal(mask)
			end

			local grassAboveDirtTiles = {
				["0:0"] = {
					TileId = BuildServiceUtils.TILE_ID.GRASS,
					ConnectGroup = (grassDefinition :: any).ConnectGroup,
				},
				["0:-1"] = {
					TileId = BuildServiceUtils.TILE_ID.DIRT,
					ConnectGroup = (dirtDefinition :: any).ConnectGroup,
				},
			}
			local function getGrassAboveDirtTile(x: number, y: number)
				return grassAboveDirtTiles[`{x}:{y}`]
			end

			local grassToDirtMask = MaskResolver.Resolve(getGrassAboveDirtTile, Vector2.zero, EightWayBlobRule)
			expect(grassToDirtMask).to.equal(DirectionBits.S)
			local grassToDirtResolved = AtlasResolver.Resolve(grassDefinition, grassToDirtMask, Vector2.zero, 0)
			expect(grassToDirtResolved.Cell).to.equal(Vector2.new(6, 0))
			expect(grassToDirtResolved.ImageRectOffset).to.equal(Vector2.new(108 * imageRectScale.X, 0))

			local AutotileRenderServiceClient = require(GetClientModule({
				"Client",
				"Source",
				"Autotile",
				"AutotileRenderServiceClient",
			}))
			local layoutService = {}
			function layoutService.GetTileSize(_self: any): number
				return 2
			end
			function layoutService.GetWorldOrigin(_self: any): Vector3
				return Vector3.new(10, 20, 30)
			end
			function layoutService.GetBasePlaneX(_self: any): number
				return 3
			end
			local grassLayout = AutotileRenderServiceClient.GetTileSurfaceLayout(
				layoutService,
				0,
				0,
				grassDefinition,
				grassToDirtResolved
			)
			expect(grassLayout.pixelsPerStud).to.equal(8)
			expect(grassLayout.size).to.equal(Vector3.new(2, 2, 2))
			expect(grassLayout.cframe.Position).to.equal(Vector3.new(13, 21, 31))
			expect(grassLayout.cframe.Position.X + grassLayout.size.X * 0.5).to.equal(14)

			grassAboveDirtTiles["0:0"].TileId = BuildServiceUtils.TILE_ID.DIRT
			grassAboveDirtTiles["0:-1"].TileId = BuildServiceUtils.TILE_ID.GRASS
			local dirtToGrassMask = MaskResolver.Resolve(getGrassAboveDirtTile, Vector2.zero, EightWayBlobRule)
			expect(dirtToGrassMask).to.equal(DirectionBits.S)

			expect(AutotileRegistry.HasDefinition(BuildServiceUtils.TILE_ID.GRASS)).to.equal(true)
			expect(AutotileRegistry.HasDefinition(BuildServiceUtils.TILE_ID.STONE)).to.equal(true)
			expect(AutotileRegistry.GetAtlas(BuildServiceUtils.TILE_ID.GRASS)).to.equal(grassDefinition)
		end)

		it("supports Octree spatial queries and Binder instance lifetimes", function()
			local octree = Octree.new()
			local nodeA = octree:CreateNode(Vector3.new(0, 0, 0), "A")
			local nodeB = octree:CreateNode(Vector3.new(20, 0, 0), "B")
			local nearby = octree:RadiusSearch(Vector3.zero, 10)
			expect(#nearby).to.equal(1)
			expect(nearby[1]).to.equal("A")

			local binder = Binder.new("PackageIntegrationBinderSpec", function(inst: Instance)
				return {
					instance = inst,
					Destroy = function(self: any)
						self.destroyed = true
					end,
				}
			end)
			binder:Start()

			local folder = Instance.new("Folder")
			folder.Name = "BoundFolder"
			folder.Parent = workspace
			CollectionService:AddTag(folder, "PackageIntegrationBinderSpec")
			task.wait()

			local bound = binder:Get(folder)
			expect(bound ~= nil).to.equal(true)
			CollectionService:RemoveTag(folder, "PackageIntegrationBinderSpec")
			task.wait()
			expect(binder:Get(folder)).to.equal(nil)

			nodeA:Destroy()
			nodeB:Destroy()
			folder:Destroy()
			binder:Destroy()
		end)

		it("throws when asset resolution cannot find a matching asset", function()
			expect(function()
				GetItem.GetPrimaryTemplate("__missing_asset_spec__")
			end).to.throw("no asset found!")

			expect(function()
				VFXServiceUtils.GetEffectTemplate("__missing_asset_spec__")
			end).to.throw("no asset found!")

			expect(function()
				GetImageId(nil, "rbxassetid://1")
			end).to.throw("no asset found!")
		end)
	end)
end
