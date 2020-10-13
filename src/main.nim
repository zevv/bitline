
import strutils
import os
import times except Time
import hashes
import tables

from sdl2/sdl import nil

import misc
import view
import reader


type

  App = ref object
    root: Group
    views: Table[uint32, View]
    gidCache: Table[string, Group]
    stats: AppStats
    readers: seq[Reader]


proc addEvent(app: App, t: Time, key, ev, evdata: string) =

  var g: Group
  if key in app.gidCache:
    g = app.gidCache[key]
  else:
    g = app.root
    var bin = -1
    for id in key.split("."):
      if bin == -1: bin = hash(id) mod 10
      if id notin g.groups:
        g.groups[id] = Group(id: id, bin: bin)
      g = g.groups[id]
    app.gidCache[key] = g

  var value = NoValue
  try:
    value = evdata.parseFloat()
  except:
    discard

  case ev[0]
    of '+':
      g.events.add misc.Event(data: evdata, ts: initSpan(t, NoTime), value: value)
    of '-':
      if g.events.len > 0:
        g.events[^1].ts.v2 = t
    of '!':
      g.events.add misc.Event(data: evdata, ts: initSpan(t, t), value: value)
    else:
      discard



proc updateEvents(app: App, updateViews=false) =

  app.stats.groupCount = 0
  app.stats.eventCount = 0

  if app.root.groups.len == 0:
    return

  proc aux(g: Group): TimeSpan =
      
    inc app.stats.groupCount
    inc app.stats.eventCount, g.events.len

    g.ts = initSpan(Time.high, Time.low)
    g.vs = initSpan(Value.high, Value.low)

    if g.events.len > 0:
      g.ts.incl(g.events[0].ts)
      g.ts.incl(g.events[^1].ts)

    for e in g.events:
      if e.value != NoValue:
        g.vs.incl(e.value)

    for id, gc in g.groups:
      let gts = aux(gc)
      g.ts.v1 = min(g.ts.v1, gts.v1)
      g.ts.v2 = max(g.ts.v2, gts.v2)

    result = g.ts

  let ts = aux(app.root)

  for _, v in app.views:
    v.setSpan(ts, updateViews)



proc pollSdl(app: App): bool =

  var e: sdl.Event

  while sdl.pollEvent(addr e) != 0:

    result = true

    if e.kind == sdl.Quit:
      quit 0

    if e.kind == sdl.TextInput:
      let v = app.views[e.key.windowId]
      v.sdlEvent(e)

    if e.kind == sdl.KeyDown:
      let v = app.views[e.key.windowId]
      let key = e.key.keysym.sym
      case key:
        of sdl.K_a:
          app.updateEvents(true)
        else:
          discard
      v.sdlEvent(e)

    if e.kind == sdl.KeyUp:
      let v = app.views[e.key.windowId]
      v.sdlEvent(e)

    if e.kind == sdl.MouseMotion:
      let v = app.views[e.motion.windowId]
      v.sdlEvent(e)

    if e.kind == sdl.MouseButtonDown:
      let v = app.views[e.button.windowId]
      v.sdlEvent(e)

    if e.kind == sdl.MouseButtonUp:
      for id, v in app.views:
        if e.button.windowId == 0 or e.button.windowID == id:
          v.sdlEvent(e)

    if e.kind == sdl.MouseWheel:
      let v = app.views[e.wheel.windowId]
      v.sdlEvent(e)

    if e.kind == sdl.WindowEvent:
      let v = app.views[e.window.windowId]
      v.sdlEvent(e)



proc run*(app: App): bool =

  var redraw = 0

  while true:

    if app.pollSdl():
      redraw = 2

    if redraw > 0:
      for _, v in app.views:
        v.draw(app.stats)
      dec redraw

    let t1 = cpuTime()
    var needUpdate = false

    while true:
      var worked = false
      for r in app.readers:
        if r.read():
          needUpdate = true
          worked = true
      if not worked:
        break
      if cpuTime() - t1 > 0.01:
        break

    if needUpdate:
      app.updateEvents()
      redraw = 2

    if redraw == 0:
      sleep 10


proc newApp*(w, h: int): App =

  let app = App()
  app.root = Group(id: "")
  let v = newView(app.root, w, h)
  app.views[sdl.getWindowId(v.getWindow())] = v
  return app
  


proc addReader(app: App, fname: string) =

  echo "Add reader ", fname

  var fname = fname
  if fname == "-":
    fname = "/dev/stdin"

  let onEvent = proc(t: Time, key, ev, evdata: string) =
    app.addEvent(t, key, ev, evdata)

  let reader = newReader(fname, onEvent)
  if reader != nil:
    app.readers.add reader



proc main() =
  discard sdl.init(sdl.InitVideo or sdl.InitAudio)
  let a = newApp(600, 400)

  for fname in commandLineParams():
    a.addReader(fname)
  
  discard a.run()


main()

# vi: ft=nim sw=2 ts=2 

