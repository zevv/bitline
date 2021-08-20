
import strutils
import os
import times except Time
import hashes
import tables
import parseopt

from sdl2/sdl import nil

import misc
import view_types
import view_control
import view_api
import view
import reader
import usage

type

  App = ref object
    root: Group
    views: Table[uint32, View]
    gidCache: Table[string, Group]
    stats: AppStats
    readers: seq[Reader]


proc keyToGroup(app: App, key: string): Group =
  var g: Group
  if key in app.gidCache:
    g = app.gidCache[key]
  else:
    g = app.root
    for id in key.split("."):
      if id notin g.groups:
        g.groups[id] = g.newGroup(id)
        g = g.groups[id]
      else:
        g = g.groups[id]
      app.gidCache[key] = g
  return g


proc addEvent(app: App, t: Time, key, ev, evdata: string) =

  let g = app.keytoGroup(key)
  g.ts.incl t

  var value = NoValue
  try:
    let vs = evdata.splitWhitespace()
    if vs.len > 0:
      value = vs[0].parseFloat()
  except:
    discard

  case ev[0]
    of '+':
      g.events.add misc.Event(kind: ekSpan, data: evdata, time: t)
    of '-':
      if g.events.len > 0:
        g.events[^1].duration = t - g.events[^1].time
    of '!':
      g.events.add misc.Event(kind: ekOneshot, data: evdata, time: t)
    of 'c':
      if g.prevTotal == NoValue:
        g.prevTotal = value
      else:
        let total = g.prevTotal + value
        let dt = t - g.prevTime
        if dt > 0.0:
          value /= dt
          g.events.add misc.Event(kind: ekCounter, data: evdata, time: t, value: value)
          g.vs.incl value
        g.prevTotal = total
      g.prevTime = t

    of 'g', 'v':
      g.events.add misc.Event(kind: ekGauge, data: evdata, time: t, value: value)
      g.vs.incl value
    else:
      discard

# Propagate group timespan to parents and count events

proc updateGroups(app: App, updateViews=false) =

  app.stats.groupCount = 0
  app.stats.eventCount = 0

  proc aux(g: Group): TimeSpan =
    inc app.stats.groupCount
    inc app.stats.eventCount, g.events.len
    for id, gc in g.groups:
      g.ts.incl aux(gc)
    result = g.ts
  let ts = aux(app.root)


proc pollSdl(app: App): bool =

  var e: sdl.Event

  while sdl.pollEvent(addr e) != 0:

    result = true

    case e.kind

    of sdl.Quit:
      quit 0

    of sdl.TextInput:
      let v = app.views[e.key.windowId]
      v.sdlEvent(e)

    of sdl.KeyDown:
      let v = app.views[e.key.windowId]
      v.sdlEvent(e)

    of sdl.KeyUp:
      let v = app.views[e.key.windowId]
      v.sdlEvent(e)

    of sdl.MouseMotion:
      let v = app.views[e.motion.windowId]
      v.sdlEvent(e)

    of sdl.MouseButtonDown:
      let v = app.views[e.button.windowId]
      v.sdlEvent(e)

    of sdl.MouseButtonUp:
      for id, v in app.views:
        if e.button.windowId == 0 or e.button.windowID == id:
          v.sdlEvent(e)

    of sdl.MouseWheel:
      let v = app.views[e.wheel.windowId]
      v.sdlEvent(e)

    of sdl.WindowEvent:
      let v = app.views[e.window.windowId]
      v.sdlEvent(e)

    of sdl.MultiGesture:
      for id, v in app.views:
        v.sdlEvent(e)

    else:
      #echo e.kind
      discard


proc run*(app: App): bool =

  var redraw = 0

  while true:
    
    for id, v in app.views:
      if v.tick():
        redraw = 2

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
      if cpuTime() - t1 > 0.05:
        break

    if needUpdate:
      app.updateGroups()
      redraw = 2

    if redraw == 0:
      sleep 10


proc newApp*(w, h: int, path_session: string): App =

  let app = App(
    root: newGroup(),
  )

  let v = newView(app.root, w, h, path_session)
  app.views[sdl.getWindowId(v.getWindow())] = v

  let cursor = sdl.createSystemCursor(sdl.SYSTEM_CURSOR_ARROW)
  sdl.setCursor(cursor)

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

  var sources: seq[string]
  var opt_path_session = "~/.bitlinerc"

  var p = initOptParser()
  while true:
    next(p)
    case p.kind
    of cmdArgument:
      sources.add p.val
      break
    of cmdLongOption, cmdShortOption:
      case normalize(p.key)
      of "help", "h":
        echo usageCmdline()
        quit(0)
      of "session", "s":
        opt_path_session = p.val
      of "version", "v":
        echo usageVersion()
        quit(0)
      else:
        echo "Unknown option"
    of cmdEnd:
      break

  discard sdl.init(sdl.InitVideo or sdl.InitAudio)
  let app = newApp(600, 400, opt_path_session)

  for fname in commandLineParams():
    app.addReader(fname)

  app.updateGroups(true)
  
  discard app.run()


main()

# vi: ft=nim sw=2 ts=2 

