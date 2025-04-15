DISKROOT="~/ocelot-emus/bootman/ede73b62-224a-49bc-ab41-57ec733b3664"

cat debug.lua bin/gopher.lua > "$DISKROOT/home/gotui.lua"

cp lib/libgopher.lua "$DISKROOT/usr/lib/gopher.lua"

cp lib/gobrowse/browser.lua "$DISKROOT/usr/lib/gobrowse/browser.lua"
cp lib/gobrowse/util.lua "$DISKROOT/usr/lib/util.lua"