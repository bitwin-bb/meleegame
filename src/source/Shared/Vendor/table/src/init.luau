--!strict

--// Variables
local RNG = Random.new()

--// Module Setup
local System = {}

--[[
    Returns true if the table contains the specified value.
]]
function System.contains<T, V>(tbl: { V }, value: V): boolean
	return not not System.indexOf(tbl, value) -- This is kind of cheatsy but it promises the best performance.
end

--[[
    A combo of table.find and table.keyOf
	This first attempts to find the ordinal index of your value, then attempts to find the lookup key if it can't find an ordinal index.
]]
function System.indexOf<T, V>(tbl: { [T]: V } | { V }, value: V): number | T?
	local index = table.find(tbl :: { V }, value)
	if index then
		return index
	end

	return System.keyOf(tbl, value)
end

--[[
    Returns the key of the specified value, or nil if it could not be found. Unlike IndexOf, this searches every key in the table, not just ordinal indices (arrays)
    This is inherently slower due to how lookups work, so if your table is structured like an array, use table.find
]]
function System.keyOf<T, V>(tbl: { [T]: V }, value: V): T?
	for index, obj in tbl do
		if obj == value then
			return index
		end
	end

	return
end

--[[
    ONLY SUPPORTS ORDINAL TABLES (ARRAYS).
    Skips *n* objects in the table, and returns a new table that contains indices (n + 1) to (end of table)
]]
function System.skip<V>(tbl: { V }, n: number): { V }
	return table.move(tbl, n + 1, #tbl, 1, table.create(#tbl - n))
end

--[[
    ONLY SUPPORTS ORDINAL TABLES (ARRAYS).
    Takes *n* objects from a table and returns a new table only containing those objects.
]]
function System.take<V>(tbl: { V }, n: number): { V }
	return table.move(tbl, 1, n, 1, table.create(n))
end

--[[
    ONLY SUPPORTS ORDINAL TABLES (ARRAYS).
    Takes the range of entries in this table in the range [start, finish] and returns that range as a table.
]]
function System.range<V>(tbl: { V }, start: number, finish: number): { V }
	return table.move(tbl, start, finish, 1, table.create(finish - start + 1))
end

--[[
    ONLY SUPPORTS ORDINAL TABLES (ARRAYS).
    An alias that calls table.skip(skip), and then takes [take] entries from the resulting table.
]]
function System.skipAndTake<V>(tbl: { V }, skip: number, take: number): { V }
	return table.move(tbl, skip + 1, skip + take, 1, table.create(take))
end

--[[
    ONLY SUPPORTS ORDINAL TABLES (ARRAYS).
    Selects a random object out of tbl
]]
function System.random<V>(tbl: { V }): V
	return tbl[RNG:NextInteger(1, #tbl)]
end

--[[
    ONLY SUPPORTS ORDINAL TABLES (ARRAYS).
    Merges tbl0 and tbl1 together.
]]
function System.join<V1, V2>(tbl1: { V1 }, tbl12: { V2 }): { V1 | V2 }
	-- Create new tbl
	local newTbl: { V1 | V2 } = table.create(#tbl1 + #tbl12)

	-- Move tbls
	table.move(tbl1, 1, #tbl1, 1, newTbl :: { V1 })
	table.move(tbl12, 1, #tbl12, #tbl1 + 1, newTbl :: { V2 })

	return newTbl
end

--[[
    ONLY SUPPORTS ORDINAL TABLES (ARRAYS).
    Removes the specified object from this array.
]]
function System.removeObject<V>(tbl: { V }, obj: V)
	local index: number? = System.indexOf(tbl, obj)
	if index then
		table.remove(tbl, index)
	end
end

--[[
    ONLY SUPPORTS ORDINAL TABLES (ARRAYS).
    Allocates a new table by getting the length of the current table and increasing its capacity by the specified amount.
    This uses Roblox's table.create function.
]]
function System.expand<V>(tbl: { V }, byAmount: number)
	if byAmount < 0 then
		error("Cannot expand a table by a negative amount of objects.")
	end

	local newTbl = table.create(#tbl + byAmount)
	for i = 1, #tbl do
		newTbl[i] = tbl[i]
	end

	return newTbl
end

return setmetatable({} :: typeof(table) & typeof(System), {
	__index = function(_, index: string)
		if System[index] then
			return System[index]
		else
			return table[index]
		end
	end,

	__newindex = function(_, _, _)
		error("Add new table entries by editing the Module itself.")
	end,
})
