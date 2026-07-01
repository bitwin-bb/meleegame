local require = require(script.Parent.loader).load(script)

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

-- selene: allow(undefined_variable)

local PlatformServiceUtils = require("PlatformServiceUtils")

local DEFAULT_CAPABILITIES: PlatformServiceUtils.CapabilitySnapshot = {
	touchEnabled = false,
	keyboardEnabled = true,
	mouseEnabled = true,
	gamepadEnabled = false,
	basePrimaryInputType = "KeyboardMouse",
}

return function()
	describe("PlatformServiceUtils", function()
		it("prefers PreferredInput when resolving the current platform", function()
			local state =
				PlatformServiceUtils.CreatePlatformState(Enum.PreferredInput.Gamepad, Enum.UserInputType.MouseButton1, {
					touchEnabled = true,
					keyboardEnabled = true,
					mouseEnabled = true,
					gamepadEnabled = true,
					basePrimaryInputType = "KeyboardMouse",
				}, Vector2.new(1920, 1080), false)

			expect(state.platform).to.equal("Gamepad")
			expect(state.deviceClass).to.equal("Console")
		end)

		it("classifies touch viewports into phone and tablet buckets", function()
			expect(PlatformServiceUtils.GetDeviceClass("Touch", Vector2.new(390, 844), DEFAULT_CAPABILITIES, false)).to.equal(
				"Phone"
			)
			expect(
				PlatformServiceUtils.GetDeviceClass("Touch", Vector2.new(1280, 800), DEFAULT_CAPABILITIES, false)
			).to.equal("Tablet")
		end)

		it("applies thumbstick deadzones without losing normalized direction", function()
			local inactive = PlatformServiceUtils.ApplyThumbstickDeadzone(Vector2.new(0.12, 0), 0.2)
			local active = PlatformServiceUtils.ApplyThumbstickDeadzone(Vector2.new(0.8, 0), 0.2)

			expect(inactive.Magnitude).to.equal(0)
			expect(active.X ~= 0).to.equal(true)
			expect(math.abs(active.X - 0.75) <= 0.001).to.equal(true)
		end)

		it("returns normalized prompts for each supported gameplay platform", function()
			local definition =
				PlatformServiceUtils.GetDefaultActionDefinition(PlatformServiceUtils.ACTIONS.MELEE_ATTACK)
			expect(definition ~= nil).to.equal(true)

			local keyboardPrompt =
				PlatformServiceUtils.GetPromptForAction(definition, "KeyboardMouse", "Desktop", "xbox") :: any
			local gamepadPrompt =
				PlatformServiceUtils.GetPromptForAction(definition, "Gamepad", "Console", "xbox") :: any
			local touchPrompt = PlatformServiceUtils.GetPromptForAction(definition, "Touch", "Phone", "xbox") :: any

			expect(keyboardPrompt.text).to.equal("LMB")
			expect(gamepadPrompt.text).to.equal("RT")
			expect(typeof(gamepadPrompt.icon)).to.equal("string")
			expect(touchPrompt.text).to.equal("Tap to Attack")
		end)

		it("keeps jump separate from fly-up controls", function()
			local jumpDefinition = PlatformServiceUtils.GetDefaultActionDefinition(PlatformServiceUtils.ACTIONS.JUMP)
			local moveUpDefinition =
				PlatformServiceUtils.GetDefaultActionDefinition(PlatformServiceUtils.ACTIONS.MOVE_UP)

			expect(jumpDefinition ~= nil).to.equal(true)
			expect(moveUpDefinition ~= nil).to.equal(true)

			local jumpBindings = PlatformServiceUtils.GetBindingsForPlatform(jumpDefinition, "KeyboardMouse")
			local moveUpBindings = PlatformServiceUtils.GetBindingsForPlatform(moveUpDefinition, "KeyboardMouse")
			local jumpPrompt =
				PlatformServiceUtils.GetPromptForAction(jumpDefinition, "KeyboardMouse", "Desktop", "xbox") :: any
			local gamepadJumpPrompt =
				PlatformServiceUtils.GetPromptForAction(jumpDefinition, "Gamepad", "Console", "xbox") :: any

			expect(#jumpBindings).to.equal(1)
			expect(jumpBindings[1].playerAction).to.equal(Enum.PlayerActions.CharacterJump)
			expect(#moveUpBindings).to.equal(1)
			expect(moveUpBindings[1].playerAction).to.equal(Enum.PlayerActions.CharacterForward)
			expect(jumpPrompt.text).to.equal("Space")
			expect(gamepadJumpPrompt.text).to.equal("A")
		end)

		it("exposes the Xbox inventory prompt on Y", function()
			local definition =
				PlatformServiceUtils.GetDefaultActionDefinition(PlatformServiceUtils.ACTIONS.OPEN_INVENTORY)

			expect(definition ~= nil).to.equal(true)

			local gamepadPrompt =
				PlatformServiceUtils.GetPromptForAction(definition, "Gamepad", "Console", "xbox") :: any

			expect(gamepadPrompt.text).to.equal("Y")
			expect(gamepadPrompt.keyCode).to.equal(Enum.KeyCode.ButtonY)
			expect(typeof(gamepadPrompt.icon)).to.equal("string")
		end)
	end)
end
