# XML-Convert
XML-Convert is a tool to help convert OpenITG/NotITG song-specific xml files into lua files.
In theory, it should work with any OS that can run lua, but it's only been tested on linux.

Requires lua 5.1+ and luafilesystem:
```
luarocks install luafilesystem
```

To run, pass in the name of a folder, and the converter will recursively scan for `.xml` files to convert into `.lua` files.
```
lua xmlconvert.lua ~/Games/Stepmania\ 5/Songs/MyPack/MySong/
```

The outputted lua files may not work out of the box, but they will certainly be closer to working than the `.xml` files were.
