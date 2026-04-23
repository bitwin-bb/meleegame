--!strict
-- selene: allow(undefined_variable)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WindFoliageServiceClient = require(script:FindFirstAncestor("game").Client.Services.WindFoliageServiceClient)

local function createWeatherWindStub()
	local baseline = {
		windField = {
			strengthMultiplier = 1,
			baseStrength = 0.62,
			gustStrength = 0.92,
			detailStrength = 0.2,
			gustSpatialScale = 140,
			gustTimeScale = 0.16,
			detailSpatialScale = 22,
			detailTimeScale = 1.55,
			directionJitterRadians = math.rad(18),
		},
		tiers = {
			near = {
				updateInterval = 1 / 60,
				windScale = 1,
				detailScale = 1,
			},
			mid = {
				updateInterval = 0.12,
				windScale = 0.82,
				detailScale = 0.42,
			},
			far = {
				updateInterval = 0.32,
				windScale = 0.56,
				detailScale = 0.1,
			},
			frozen = {
				updateInterval = 0.75,
			},
		},
		updateBudget = {
			maxActiveTrees = 128,
			maxTransformWritesPerStep = 24000,
		},
		springs = {
			primary = {
				frequency = 0.45,
				damping = 0.97,
			},
			secondary = {
				frequency = 0.55,
				damping = 0.94,
			},
			flutter = {
				frequency = 0.6,
				damping = 1,
			},
		},
	}
	local windField = table.clone(baseline.windField)
	local lodController = {
		tierNear = {
			updateInterval = baseline.tiers.near.updateInterval,
			lodState = {
				windScale = baseline.tiers.near.windScale,
				detailScale = baseline.tiers.near.detailScale,
			},
		},
		tierMid = {
			updateInterval = baseline.tiers.mid.updateInterval,
			lodState = {
				windScale = baseline.tiers.mid.windScale,
				detailScale = baseline.tiers.mid.detailScale,
			},
		},
		tierFar = {
			updateInterval = baseline.tiers.far.updateInterval,
			lodState = {
				windScale = baseline.tiers.far.windScale,
				detailScale = baseline.tiers.far.detailScale,
			},
		},
		tierFrozen = {
			updateInterval = baseline.tiers.frozen.updateInterval,
			lodState = {
				windScale = 0,
				detailScale = 0,
			},
		},
	}
	local updateManager = {
		maxActiveTrees = baseline.updateBudget.maxActiveTrees,
		maxTransformWritesPerStep = baseline.updateBudget.maxTransformWritesPerStep,
		primarySpring = table.clone(baseline.springs.primary),
		secondarySpring = table.clone(baseline.springs.secondary),
		flutterSpring = table.clone(baseline.springs.flutter),
	}
	local service = {
		simulation = {
			windField = windField,
			lodController = lodController,
			updateManager = updateManager,
		},
		weatherWindState = {
			strengthMultiplier = baseline.windField.strengthMultiplier,
			baseStrength = baseline.windField.baseStrength,
			gustStrength = baseline.windField.gustStrength,
			detailStrength = baseline.windField.detailStrength,
			gustSpatialScale = baseline.windField.gustSpatialScale,
			gustTimeScale = baseline.windField.gustTimeScale,
			detailSpatialScale = baseline.windField.detailSpatialScale,
			detailTimeScale = baseline.windField.detailTimeScale,
			directionJitterRadians = baseline.windField.directionJitterRadians,
			tiers = {
				near = table.clone(baseline.tiers.near),
				mid = table.clone(baseline.tiers.mid),
				far = table.clone(baseline.tiers.far),
				frozen = table.clone(baseline.tiers.frozen),
			},
			updateBudget = table.clone(baseline.updateBudget),
			springs = {
				primary = table.clone(baseline.springs.primary),
				secondary = table.clone(baseline.springs.secondary),
				flutter = table.clone(baseline.springs.flutter),
			},
		},
	}

	return baseline, windField, lodController, updateManager, service
end

return function()
	describe("WindFoliageServiceClient", function()
		it("makes storm wind stronger, more turbulent, and restores the calm baseline afterward", function()
			local baseline, windField, lodController, updateManager, service = createWeatherWindStub()

			WindFoliageServiceClient.SetWeatherWind(service, 1, false)

			local rainyGustStrength = windField.gustStrength
			local rainyDetailStrength = windField.detailStrength
			local rainyDirectionJitter = windField.directionJitterRadians
			local rainyGustSpatialScale = windField.gustSpatialScale
			local rainyDetailTimeScale = windField.detailTimeScale
			local rainyNearInterval = lodController.tierNear.updateInterval
			local rainyFarWindScale = lodController.tierFar.lodState.windScale
			local rainyFarDetailScale = lodController.tierFar.lodState.detailScale
			local rainyMaxActiveTrees = updateManager.maxActiveTrees
			local rainyTransformWrites = updateManager.maxTransformWritesPerStep
			local rainyFlutterFrequency = updateManager.flutterSpring.frequency

			expect(windField.strengthMultiplier > baseline.windField.strengthMultiplier).to.equal(true)
			expect(rainyGustStrength > baseline.windField.gustStrength).to.equal(true)
			expect(rainyDetailStrength > baseline.windField.detailStrength).to.equal(true)
			expect(rainyDirectionJitter > baseline.windField.directionJitterRadians).to.equal(true)
			expect(rainyGustSpatialScale < baseline.windField.gustSpatialScale).to.equal(true)
			expect(rainyDetailTimeScale > baseline.windField.detailTimeScale).to.equal(true)
			expect(rainyNearInterval < baseline.tiers.near.updateInterval).to.equal(true)
			expect(rainyFarWindScale > baseline.tiers.far.windScale).to.equal(true)
			expect(rainyFarDetailScale > baseline.tiers.far.detailScale).to.equal(true)
			expect(rainyMaxActiveTrees > baseline.updateBudget.maxActiveTrees).to.equal(true)
			expect(rainyTransformWrites > baseline.updateBudget.maxTransformWritesPerStep).to.equal(true)
			expect(rainyFlutterFrequency > baseline.springs.flutter.frequency).to.equal(true)

			WindFoliageServiceClient.SetWeatherWind(service, 1, true)

			expect(windField.gustStrength > rainyGustStrength).to.equal(true)
			expect(windField.detailStrength > rainyDetailStrength).to.equal(true)
			expect(windField.directionJitterRadians > rainyDirectionJitter).to.equal(true)
			expect(windField.gustSpatialScale < rainyGustSpatialScale).to.equal(true)
			expect(windField.detailTimeScale > rainyDetailTimeScale).to.equal(true)
			expect(lodController.tierNear.updateInterval < rainyNearInterval).to.equal(true)
			expect(lodController.tierFar.lodState.windScale > rainyFarWindScale).to.equal(true)
			expect(lodController.tierFar.lodState.detailScale > rainyFarDetailScale).to.equal(true)
			expect(updateManager.maxActiveTrees > rainyMaxActiveTrees).to.equal(true)
			expect(updateManager.maxTransformWritesPerStep > rainyTransformWrites).to.equal(true)
			expect(updateManager.flutterSpring.frequency > rainyFlutterFrequency).to.equal(true)

			WindFoliageServiceClient.SetWeatherWind(service, 0, false)

			expect(windField.strengthMultiplier).to.equal(baseline.windField.strengthMultiplier)
			expect(windField.baseStrength).to.equal(baseline.windField.baseStrength)
			expect(windField.gustStrength).to.equal(baseline.windField.gustStrength)
			expect(windField.detailStrength).to.equal(baseline.windField.detailStrength)
			expect(windField.gustSpatialScale).to.equal(baseline.windField.gustSpatialScale)
			expect(windField.gustTimeScale).to.equal(baseline.windField.gustTimeScale)
			expect(windField.detailSpatialScale).to.equal(baseline.windField.detailSpatialScale)
			expect(windField.detailTimeScale).to.equal(baseline.windField.detailTimeScale)
			expect(windField.directionJitterRadians).to.equal(baseline.windField.directionJitterRadians)
			expect(lodController.tierNear.updateInterval).to.equal(baseline.tiers.near.updateInterval)
			expect(lodController.tierMid.updateInterval).to.equal(baseline.tiers.mid.updateInterval)
			expect(lodController.tierFar.updateInterval).to.equal(baseline.tiers.far.updateInterval)
			expect(lodController.tierFrozen.updateInterval).to.equal(baseline.tiers.frozen.updateInterval)
			expect(lodController.tierNear.lodState.windScale).to.equal(baseline.tiers.near.windScale)
			expect(lodController.tierFar.lodState.detailScale).to.equal(baseline.tiers.far.detailScale)
			expect(updateManager.maxActiveTrees).to.equal(baseline.updateBudget.maxActiveTrees)
			expect(updateManager.maxTransformWritesPerStep).to.equal(baseline.updateBudget.maxTransformWritesPerStep)
			expect(updateManager.primarySpring.frequency).to.equal(baseline.springs.primary.frequency)
			expect(updateManager.secondarySpring.frequency).to.equal(baseline.springs.secondary.frequency)
			expect(updateManager.flutterSpring.frequency).to.equal(baseline.springs.flutter.frequency)
		end)
	end)
end
