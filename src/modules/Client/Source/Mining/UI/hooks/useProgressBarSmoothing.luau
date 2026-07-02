
local require = require(script.Parent.loader).load(script)

local useSmoothedProgress = require("useSmoothedProgress")

export type ProgressBarSmoothingOptions = {
	progress: number,
	visible: boolean?,
	gainRate: number?,
	depletionRate: number?,
}

local function useProgressBarSmoothing(options: ProgressBarSmoothingOptions): number
	return useSmoothedProgress({
		progress = options.progress,
		visible = options.visible,
		gainRate = options.gainRate,
		depletionRate = options.depletionRate,
	})
end

return useProgressBarSmoothing
