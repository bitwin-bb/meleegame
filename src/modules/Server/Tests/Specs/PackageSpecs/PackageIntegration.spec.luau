--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Matter = require(ReplicatedStorage.Packages.Matter)
local TestEZ = require(ReplicatedStorage.Packages.TestEZ)
local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = require(loaderUtils.Parent).load(script)

local Binder = loader("Binder")
local Brio = loader("Brio")
local Maid = loader("Maid")
local Octree = loader("Octree")
local Rx = loader("Rx")
local RxSignal = loader("RxSignal")

return function()
	describe("Package integrations", function()
		it("exposes TestEZ through the shared packages tree", function()
			expect(typeof(TestEZ.run)).to.equal("function")
			expect(typeof(TestEZ.TestBootstrap)).to.equal("table")
			expect(TestEZ.Reporters.TextReporter ~= nil).to.equal(true)
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
			local Position = Matter.component("PackageIntegrationPosition")
			local world = Matter.World.new()
			local loop = Matter.Loop.new(world)
			local tick = Instance.new("BindableEvent")
			local entityId = world:spawn(Position({
				x = 5,
			}))

			loop:scheduleSystem(function(activeWorld)
				for entityId, position in activeWorld:query(Position) do
					activeWorld:insert(
						entityId,
						Position({
							x = position.x + 1,
						})
					)
				end
			end)

			local connections = loop:begin({
				default = tick.Event,
			})

			tick:Fire()
			task.wait()
			tick:Fire()
			task.wait()

			local position = world:get(entityId, Position)
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
	end)
end
