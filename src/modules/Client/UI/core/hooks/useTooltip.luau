--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local useStableCallback = require(script.Parent.internal.useStableCallback)

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
	end, { enabled, hovered, id, text, show })

	React.useEffect(function()
		if enabled and hovered then
			return
		end
		hide(id)
	end, { enabled, hovered, id, hide })

	React.useEffect(function()
		return function()
			hide(id)
		end
	end, { id, hide })
end

return useTooltip
