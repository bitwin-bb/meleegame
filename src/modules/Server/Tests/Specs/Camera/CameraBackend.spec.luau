--!strict
-- selene: allow(undefined_variable)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Cache = require(script:FindFirstAncestor("game").Shared.Classes.Camera.Cache)
local Predict = require(script:FindFirstAncestor("game").Shared.Classes.Camera.Predict)
local Resolve = require(script:FindFirstAncestor("game").Shared.Classes.Camera.Resolve)
local Stack = require(script:FindFirstAncestor("game").Shared.Classes.Camera.Stack)
local State = require(script:FindFirstAncestor("game").Shared.Classes.Camera.State)
local Target = require(script:FindFirstAncestor("game").Shared.Classes.Camera.Target)

local function expectVectorNear(actualRaw: any, expectedRaw: any, epsilon: number?)
	if typeof(actualRaw) ~= "Vector3" or typeof(expectedRaw) ~= "Vector3" then
		error(
			("expected Vector3 values, got %s and %s"):format(typeof(actualRaw), typeof(expectedRaw)),
			2
		)
	end

	local actual = actualRaw :: Vector3
	local expected = expectedRaw :: Vector3
	local tolerance = epsilon or 1e-4
	if (actual - expected).Magnitude > tolerance then
		error(
			("expected %s to be within %.6f of %s"):format(tostring(actual), tolerance, tostring(expected)),
			2
		)
	end
end

local function createTrackedPart(name: string, position: Vector3, velocity: Vector3?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = CFrame.new(position)
	part.AssemblyLinearVelocity = velocity or Vector3.zero
	part.Parent = Workspace
	return part
end

local function createCharacter(name: string, rootPosition: Vector3): Model
	local character = Instance.new("Model")
	character.Name = name

	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Anchored = true
	rootPart.CanCollide = false
	rootPart.CFrame = CFrame.new(rootPosition)
	rootPart.Parent = character

	character.PrimaryPart = rootPart
	character.Parent = Workspace
	return character
end

return function()
	describe("Camera backend helpers", function()
		it("prioritizes temporary overrides before explicit or character targets", function()
			local character = createCharacter("CameraBackendCharacter", Vector3.new(2, 3, 4))
			local explicitTarget = createTrackedPart("CameraBackendExplicit", Vector3.new(10, 0, 0), Vector3.zero)
			local temporaryTarget = createTrackedPart("CameraBackendTemporary", Vector3.new(20, 0, 0), Vector3.zero)

			local targetResolver = Target.new()

			targetResolver:setCharacter(character)
			targetResolver:setExplicitTarget(explicitTarget)
			targetResolver:setTemporaryOverride(temporaryTarget)

			local temporaryResolution = targetResolver:resolve()
			expect(temporaryResolution ~= nil).to.equal(true)
			expect(temporaryResolution.kind).to.equal("TemporaryOverride")
			expect(temporaryResolution.basePart).to.equal(temporaryTarget)

			targetResolver:clearTemporaryOverride()
			local explicitResolution = targetResolver:resolve()
			expect(explicitResolution ~= nil).to.equal(true)
			expect(explicitResolution.kind).to.equal("ExplicitTarget")
			expect(explicitResolution.basePart).to.equal(explicitTarget)

			targetResolver:setExplicitTarget(nil)
			local characterResolution = targetResolver:resolve()
			expect(characterResolution ~= nil).to.equal(true)
			expect(characterResolution.kind).to.equal("Character")
			expect(characterResolution.basePart).to.equal(character.PrimaryPart)

			temporaryTarget:Destroy()
			explicitTarget:Destroy()
			character:Destroy()
		end)

		it("resolves active overrides by priority and prunes expired entries", function()
			local stack = Stack.new()
			local lowPriorityId = stack:push({
				priority = 1,
				position = Vector3.new(1, 0, 0),
			})
			local highPriorityId = stack:push({
				priority = 5,
				position = Vector3.new(5, 0, 0),
			})
			stack:push({
				priority = 9,
				position = Vector3.new(9, 0, 0),
				expiresAt = 0,
			})

			local resolved = stack:resolve(os.clock())
			expect(resolved ~= nil).to.equal(true)
			expect(resolved.id).to.equal(highPriorityId)
			expect(resolved.position).to.equal(Vector3.new(5, 0, 0))

			stack:remove(highPriorityId)
			local afterRemoval = stack:resolve(os.clock())
			expect(afterRemoval ~= nil).to.equal(true)
			expect(afterRemoval.id).to.equal(lowPriorityId)
		end)

		it("predicts forward using cache-derived velocity when live velocity is absent", function()
			local cache = Cache.new()
			cache:rememberSubject("camera-test", "Point", Vector3.zero, Vector3.zero, 0)

			local predictor = Predict.new({
				enabled = true,
				leadTime = 0.1,
				maxLeadTime = 0.1,
				minimumSpeed = 0,
				maximumDistance = 100,
				derivedVelocityWeight = 1,
			})

			local result = predictor:resolve({
				position = Vector3.new(10, 0, 0),
				velocity = Vector3.zero,
				cacheKey = "camera-test",
			}, cache, {
				now = 1,
			})

			expect(result.active).to.equal(true)
			expectVectorNear(result.offset, Vector3.new(1, 0, 0), 1e-4)
			expectVectorNear(result.position :: Vector3, Vector3.new(11, 0, 0), 1e-4)
		end)

		it("composes a follow goal and records the backend frame snapshot", function()
			local trackedPart = createTrackedPart("CameraBackendFollow", Vector3.new(4, 2, 0), Vector3.zero)
			local cache = Cache.new()
			local predictor = Predict.new({
				enabled = false,
			})
			local stack = Stack.new()
			local state = State.new()
			local targetResolver = Target.new()
			targetResolver:setExplicitTarget(trackedPart)
			state:setEnabled(true)

			local resolver = Resolve.new({
				cache = cache,
				predictor = predictor,
				stack = stack,
				state = state,
				target = targetResolver,
			})

			local resolution = resolver:resolve({
				distance = 10,
				height = 5,
				lookHeight = 2,
				sideSign = 1,
				fieldOfView = 55,
				movementBackAmount = 0,
				movementSpeedForMaxBack = 10,
				movementBackSign = 1,
				mouseInfluenceX = 0,
				mouseInfluenceY = 0,
			})

			expect(resolution.cameraCFrame ~= nil).to.equal(true)
			expectVectorNear((resolution.cameraCFrame :: CFrame).Position, Vector3.new(14, 7, 0), 1e-4)
			expect(resolution.fieldOfView).to.equal(55)
			expect((resolution.state :: any).mode).to.equal("Follow")

			local frame = cache:getFrame()
			expect(frame.mode).to.equal("Follow")
			expect(frame.subjectKind).to.equal("ExplicitTarget")
			expectVectorNear(frame.targetPosition :: Vector3, trackedPart.Position, 1e-4)

			trackedPart:Destroy()
		end)

		it("lets direct camera overrides take over without replacing the rest of the backend", function()
			local cache = Cache.new()
			local predictor = Predict.new({
				enabled = false,
			})
			local stack = Stack.new()
			local state = State.new()
			local targetResolver = Target.new()
			state:setEnabled(true)

			stack:push({
				priority = 10,
				kind = "Cutscene",
				cameraPosition = Vector3.new(30, 15, 5),
				lookPosition = Vector3.new(0, 0, 0),
				fieldOfView = 40,
			})

			local resolver = Resolve.new({
				cache = cache,
				predictor = predictor,
				stack = stack,
				state = state,
				target = targetResolver,
			})

			local resolution = resolver:resolve({
				distance = 10,
				height = 5,
				lookHeight = 2,
				sideSign = 1,
				fieldOfView = 55,
				movementBackAmount = 0,
				movementSpeedForMaxBack = 10,
				movementBackSign = 1,
				mouseInfluenceX = 0,
				mouseInfluenceY = 0,
			})

			expect(resolution.cameraCFrame ~= nil).to.equal(true)
			expectVectorNear((resolution.cameraCFrame :: CFrame).Position, Vector3.new(30, 15, 5), 1e-4)
			expect(resolution.fieldOfView).to.equal(40)
			expect((resolution.state :: any).mode).to.equal("DirectOverride")
		end)
	end)
end
