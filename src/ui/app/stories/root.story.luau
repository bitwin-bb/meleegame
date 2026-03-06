local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local RootUI = require(ReplicatedStorage.UI.app.RootUI)
local HpServiceUtils = require(ReplicatedStorage.Shared.Services.HpService.HpServiceUtils)
local ManaServiceUtils = require(ReplicatedStorage.Shared.Services.ManaService.ManaServiceUtils)

local e: typeof(React.createElement) = React.createElement

return function(target)
	local root = ReactRoblox.createRoot(target)
	local mockHpState = HpServiceUtils.createState(78, 100, 20)
	local mockManaState = ManaServiceUtils.createState(17, 20, 0, true, nil)

	root:render(e(RootUI, {
		currentScreen = nil,
		hudProps = {
			hpBarProps = {
				useServiceState = false,
				mockState = mockHpState,
				mockReady = true,
			},
			manaBarProps = {
				useServiceState = false,
				mockState = mockManaState,
				mockReady = true,
			},
		},
	}))

	return function()
		root:unmount()
	end
end
