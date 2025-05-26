local builder = {}

function builder:add(ltype, text, rsc, host, port, extra)
	table.insert(self, {
		type = ltype,
		display = text,
		rsc = rsc or "nil",
		host = host or "null.host",
		port = port or 0,
		extra = extra
	})
end

function builder:print(text)
	self:add("i", text)
end

function builder:error(text)
	self:add("3", text)
end

function builder:control()
	
end

return function()
	return setmetatable({}, {__index=builder})
end