do
	local packages = {
		"gopher",
		"libgopher",
		"gobrowse.browser",
		"gobrowse.util"
	}
	for i=1, #packages do
		package.loaded[packages[i]] = nil
	end
end
