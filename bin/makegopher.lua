local ifile, ofile = ...
local hi = assert(io.open(ifile, "r"))
local ho = assert(io.open(ofile, "w"))
for line in hi:lines() do
	if line:sub(1,1) == "i" then
		ho:write(line.."\n")
	else
		ho:write(line:gsub("  +", "\t").."\n")
	end
end
hi:close()
ho:close()