local util = {}

function util.usub(str, i, j)
	if not str then
		error("no string", 2)
	end
	if not j then
		j = utf8.len(str)
	end
	local spos = utf8.offset(str, i)
	local epos = utf8.offset(str, j)
	return str:sub(spos, epos)
end

function util.upad(str, len)
	return str .. string.rep(" ", len-utf8.len(str))
end

function util.uclamp(str, len)
	if not str then
		error("no string", 2)
	end
	if utf8.len(str) > len then
		str = util.usub(str, 1, len-1).. "…"
	end
	return str
end

function util.replace_tab(str)
	return (str:gsub("\t", "§"))
end

return util