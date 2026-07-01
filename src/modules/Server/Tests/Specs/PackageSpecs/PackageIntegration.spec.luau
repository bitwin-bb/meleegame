local require = require(script.Parent.loader).load(script)

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Matter = require("Matter")
local TestEZ = require("TestEZ")

local Binder = require("Binder")
local AudioServiceUtils = require("AudioServiceUtils")
local Blocks = require("Blocks")
local Brio = require("Brio")
local BuildServiceUtils = require("BuildServiceUtils")
local Maid = require("Maid")
local Octree = require("Octree")
local GetItem = require("GetItem")
local Rx = require("Rx")
local RxSignal = require("RxSignal")
local TileItem = require("TileItem")
local VFXServiceUtils = require("VFXServiceUtils")
local GetImageId = require("GetImageId")

local PACKAGE_NAME = "AquariaBackup"

local function GetPackageRoot(): Instance
	return assert(ServerScriptService:FindFirstChild(PACKAGE_NAME), `missing {PACKAGE_NAME} package root`)
end

return function()
	describe("Package integrations", function()
		it("maps shared boss modules into the replicated package tree", function()
			local packageRoot = GetPackageRoot()
			local gameRoot = assert(packageRoot:FindFirstChild("game"), "missing package game root")
			local sharedRoot = assert(gameRoot:FindFirstChild("Shared"), "missing shared root")
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
			local sharedRoot = assert(gameRoot:FindFirstChild("Shared"), "missing shared root")
			local queenBeeConfigs =
				assert(sharedRoot:FindFirstChild("QueenBeeConfigs"), "missing shared QueenBeeConfigs module")

			expect(queenBeeConfigs:IsA("ModuleScript")).to.equal(true)
		end)

		it("maps shared npc definitions into the replicated package tree", function()
			local packageRoot = GetPackageRoot()
			local gameRoot = assert(packageRoot:FindFirstChild("game"), "missing package game root")
			local sharedRoot = assert(gameRoot:FindFirstChild("Shared"), "missing shared root")
			local definitions =
				assert(sharedRoot:FindFirstChild("NpcDefinitions"), "missing shared NpcDefinitions module")

			expect(definitions:IsA("ModuleScript")).to.equal(true)
		end)

		it("exposes TestEZ through the shared vendor tree", function()
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
			expect(AudioServiceUtils.collectSoundAssetIds).to.equal(nil)
			expect(AudioServiceUtils.createDefaultState).to.equal(nil)
			expect(AudioServiceUtils.serializePlaybackOptions).to.equal(nil)
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
