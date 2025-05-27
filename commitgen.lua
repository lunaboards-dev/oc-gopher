local h = io.popen("git log -5", "r")

local cur_commit = {desc = {}}

local function write_commit()
	if cur_commit.hash then
		print(string.format("%s [%s]: %s", cur_commit.hash:sub(1, 8), cur_commit.author, table.concat(cur_commit.desc, " "):gsub("^%s+", ""):gsub("%s+$", "")))
		cur_commit = {desc = {}}
	end
end

for line in h:lines() do
	local key, value = line:match("(%S+)%s+(.+)")
	--print("k", key, "v", value)
	--print(line:match("^(%S+)%s+"))
	if key == "commit" then
		write_commit()
		cur_commit.hash = value
	elseif key == "Author:" then
		cur_commit.author = value:match("^[^<]+"):gsub("%s+$", "")
	elseif key == "Date:" then
		cur_commit.date = value
	else
		table.insert(cur_commit.desc, (line:gsub("^%s+", "")))
	end
end

write_commit()