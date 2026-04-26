--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

export type MountedRef = {
	current: boolean,
}

local function useMounted(): MountedRef
	local mountedRef = React.useRef(false) :: MountedRef

	React.useEffect(function()
		mountedRef.current = true

		return function()
			mountedRef.current = false
		end
	end, {})

	return mountedRef
end

return useMounted
