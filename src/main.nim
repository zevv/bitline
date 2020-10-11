
import sets
import strutils
import os
import gui
import strformat
import times except Time
import hashes
import tables
import math
import textcache

from sdl2/sdl import nil
from posix import nil

import misc
import view


type
  App* = ref object
    root*: Group
    views*: Table[uint32, View]
    gidCache*: Table[string, Group]
    rxBuf*: string
    rxPtr*: int
    stats*: AppStats


const
  readBufSize = 256 * 1024



proc addEvent(app: App, t: Time, key, ev, evdata: string) =

  var g: Group
  if key in app.gidCache:
    g = app.gidCache[key]
  else:
    g = app.root
    for id in key.split("."):
      if id notin g.groups:
        g.groups[id] = Group(id: id)
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
      g.vs.incl(e.value)

    for id, gc in g.groups:
      let gts = aux(gc)
      g.ts.v1 = min(g.ts.v1, gts.v1)
      g.ts.v2 = max(g.ts.v2, gts.v2)

    result = g.ts

  let ts = aux(app.root)

  for _, v in app.views:
    v.setSpan(ts, updateViews)


proc parseEvent(app: App, l: string) =
  let r = l.splitWhiteSpace(3)

  if r.len >= 3:

    let (ts, key, ev) = (r[0], r[1], r[2])
    let evdata = if r.len == 4: r[3] else: ""
    var t = NoTime

    try:
      t = ts.parse(iso8601format).toTime.toUnixFloat
    except:
      discard

    try:
      t = ts.parseFloat()
    except:
      discard

    if t != NoTime:
      app.addEvent(t, key, ev, evdata)


proc readEvents(app: App): bool =
  var count = 0

  var pfds: seq[posix.TPollfd]
  pfds.add posix.TPollfd(fd: 0.cint, events: posix.POLLIN)

  let r = posix.poll(pfds[0].addr, posix.Tnfds(pfds.len), 0)
  if r == 0:
    return false

  let n = posix.read(0, app.rxBuf[app.rxPtr].addr, readBufSize - app.rxPtr)
  if n <= 0:
    return false

  app.rxPtr += n
  var o1 = 0
  var o2 = 0

  while true:
    o2 = app.rxBuf.find("\n", o1, app.rxPtr-1)
    if o2 > -1:
      let l = app.rxBuf[o1..<o2]
      app.parseEvent(l)
      inc count
      o1 = o2 + 1
    else:
      let nLeft = app.rxPtr - o1
      if nLeft > 0:
        moveMem(app.rxBuf[0].addr, app.rxBuf[o1].addr, nLeft)
      app.rxPtr = nLeft
      break


  return count > 0


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
    while app.readEvents() and cpuTime() - t1 < 0.01:
      needUpdate = true
    if needUpdate:
      app.updateEvents()
      redraw = 2

    if redraw == 0:
      sleep 10



proc newApp*(w, h: int): App =

  let app = App()
  app.root = Group(id: "/")
  app.rxBuf = newString(readBufSize)

  let v = newView(app.root, w, h)
  app.views[sdl.getWindowId(v.getWindow())] = v

  discard app.readEvents()
  app.updateEvents(true)

  return app


discard sdl.init(sdl.InitVideo or sdl.InitAudio)
let a = newApp(600, 400)

echo sizeof(Event)

#a.loadEvents("events")
discard a.run()


# vi: ft=nim sw=2 ts=2 

