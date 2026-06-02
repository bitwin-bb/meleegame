--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local useSmoothedProgress = require(gameRoot.Client.UI.core.hooks.useSmoothedProgress)

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
