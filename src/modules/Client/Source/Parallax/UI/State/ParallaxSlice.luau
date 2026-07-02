local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)

export type ParallaxLayerView = {
	id: string,
	image: string,
	imageColor: Color3,
	imageTransparency: number,
	framePosition: UDim2,
	frameSize: UDim2,
	imagePosition: UDim2,
	imageSize: UDim2,
	tileSize: UDim2,
	zIndex: number,
}

export type ParallaxSurfaceState = {
	visible: boolean,
	adornee: BasePart?,
	face: Enum.NormalId,
	brightness: number,
	canvasSize: Vector2,
	layers: { ParallaxLayerView },
}

local DEFAULT_STATE: ParallaxSurfaceState = {
	visible = false,
	adornee = nil,
	face = Enum.NormalId.Right,
	brightness = 0.5,
	canvasSize = Vector2.new(1, 1),
	layers = {},
}

local ParallaxSlice = {}

local surfaceStateAtom: Charm.Atom<ParallaxSurfaceState> = Charm.atom(DEFAULT_STATE)

local function cloneLayer(layer: ParallaxLayerView): ParallaxLayerView
	return {
		id = layer.id,
		image = layer.image,
		imageColor = layer.imageColor,
		imageTransparency = layer.imageTransparency,
		framePosition = layer.framePosition,
		frameSize = layer.frameSize,
		imagePosition = layer.imagePosition,
		imageSize = layer.imageSize,
		tileSize = layer.tileSize,
		zIndex = layer.zIndex,
	}
end

local function cloneState(state: ParallaxSurfaceState): ParallaxSurfaceState
	local layers = table.create(#state.layers)
	for index, layer in state.layers do
		layers[index] = cloneLayer(layer)
	end

	return {
		visible = state.visible,
		adornee = state.adornee,
		face = state.face,
		brightness = state.brightness,
		canvasSize = state.canvasSize,
		layers = layers,
	}
end

function ParallaxSlice.GetSurfaceState(): ParallaxSurfaceState
	return cloneState(surfaceStateAtom())
end

function ParallaxSlice.SetSurfaceState(stateRaw: ParallaxSurfaceState)
	surfaceStateAtom(cloneState(stateRaw))
end

function ParallaxSlice.ClearSurfaceState()
	surfaceStateAtom(cloneState(DEFAULT_STATE))
end

ParallaxSlice.surfaceStateAtom = surfaceStateAtom
return ParallaxSlice
