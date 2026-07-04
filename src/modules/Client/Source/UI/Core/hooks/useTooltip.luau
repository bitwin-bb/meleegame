local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React: any = require(ReplicatedStorage.Packages.React)
local useStableCallback = require("useStableCallback")

local function dependencyArray(...: any): { any }
	return { ... }
end

export type TooltipPayload = {
	id: string,
	text: string,
}

export type TooltipOptions = {
	id: string,
	text: string,
	enabled: boolean?,
	hovered: boolean?,
	show: (TooltipPayload) -> (),
	hide: (string?) -> (),
}

local function useTooltip(options: TooltipOptions)
	local show = useStableCallback(options.show)
	local hide = useStableCallback(options.hide)
	local enabled = options.enabled ~= false
	local hovered = options.hovered == true
	local id = options.id
	local text = options.text

	React.useEffect(function()
		if not enabled or not hovered then
			return
		end

		show({
			id = id,
			text = text,
		})
	end, dependencyArray(enabled, hovered, id, text, show))

	React.useEffect(function()
		if enabled and hovered then
			return
		end
		hide(id)
	end, dependencyArray(enabled, hovered, id, hide))

	React.useEffect(function()
		return function()
			hide(id)
		end
	end, dependencyArray(id, hide))
end

return useTooltip
