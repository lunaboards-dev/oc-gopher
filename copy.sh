DISKROOT="/home/sam/ocelot-emus/bootman/ede73b62-224a-49bc-ab41-57ec733b3664"

cat debug.lua gopher/usr/bin/gopher.lua > "$DISKROOT/home/gotui.lua"

cp gopher/usr/lib/gopher.lua "$DISKROOT/usr/lib/gopher.lua"

cp gopher/usr/lib/gobrowse/browser.lua "$DISKROOT/usr/lib/gobrowse/browser.lua"
cp gopher/usr/lib/gobrowse/util.lua "$DISKROOT/usr/lib/gobrowse/util.lua"