--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Matter = require(ReplicatedStorage.Packages.Matter)
local TestEZ = require(ReplicatedStorage.Packages.TestEZ)
local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).load(script)
local Maid = require("Maid")
local Rx = require("Rx")

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
					activeWorld:insert(entityId, Position({
						x = position.x + 1,
					}))
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
	end)
end
