rm -r build
mkdir build
cp -r gopher build

lua commitgen.lua > build/gopher/usr/lib/gobrowse/commit.info

cd build/gopher

# Basic CPIO
echo "buildcpio" > usr/lib/gobrowse/src.info
find * | cpio -oF ../gopher-src.cpio

# OPPM release
echo "oppm" > usr/lib/gobrowse/src.info
find * | grep -v .prop | cpio -oF ../gopher-oppm.cpio

# Disk release
echo "loot" > usr/lib/gobrowse/src.info
find * | cpio -oF ../gopher-loot.cpio

# Net release
echo "net" > usr/lib/gobrowse/src.info
find * | grep -v .prop | cpio -oF ../gopher-src.cpio

# Basic CPIO
echo "local" > usr/lib/gobrowse/src.info