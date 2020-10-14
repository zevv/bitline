# Package

version       = "0.1.0"
author        = "Ico Doornekamp"
description   = "High performance event visualization"
license       = "GPL-2.0"
srcDir        = "src"
bin           = @["bitline"]

# Dependencies

requires "nim >= 1.2.0", "sdl2_nim >= 2.0.10.0", "chroma >= 0.1.0"

task build, "Build":
  exec "nim c -d:danger -o:bitline src/bitline.nim"

task release, "Release":
  exec "nimble build"
  exec "scp ./bitline ico@mdoos:~/div"
