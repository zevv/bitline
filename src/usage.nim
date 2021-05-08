
const buildRev = gorge("git rev-parse --short=10 HEAD")
const buildTime = gorge("date '+%Y-%M-%d %H:%M:%S'")
const NimblePkgVersion {.strdefine.} = ""


proc usageVersion*(): string =
  "version: " & NimblePkgVersion & ", git: " & buildRev & ", date: " & buildTime


proc usage*(): string = """

keys:
 a             zoom all
 c /o          close all / open all
 l             toggle log scale for graphs"
 q             quit
 [ / ]         adjust alpha
 + / -         adjust font size
 shift         measure
 /             search
 0..9          set group
 shift + 0..9  toggle group

mouse:
 LMB           drag: pan    click: open
 RMB           drag: zoom   click: open & zoom
 MMB           drag: row height
 wheel         adjust row size

""" & usageVersion()


proc usageCmdline*(): string = """
usage: bitline [options] [FILE...]

options:

  -h, --help          display this help and exit
  -s, --session FILE  use FILE for saving/loading session state
  -v, --version       output version information and exit

""" & usageVersion()
