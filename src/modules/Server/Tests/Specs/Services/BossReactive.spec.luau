--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = require(loaderUtils.Parent).load(script)

local Maid = loader("Maid")
local BossBase = require(script:FindFirstAncestor("game").Shared.Features.npc.classes.Boss)
local BossServiceServer = require(script:FindFirstAncestor("game").Shared.Features.npc.BossServiceServer)
local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Features.npc.BossServiceUtils)
local EyeOfCthulhuConfig =
	require(script:FindFirstAncestor("game").Shared.Features.npc.classes.Boss.EyeOfCthulhu.Config)

local function createBossAssetTemplates()
	local assets = Instance.new("Folder")
	assets.Name = "Assets"
	assets.Parent = ReplicatedStorage

	local npcs = Instance.new("Folder")
	npcs.Name = "Npcs"
	npcs.Parent = assets

	local bosses = Instance.new("Folder")
	bosses.Name = "Bosses"
	bosses.Parent = npcs

	local eye = Instance.new("Folder")
	eye.Name = "EyeOfCthulhu"
	eye.Parent = bosses

	local phase = Instance.new("Folder")
	phase.Name = "Phase1"
	phase.Parent = eye

	local model = Instance.new("Model")
	model.Name = "EyeOfCthulhu"
	model.Parent = phase

	local rootPart = Instance.new("Part")
	rootPart.Name = "RootPart"
	rootPart.Anchored = true
	rootPart.Parent = model
	model.PrimaryPart = rootPart

	return assets
end

local function createTestService()
	local service = setmetatable({
		maid = Maid.new(),
		networker = {
			fire = function()
				return
			end,
			destroy = function()
				return
			end,
		},
		hpService = nil,
		weatherService = nil,
		worldGenerationService = nil,
		controllersById = {},
		controllersByChannel = {},
		boundModelsById = {},
		state = BossServiceUtils.createDefaultState(),
		statePushInterval = 0,
		naturalSpawnCheckInterval = BossServiceUtils.DEFAULT_NATURAL_SPAWN_CHECK_INTERVAL,
		naturalSpawnAccumulator = 0,
		random = Random.new(1337),
		world = nil,
		pendingNaturalSpawn = nil,
		allowClientManualSummon = false,
		defaultConfigByBossId = {
			EyeOfCthulhu = EyeOfCthulhuConfig.getDefaults(),
		},
		previousClockTime = 12,
	}, {
		__index = BossServiceServer,
	})

	service:initReactiveState()
	return service
end

local function createTestBoss(service)
	local definition = assert(BossServiceUtils.getRegistryEntryById("EyeOfCthulhu"))
	return BossBase.new(service, definition, {
		bossId = "EyeOfCthulhu",
		spawnSource = "DebugCommand",
		encounterChannel = "spec.eye",
		spawnPosition = Vector3.new(0, 30, 0),
	}, {
		maxHp = 150,
		defense = 4,
		contactDamage = 8,
	})
end

return function()
	describe("Boss reactive lifecycle", function()
		it("exposes stateful Rx streams and promise waits on the boss base class", function()
			local assetTemplates = createBossAssetTemplates()
			local service = createTestService()
			local boss = createTestBoss(service)
			local maid = Maid.new()
			local observedStates = {}
			local observedModelPresence = {}
			local snapshotStates = {}
			local modelBriosDied = 0

			maid:GiveTask(boss:observeState():Subscribe(function(state)
				table.insert(observedStates, state)
			end))
			maid:GiveTask(boss:observeModel():Subscribe(function(model)
				table.insert(observedModelPresence, model ~= nil)
			end))
			maid:GiveTask(boss:observeSnapshot():Subscribe(function(snapshot)
				table.insert(snapshotStates, snapshot.state)
			end))
			maid:GiveTask(boss:observeModelBrio():Subscribe(function(brio)
				maid:GiveTask(brio:GetDiedSignal():Connect(function()
					modelBriosDied += 1
				end))
			end))

			expect(observedStates[1]).to.equal("Dormant")
			expect(observedModelPresence[1]).to.equal(false)
			expect(snapshotStates[1]).to.equal("Dormant")

			local statePromise = boss:promiseState("Phase1Hover")
			boss:changeState("Phase1Hover", "spec_state")
			local stateOk, nextState = statePromise:Yield()
			expect(stateOk).to.equal(true)
			expect(nextState).to.equal("Phase1Hover")

			local spawnOk, model = boss:spawnPromise():Yield()
			expect(spawnOk).to.equal(true)
			expect(typeof(model)).to.equal("Instance")
			expect((model :: Instance):IsA("Model")).to.equal(true)
			expect(observedModelPresence[#observedModelPresence]).to.equal(true)

			boss:requestRemoval("spec_remove")
			local removedOk, removedReason = boss:promiseRemoved():Yield()
			expect(removedOk).to.equal(true)
			expect(removedReason).to.equal("spec_remove")

			boss:destroy()
			expect(modelBriosDied).to.equal(1)

			maid:Destroy()
			service:destroy()
			assetTemplates:Destroy()
		end)

		it("wires controller tracking through reactive service helpers", function()
			local assetTemplates = createBossAssetTemplates()
			local service = createTestService()
			local boss = createTestBoss(service)
			local maid = Maid.new()
			local addedIds = {}
			local updatedIds = {}
			local removedIds = {}
			local observedStates = {}

			maid:GiveTask(service:observeControllerAdded():Subscribe(function(snapshot)
				table.insert(addedIds, snapshot.id)
			end))
			maid:GiveTask(service:observeControllerUpdated():Subscribe(function(snapshot)
				table.insert(updatedIds, snapshot.id)
			end))
			maid:GiveTask(service:observeControllerRemoved():Subscribe(function(payload)
				table.insert(removedIds, payload.id)
			end))
			maid:GiveTask(service:observeState():Subscribe(function(state)
				table.insert(observedStates, #state.orderedIds)
			end))

			local waitForTrackedBoss = service:waitForControllerPromise(boss.id)
			service:trackController(boss)
			local addedSnapshot = service:upsertControllerState(boss)
			service:emitControllerAdded(addedSnapshot, boss)

			local waitedOk, waitedBoss = waitForTrackedBoss:Yield()
			expect(waitedOk).to.equal(true)
			expect(waitedBoss).to.equal(boss)
			expect(addedIds[#addedIds]).to.equal(boss.id)
			expect(observedStates[#observedStates]).to.equal(1)

			boss:changeState("Phase1Hover", "service_update")
			expect(updatedIds[#updatedIds]).to.equal(boss.id)

			local removalPromise = service:waitForControllerRemovalPromise(boss.id)
			boss:requestRemoval("service_remove")
			local removedOk, removedPayload = removalPromise:Yield()
			expect(removedOk).to.equal(true)
			expect(removedPayload.id).to.equal(boss.id)
			expect(removedIds[#removedIds]).to.equal(boss.id)
			expect(service.controllersById[boss.id]).to.equal(nil)

			maid:Destroy()
			service:destroy()
			assetTemplates:Destroy()
		end)

		it("provides promise-based spawn helpers on the service", function()
			local assetTemplates = createBossAssetTemplates()
			local service = createTestService()
			local spawnPromise = service:spawnBossPromise({
				bossId = "EyeOfCthulhu",
				spawnSource = "DebugCommand",
				encounterChannel = "spec.promise_spawn",
				spawnPosition = Vector3.new(0, 35, 18),
			})

			local ok, boss, reason = spawnPromise:Yield()
			expect(ok).to.equal(true)
			expect(boss ~= nil).to.equal(true)
			expect(reason).to.equal(nil)
			expect(service.controllersById[(boss :: any).id]).to.equal(boss)

			service:destroy()
			assetTemplates:Destroy()
		end)

		it("spawns the eye controller when authored asset templates are absent", function()
			local service = createTestService()
			local boss, reason = service:spawnBoss({
				bossId = "EyeOfCthulhu",
				spawnSource = "DebugCommand",
				encounterChannel = "spec.assetless_spawn",
				spawnPosition = Vector3.new(0, 35, 18),
			})

			expect(reason).to.equal(nil)
			expect(boss ~= nil).to.equal(true)
			expect(service.controllersById[(boss :: any).id]).to.equal(boss)
			expect(((boss :: any).model :: Instance):GetAttribute("BossSpriteRoot")).to.equal(true)

			service:destroy()
		end)
	end)
end
