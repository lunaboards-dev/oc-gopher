local gopher = require("gopher")
local term = require("term")
local event = require("event")
local quit

local events = {}

if not gopher.has_minitel() and not gopher.has_internet() then
	io.stderr:write("gopher requires either an internet card or minitel to be installed\n")
	os.exit(1)
end

local args, opts = require("shell").parse(...)

if opts.h or #args ~= 1 then
	io.stderr:write("Usage: gotui <url>\n")
	os.exit(1)
end
xpcall(function()
	local function u8sub(str, i, j)
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

	local function pad(str, len)
		return str .. string.rep(" ", len-utf8.len(str))
	end

	local function clamp(str, len)
		if not str then
			error("no string", 2)
		end
		if utf8.len(str) > len then
			str = u8sub(str, 1, len-1).. "…"
		end
		return str
	end

	local function line_format()

	end

	local offset = 0
	local sel_link = 0

	local etypes = {
		["0"] = "📝",
		["1"] = "📁",
		["2"] = "☏",
		["3"] = "\27[31m!!\27[0m",
		["4"] = " H",
		["5"] = "💻",
		["6"] = " U",
		["7"] = "<SEARCH>",
		["8"] = "🖥",
		["9"] = "💾",
		["+"] = "<ALT>",
		g = "📹",
		I = "🖼",
		T = "3270",
		[":"] = "BMP",
		[";"] = "📹",
		["<"] = "SND",
		d = "DOC",
		h = "🔗",
		i = "",
		p = "🖼",
		r = "RTF",
		s = "SND",
		P = "PDF",
		X = "XML"
	}

	local search_text = ""
	local tmp_url
	local url
	local w, h = term.getViewport()

	local pages = {}
	local state

	local function clear_term()
		term.write("\27[2J\27[H")
	end

	local function e_write(str)
		term.write("\27[2K"..str)
	end

	local link_pos = {}
	local not_link = {["3"] = true, i = true, ["+"] = true}

	-- Update link positions
	local function recompute()
		link_pos = {}
		sel_link = 0
		for i=1, math.min(#state-offset, h-1) do
			local e = state[i+offset]
			if e and e.type and not not_link[e.type] then
				table.insert(link_pos, {
					y = i,
					width = utf8.len(e.display),
					type = e.type
				})
			end
		end
	end

	local function redraw_line(ent, y)
		local e = state[ent]
		term.setCursor(1, y)
		if not e then return end
		if e.type == "i" then
			e_write("   "..e.display)
		elseif e.type == "7" then
			if sel_link > 0 and link_pos[sel_link].y == y then
				e_write(string.format("🔍 \27[33m%s:\27[0m %s", e.display, search_text))
				return utf8.len(e.display..": "..search_text)+2
			else
				e_write(string.format("🔍 \27[35m%s:\27[0m %s", e.display, search_text))
			end
		elseif e.type then
			if sel_link > 0 and link_pos[sel_link].y == y then
				e_write((etypes[e.type] or (e.type.."?"))..string.format(" \27[33m%s\27[0m", clamp(e.display or "", w-3)))
			else
				e_write((etypes[e.type] or (e.type.."?"))..string.format(" \27[36m%s\27[0m", clamp(e.display or "", w-3)))
			end
		end
	end

	local function redraw()
		local cur_pos, cy
		for i=1, math.min(#state-offset, h-1) do
			cur_pos = redraw_line(i+offset, i)
			if cur_pos then
				cy = i
			end
		end
		term.setCursor(1, h)
		if tmp_url then
			term.write("\27[30;47m"..clamp(pad(string.format("Enter URL: %s", tmp_url), w-1), w).."\27[0m")
			cur_pos = utf8.len("Enter URL: "..tmp_url)
			cy = h
		else
			term.write("\27[30;47m"..clamp(pad(string.format("gotui | g Goto - ← Back - → Follow | %s ", url:gsub("\t", "§")), w-1), w).."\27[0m")
		end
		if cur_pos then
			term.setCursor(cur_pos, cy)
		end
	end

	local function navigate(to, nopush)
		if not nopush then
			table.insert(pages, url)
		end
		url = to
		search_text = to:match("\t(.+)") or ""
		offset = 0
		sel_link = 0
		local res, file, buf = gopher.req(to)
		if not res then error(file) end
		if type(res) == "table" and not file then
			state = res
		elseif type(res) == "string" then
			state = {}
			for line in res:gmatch("[^\n]*") do
				table.insert(state, {
					type = "i",
					display = line:gsub("\r$", "")
				})
			end
		end
		recompute()
		clear_term()
		redraw()
	end

	navigate(args[1], true)

	local codes = {
		[208] = "down",
		[200] = "up",
		[203] = "left",
		[205] = "right",
		[201] = "pgup",
		[209] = "pgdn"
	}

	local vh = h-1

	local function clamp_offset()
		if offset < 0 then
			offset = 0
		end
		if #state-offset < vh then
			offset = math.max(0, #state - vh)
		end
	end

	local function handle_input(buffer, key, code)
		local char = string.char(key)
		local skey = codes[code]
		if key > 31 and key < 127 then
			buffer = buffer .. char
		elseif key == 13 then
			return buffer, true
		elseif key == 8 then
			buffer = buffer:sub(1, #buffer-1)
		end
		return buffer
	end

	function events.key_down(_, kb, key, code)
		local char = string.char(key)
		local skey = codes[code]
		local go
		local function handle_navigation()
			if skey == "pgdn" then
				offset = offset + vh
				recompute()
				sel_link = 0
				clear_term()
				clamp_offset()
				redraw()
			elseif skey == "pgup" then
				offset = offset - vh
				recompute()
				sel_link = 0
				clear_term()
				clamp_offset()
				redraw()
			elseif skey == "down" then
				sel_link = sel_link + 1
				if sel_link > #link_pos then
					sel_link = #link_pos
				end
				redraw()
			elseif skey == "up" then
				sel_link = sel_link - 1
				if sel_link < 0 then
					sel_link = 0
				end
				redraw()
			end
		end
		if tmp_url then
			tmp_url, go = handle_input(tmp_url, key, code)
			if go then
				local t = tmp_url
				tmp_url = nil
				navigate(t)
			end
		elseif sel_link > 0 and link_pos[sel_link].type == "7" then
			search_text, go = handle_input(search_text, key, code)
			local y = link_pos[sel_link].y
			if go then
				local e = state[y+offset]
				navigate(string.format("%s://%s:%d/7%s\t%s", state.proto, e.host, e.port, e.rsc, search_text))
			else
				local cur_pos = redraw_line(y+offset, y)
				term.setCursor(cur_pos, y)
				handle_navigation()
			end
		else
			if char == "q" then
				quit = true
			elseif char == "g" then
				-- Bring up URL entry
				tmp_url = url:gsub("\t.+", "")
			elseif (key == 13 or skey == "right") and sel_link > 0 then
				local e = state[link_pos[sel_link].y+offset]
				navigate(string.format("%s://%s:%d/%s%s", state.proto, e.host, e.port, e.type, e.rsc))
			elseif skey == "left" then
				local back = table.remove(pages)
				navigate(back, true)
			else
				handle_navigation()
			end
			clamp_offset()
		end
	end

	function events.scroll(_, scr, x, y, amt)
		amt = -amt
		offset = offset + amt
		clamp_offset()
		recompute()
		redraw()
	end

	function events.clipboard(_, kb, text)
		if tmp_url then
			tmp_url = tmp_url .. text
		elseif link_pos[sel_link].type == "7" then
			search_text = search_text .. text
		end
	end

	function events.touch(_, scr, x, y)
		for i=1, #link_pos do
			if not link_pos[i] then goto continue end
			if link_pos[i].y == y and x < link_pos[i].width+2 and x > 2 then
				local e = state[y]
				if e.type == "7" then
					sel_link = i
					redraw()
					return
				elseif not not_link[e.type] then
					navigate(string.format("%s://%s:%d/%s%s", state.proto, e.host, e.port, e.type, e.rsc))
				end
			end
			::continue::
		end
	end

	function events.interrupted()
		tmp_url = nil
		redraw()
	end

	local es = {}

	for k, v in pairs(events) do
		es[k] = function(...)
			xpcall(v, function(err)
				io.stderr:write(debug.traceback(err))
			end, ...)
		end
		event.listen(k, es[k])
	end
	while not quit do
		if tmp_url then
			term.setCursor(1, h)
			term.write("\27[30;47m"..clamp(pad(string.format("Enter URL: %s", tmp_url), w-1), w).."\27[0m")
		end
		os.sleep(0.001)
	end

	for k, v in pairs(events) do
		event.ignore(k, es[k])
	end

	clear_term()
	term.setCursor(1,1)
end, function(err)
	io.stderr:write(debug.traceback(err))
end)