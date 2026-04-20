--!strict
-- selene: allow(undefined_variable)

local gameRoot = script:FindFirstAncestor("game")
assert(gameRoot ~= nil, "Missing Nevermore game root for CmdrCommands.spec.")

local sharedCommands = gameRoot.Shared.Cmdr.Commands
local serverCommands = gameRoot.Server.Cmdr.ServerCommands

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end

	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function expectUniqueModuleNames(folder: Instance)
	local counts = {}

	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			counts[child.Name] = (counts[child.Name] or 0) + 1
		end
	end

	for _, count in counts do
		expect(count).to.equal(1)
	end
end

return function()
	describe("Cmdr commands", function()
		it("keeps shared and server command modules uniquely named", function()
			expectUniqueModuleNames(sharedCommands)
			expectUniqueModuleNames(serverCommands)
		end)

		it("exposes valid shared definitions with matching server executors", function()
			local sharedCount = 0

			for _, child in sharedCommands:GetChildren() do
				if not child:IsA("ModuleScript") then
					continue
				end

				sharedCount += 1
				local commandData = require(child)
				expect(typeof(commandData)).to.equal("table")
				expect(trim((commandData :: any).Name) ~= "").to.equal(true)

				local serverModule = serverCommands:FindFirstChild(`${child.Name}Server`)
					or serverCommands:FindFirstChild(child.Name)
				expect(serverModule ~= nil).to.equal(true)
				if serverModule == nil then
					return
				end
				expect(serverModule:IsA("ModuleScript")).to.equal(true)

				local execute = require(serverModule)
				expect(typeof(execute)).to.equal("function")
			end

			expect(sharedCount > 0).to.equal(true)
		end)
	end)
end
