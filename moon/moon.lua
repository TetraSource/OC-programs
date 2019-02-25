
--[[
moon API by TetraSource

Adds OOP to OC Lua, based on python's OOP.

dependencies: none
]]--

---------------
-- variables --
---------------

local moon = {
	version = "v1.0"
}

-- for backward compatibility with Lua 5.2
local unpack = unpack or table.unpack

------------------------
-- linearization algo --
------------------------

local function revert(list)
	local j, cpy = 1, {}
	for i = #list, 1, -1 do
		j, cpy[j] = j+1, list[i]
	end
	return cpy
end

local function isGoodHead(mros, goodHead)
	for i = 1, #mros do
		local mro = mros[i]
		for j = 1, #mro-1 do
			if rawequal(mro[j], goodHead) then
				return false
			end
		end
	end
	return true
end

local function removeGoodHead(mros, goodHead)
	local i = 1
	while mros[i] do
		local mro = mros[i]
		if rawequal(mro[#mro], goodHead) then
			if #mro > 1 then
				mro[#mro] = nil
			else
				table.remove(mros, i)
				i = i-1
			end
		end
		i = i+1
	end
end

local function merge(bases)
	local mro, mros = {}, {}
	for i = 1, #bases do
		mros[i] = revert(bases[i].__mro)
	end
	mros[#mros+1] = revert(bases)

	while #mros > 0 do
		for k = 1, math.huge do
			if not mros[k] then
				return nil
			end

			local goodHead = mros[k][ #mros[k] ]
			if isGoodHead(mros, goodHead) then
				table.insert(mro, goodHead)
				removeGoodHead(mros, goodHead)
				break
			end
		end
	end
	return mro
end

---------------
-- metatable --
---------------

local metatable = {}

local function lookup(mro, idx)
	for i = 1, #mro do
		if mro[i].__table[idx] ~= nil then
			return mro[i].__table[idx]
		end
	end
	return nil
end

function metatable.__index(obj, idx)
	local method = lookup(obj.__class.__mro, "__getfield")
	if type(method) == "function" then
		return method(obj, idx)
	end
	return nil
end

function metatable.__newindex(obj, idx, val)
	local method = lookup(obj.__class.__mro, "__setfield")
	if type(method) == "function" then
		method(obj, idx, val)
	end
end

local function compErr()
	error("invalid types for comparison", 2)
end

local function arithErr()
	error("attempt to perform arithmetic on a table value", 2)
end

local function binErr()
	error("attempt to perform bitwise operation on a table value", 2)
end

local defaults = {
	__call = function()
		error("attempt to call a table value", 2)
	end,
	__tostring = function(self)
		local name = rawget(self, "__name")
		if name then
			name = (" name: '%s'"):format(name)
		end
		return ("<%s type: '%s'%s>"):format(
			tostring(self.__table), self.__class.__name, name or "")
	end,
	__len = function(self)
		return #self.__table
	end,
	__pairs = function(self)
		return pairs(self.__table)
	end,
	-- might get deprecated
	__ipairs = function(self)
		return ipairs(self.__table)
	end,
	__gc = function()
	end,
	__unm = arithErr,
	__bnot = binErr,
}
for name, operation in next, defaults do
	metatable[name] = function(obj, ...)
		local method = lookup(obj.__class.__mro, name)
		if type(method) == "function" then
			return method(obj, ...)
		else
			return operation(obj, ...)
		end
	end
end

defaults = {
	__concat = function()
		error("attempt to concatenate a table value", 2)
	end,
	__eq = rawequal,
	__lt = compErr,
	__le = compErr,
	__add = arithErr,
	__sub = arithErr,
	__mul = arithErr,
	__div = arithErr,
	__idiv = arithErr,
	__mod = arithErr,
	__pow = arithErr,
	__band = binErr,
	__bor = binErr,
	__bxor = binErr,
	__shl = binErr,
	__shr = binErr,
}
for name, operation in next, defaults do
	metatable[name] = function(obj, other)
		local meta = getmetatable(obj)
		local method = lookup((meta and type(meta) == "table" and
			type(meta[name]) == "function" and obj or other).__class.__mro, name)
		if type(method) == "function" then
			return method(obj, other)
		else
			return operation(obj, other)
		end
	end
end

-------------
-- classes --
-------------

local function namespaceGet(obj, idx)
	if rawget(obj, "__mro") then
		-- check namespace of class and its bases
		return lookup(obj.__mro, idx)
	else
		-- check namespace of object
		return obj.__table[idx]
	end
end

local function getfield(obj, idx, descriptor)
	if descriptor and type(descriptor) == "table" and
		type(descriptor.__get) == "function" then
		-- call data descriptor
		return descriptor:__get(obj)
	end

	local field = namespaceGet(obj, name)
	if field == nil then
		field = descriptor
	end
	if field ~= nil then
		return field
	end

	field = lookup(obj.__class.__mro, "__index")
	if type(field) == "function" then
		-- call __index
		return field(obj, idx)
	end

	-- default
	return nil
end

local function setfield(obj, idx, val, descriptor)
	if descriptor and type(descriptor) == "table" and
		type(descriptor.__set) == "function" then
		-- call data descriptor
		descriptor:__set(obj, val)
		return
	end

	if namespaceGet(obj, idx) ~= nil then
		return
	end

	local field = lookup(obj.__class.__mro, "__newindex")
	if type(field) == "function" then
		-- call __newindex
		field(obj, idx, val)
		return
	end

	-- default
	obj.__table[idx] = val
end

local Class = {
	__getfield = function(self, idx)
		return getfield(self, idx, lookup(self.__class.__mro, idx))
	end;

	__setfield = function(self, idx, val)
		setfield(self, idx, val, lookup(self.__class.__mro, idx))
	end;

	__new = function(self, name, bases, namespace)
		checkArg(1, name, "string")
		checkArg(2, bases, "table")
		checkArg(3, namespace, "table")

		local cls = {
			__class = self,
			__name = name,
			__table = namespace,
			__bases = bases,
			__mro = merge(bases),
		}
		if not cls.__mro then
error("Cannot create a consistent method resolution order (MRO) for bases", 3)
		end
		table.insert(cls.__mro, 1, cls)
		return setmetatable(cls, getmetatable(self))
	end;

	__init = function(self)
	end;

	__call = function(self, ...)
		local obj = self:__new(...)
		self.__init(obj, ...)
		return obj
	end;

	-- classmethod
	__prepare = function(cls)
		return {}
	end
}
Class = Class:__call("Class", {}, Class)
rawset(Class, "__class", Class)
setmetatable(Class, metatable)
moon.Class = Class

moon.Object = Class("Object", {}, {
	__getfield = Class.__getfield;

	__setfield = Class.__setfield;

	-- classmethod
	__new = function(cls)
		return setmetatable({
			__class = cls,
			__table = {},
		}, getmetatable(cls))
	end;

	__init = function()
	end;
})

local function superLookup(self, idx)
	local mro = self.__native.__class.__mro
	for i = self.__lvl, #mro do
		if mro[i].__table[idx] ~= nil then
			return mro[i].__table[idx]
		end
	end
	return nil
end

moon.Super = Class("Super", {}, {
	__getfield = function(self, idx)
		return getfield(self.__native, idx, superLookup(self, idx))
	end;

	__setfield = function(self, idx, val)
		setfield(self.__native, idx, val, superLookup(self, idx))
	end;

	__new = function(self, cls, obj)
		return setmetatable({
			__class = self,
			__table = true,
			__native = obj,
			__lvl = 1,
		}, getmetatable(obj))
	end;

	__init = function(self, cls, obj)
		checkArg(1, cls, "table")
		checkArg(2, obj, "table")

		local mro = obj.__class.__mro
		for i = 1, #mro do
			if rawequal(mro[i], cls) then
				self.__lvl = i+1
				break
			end
		end
		self.__table = obj.__table
	end;
})

moon.Property = Class("Property", {moon.Object}, {
	__init = function(self, fget, fset)
		checkArg(1, fget, "function")
		if fset ~= nil then
			checkArg(2, fset, "function")
			self.fset = fset
		end
		self.fget = fget
	end;

	__get = function(self, obj)
		return self.fget(obj)
	end;

	__set = function(self, obj, val)
		if not self.fset then
			error("can't set attribute", 2)
		end
		self.fset(obj, val)
	end;
})

---------
-- API --
---------

function moon.class(name, ...)
	local arg, cls, bases = 1, Class, {...}
	if type(name) == "table" then
		arg, cls, name = 2, name, table.remove(bases, 1)
	end
	checkArg(arg, name, "string")

	for i = 1, #bases do
		checkArg(arg+i, bases[i], "table")
	end
	bases[1] = bases[1] or moon.Object

	return cls(name, bases, cls:__prepare(name, bases))
end

function moon.super(cls, obj)
	checkArg(1, cls, "table")
	checkArg(2, obj, "table")
	return Super(cls, obj)
end

function moon.issubclass(cls1, cls2)
	if type(cls1) == "table" and type(cls1.__mro) == "table" then
		local mro = cls1.__mro
		for i = 1, #mro do
			if rawequal(mro[i], cls2) then
				return true
			end
		end
	end
	return false
end
local issubclass = moon.issubclass

function moon.isinstance(inst, cls)
	if type(inst) ~= "table" then
		return false
	end
	return issubclass(inst.__class, cls)
end

function moon.rawget(obj, idx)
	checkArg(1, obj, "table")
	return namespaceGet(obj, idx)
end

function moon.rawset(obj, idx, val)
	checkArg(1, obj, "table")
	obj.__table[idx] = val
end

function moon.classmethod(method)
	checkArg(1, method, "function")
	return function(self, ...)
		if not self.__name then
			-- self is object
			self = self.__class
		end
		return method(self, ...)
	end
end

function moon.staticmethod(method)
	checkArg(1, method, "function")
	return function(_, ...)
		return method(...)
	end
end

return moon