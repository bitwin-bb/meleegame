--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local UserInputService = game:GetService("UserInputService")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Maid = Nevermore.Get("Maid")
local Signal = Nevermore.Get("Signal")

local InputHandler = {}
InputHandler.__index = InputHandler

export type InputHandler = typeof(setmetatable(
	{} :: {
		maid: any,
		Changed: any,
		moveVector: Vector3,
		pressed: { [string]: boolean },
	},
	InputHandler
))

local KEY_NAMES = table.freeze({
	Dash = "Dash",
	Jump = "Jump",
	Attack = "Attack",
	Block = "Block",
})

function InputHandler.new(): InputHandler
	local self = setmetatable({
		maid = Maid.new(),
		Changed = Signal.new(),
		moveVector = Vector3.zero,
		pressed = {},
	}, InputHandler)

	self.maid:GiveTask(self.Changed)
	self.maid:GiveTask(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		self:_setInput(input, true)
	end))
	self.maid:GiveTask(UserInputService.InputEnded:Connect(function(input)
		self:_setInput(input, false)
	end))

	return self
end

function InputHandler._setPressed(self: InputHandler, keyName: string, isPressed: boolean)
	if self.pressed[keyName] == isPressed then
		return
	end
	self.pressed[keyName] = isPressed
	self.Changed:Fire(keyName, isPressed)
end

function InputHandler._setInput(self: InputHandler, input: InputObject, isPressed: boolean)
	if input.KeyCode == Enum.KeyCode.Space then
		self:_setPressed(KEY_NAMES.Jump, isPressed)
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.Q then
		self:_setPressed(KEY_NAMES.Dash, isPressed)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		self:_setPressed(KEY_NAMES.Attack, isPressed)
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		self:_setPressed(KEY_NAMES.Block, isPressed)
	end
end

function InputHandler.SetMoveVector(self: InputHandler, moveVectorRaw: any)
	self.moveVector = if typeof(moveVectorRaw) == "Vector3" then moveVectorRaw else Vector3.zero
end

function InputHandler.GetMoveVector(self: InputHandler): Vector3
	return self.moveVector
end

function InputHandler.IsJumpPressed(self: InputHandler): boolean
	return self.pressed[KEY_NAMES.Jump] == true
end

function InputHandler.IsDashPressed(self: InputHandler): boolean
	return self.pressed[KEY_NAMES.Dash] == true
end

function InputHandler.IsAttackPressed(self: InputHandler): boolean
	return self.pressed[KEY_NAMES.Attack] == true
end

function InputHandler.IsBlocking(self: InputHandler): boolean
	return self.pressed[KEY_NAMES.Block] == true
end

function InputHandler.Destroy(self: InputHandler)
	self.maid:DoCleaning()
	table.clear(self.pressed)
end

InputHandler.setMoveVector = InputHandler.SetMoveVector
InputHandler.getMoveVector = InputHandler.GetMoveVector
InputHandler.isJumpPressed = InputHandler.IsJumpPressed
InputHandler.isDashPressed = InputHandler.IsDashPressed
InputHandler.isAttackPressed = InputHandler.IsAttackPressed
InputHandler.isBlocking = InputHandler.IsBlocking
InputHandler.destroy = InputHandler.Destroy

return InputHandler
