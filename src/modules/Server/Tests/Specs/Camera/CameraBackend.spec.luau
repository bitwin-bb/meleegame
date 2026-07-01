local require = require(script.Parent.loader).load(script)

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

-- selene: allow(undefined_variable)

local Workspace = game:GetService("Workspace")

local Cache = require("Cache")
local Predict = require("Predict")
local CameraBackendGetter = require("CameraBackendGetter")
local Stack = require("CameraOverrideStack")
local State = require("CameraOverrideState")
local Target = require("Target")

local function expectVectorNear(actualRaw: any, expectedRaw: any, epsilon: number?)
	if typeof(actualRaw) ~= "Vector3" or typeof(expectedRaw) ~= "Vector3" then
		error(("expected Vector3 values, got %s and %s"):format(typeof(actualRaw), typeof(expectedRaw)), 2)
	end

	local actual = actualRaw :: Vector3
	local expected = expectedRaw :: Vector3
	local tolerance = epsilon or 1e-4
	if (actual - expected).Magnitude > tolerance then
		error(("expected %s to be within %.6f of %s"):format(tostring(actual), tolerance, tostring(expected)), 2)
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

			local targetGetter = Target.New()

			targetGetter:SetCharacter(character)
			targetGetter:SetExplicitTarget(explicitTarget)
			targetGetter:SetTemporaryOverride(temporaryTarget)

			local temporaryResolution = targetGetter:Get() :: any
			expect(temporaryResolution ~= nil).to.equal(true)
			expect(temporaryResolution.kind).to.equal("TemporaryOverride")
			expect(temporaryResolution.basePart).to.equal(temporaryTarget)

			targetGetter:ClearTemporaryOverride()
			local explicitResolution = targetGetter:Get() :: any
			expect(explicitResolution ~= nil).to.equal(true)
			expect(explicitResolution.kind).to.equal("ExplicitTarget")
			expect(explicitResolution.basePart).to.equal(explicitTarget)

			targetGetter:SetExplicitTarget(nil)
			local characterResolution = targetGetter:Get() :: any
			expect(characterResolution ~= nil).to.equal(true)
			expect(characterResolution.kind).to.equal("Character")
			expect(characterResolution.basePart).to.equal(character.PrimaryPart)

			temporaryTarget:Destroy()
			explicitTarget:Destroy()
			character:Destroy()
		end)

		it("gets active overrides by priority and prunes expired entries", function()
			local stack = Stack.New()
			local lowPriorityId = stack:Push({
				priority = 1,
				position = Vector3.new(1, 0, 0),
			})
			local highPriorityId = stack:Push({
				priority = 5,
				position = Vector3.new(5, 0, 0),
			})
			stack:Push({
				priority = 9,
				position = Vector3.new(9, 0, 0),
				expiresAt = 0,
			})

			local Got = stack:Get(os.clock()) :: any
			expect(Got ~= nil).to.equal(true)
			expect(Got.id).to.equal(highPriorityId)
			expect(Got.position).to.equal(Vector3.new(5, 0, 0))

			stack:Remove(highPriorityId)
			local afterRemoval = stack:Get(os.clock()) :: any
			expect(afterRemoval ~= nil).to.equal(true)
			expect(afterRemoval.id).to.equal(lowPriorityId)
		end)

		it("predicts forward using cache-derived velocity when live velocity is absent", function()
			local cache = Cache.New()
			cache:RememberSubject("camera-test", "Point", Vector3.zero, Vector3.zero, 0)

			local predictor = Predict.New({
				enabled = true,
				leadTime = 0.1,
				maxLeadTime = 0.1,
				minimumSpeed = 0,
				maximumDistance = 100,
				derivedVelocityWeight = 1,
			})

			local result = predictor:Get(
				{
					position = Vector3.new(10, 0, 0),
					velocity = Vector3.zero,
					cacheKey = "camera-test",
				},
				cache,
				{
					now = 1,
				}
			)

			expect(result.active).to.equal(true)
			expectVectorNear(result.offset, Vector3.new(1, 0, 0), 1e-4)
			expectVectorNear(result.position :: Vector3, Vector3.new(11, 0, 0), 1e-4)
		end)

		it("composes a follow goal and records the backend frame snapshot", function()
			local trackedPart = createTrackedPart("CameraBackendFollow", Vector3.new(4, 2, 0), Vector3.zero)
			local cache = Cache.New()
			local predictor = Predict.New({
				enabled = false,
			})
			local stack = Stack.New()
			local state = State.New()
			local targetGetter = Target.New()
			targetGetter:SetExplicitTarget(trackedPart)
			state:SetEnabled(true)

			local backendGetter = CameraBackendGetter.new({
				cache = cache,
				predictor = predictor,
				stack = stack,
				state = state,
				target = targetGetter,
			})

			local resolution = backendGetter:Get({
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

			local frame = cache:GetFrame()
			expect(frame.mode).to.equal("Follow")
			expect(frame.subjectKind).to.equal("ExplicitTarget")
			expectVectorNear(frame.targetPosition :: Vector3, trackedPart.Position, 1e-4)

			trackedPart:Destroy()
		end)

		it("lets direct camera overrides take over without replacing the rest of the backend", function()
			local cache = Cache.New()
			local predictor = Predict.New({
				enabled = false,
			})
			local stack = Stack.New()
			local state = State.New()
			local targetGetter = Target.New()
			state:SetEnabled(true)

			stack:Push({
				priority = 10,
				kind = "Cutscene",
				cameraPosition = Vector3.new(30, 15, 5),
				lookPosition = Vector3.new(0, 0, 0),
				fieldOfView = 40,
			})

			local backendGetter = CameraBackendGetter.new({
				cache = cache,
				predictor = predictor,
				stack = stack,
				state = state,
				target = targetGetter,
			})

			local resolution = backendGetter:Get({
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
