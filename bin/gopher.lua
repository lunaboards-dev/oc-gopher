local gopher = require("gopher")

if not gopher.has_minitel() and not gopher.has_internet() then
	io.stderr:write("gopher requires either an internet card or minitel to be installed\n")
	os.exit(1)
end

local args, opts = require("shell").parse(...)

if opts.h or #args ~= 1 then
	io.stderr:write("Usage: gopher <url>\n")
	os.exit(1)
end

local etypes = {
	["0"] = "TEXT",
	["1"] = "DIR",
	["2"] = "NS",
	["3"] = "ERROR",
	["4"] = "BINHEX",
	["5"] = "EXE",
	["6"] = "UUFILE",
	["7"] = "<SEARCH>",
	["8"] = "TELNET",
	["9"] = "FILE",
	["+"] = "<ALT>",
	g = "GIF",
	I = "IMG",
	T = "3270",
	[":"] = "BMP",
	[";"] = "VID",
	["<"] = "SND",
	d = "DOC",
	h = "HTML",
	i = "",
	p = "IMG",
	r = "RTF",
	s = "SND",
	P = "PDF",
	X = "XML"
}
xpcall(function()
	local res, file, buf = gopher.req(args[1])
	if type(res) == "table" and not file then
		for i=1, #res do
			local l = res[i]
			if not l.type then
				print("")
			elseif l.type == "i" then
				print(l.display)
			else
				print(string.format("(%s) %s", etypes[l.type] or "UNK", l.display))
			end
		end
	elseif type(res) == "string" then
		print(res)
	else
		io.stderr:write("TODO: handle binary files\n")
	end
end, function(err) io.stderr:write(debug.traceback(err)) end)