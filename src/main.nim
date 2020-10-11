
import sets
import strutils
import os
import gui
import npeg
import npeg
import strformat
import times
import hashes
#import chroma
import tables
import math
import textcache

from sdl2/sdl import nil
from posix import nil

import misc
import view



const
  readBufSize = 256 * 1024


const helpText = """
     a       zoom all
     c       close all
     [ / ]   adjust alpha
     + / -   adjust font size
 shift       measure

   LMB       drag: pan    click: open
   RMB       drag: zoom   click: open & focus
   MMM       drag: row height
"""




proc addEvent(app: App, t: TimeFloat, key, ev, evdata: string) =

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



proc updateEvents(app: App, updateView=false) =

  app.stats.groupCount = 0
  app.stats.eventCount = 0

  if app.root.groups.len == 0:
    return

  proc aux(g: Group): TimeSpan =
      
    inc app.stats.groupCount
    inc app.stats.eventCount, g.events.len

    g.ts = initSpan(TimeFloat.high, TimeFloat.low)
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
    if updateView or v.ts.v1 == NoTime:
      v.ts = ts


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
      let
        v = app.views[e.key.windowId]
        c = v.cmdLine
      if c.active:
        var i = 0
        while e.text.text[i] != '\0':
          c.s.add $e.text.text[i]
          inc i

    if e.kind == sdl.KeyDown:
      let
        v = app.views[e.key.windowId]
        key = e.key.keysym.sym
        c = v.cmdLine
      echo key.repr

      if c.active:
        case key
        of sdl.K_RETURN:
          c.active = false
        of sdl.K_ESCAPE:
          c.active = false
        of sdl.K_BACKSPACE:
          if c.s.len > 0:
            c.s = c.s[0..^2]
        else:
          discard

      else:

        case key
        of sdl.K_ESCAPE, sdl.K_Q:
          quit(0)
        of sdl.K_SEMICOLON:
          c.active = true
        of sdl.K_EQUALS:
          inc v.rowSize
        of sdl.K_MINUS:
          dec v.rowSize
        of sdl.K_LEFTBRACKET:
          v.alpha = clamp(v.alpha * 0.8, 0.1, 1.0)
        of sdl.K_RIGHTBRACKET:
          v.alpha = clamp(v.alpha / 0.8, 0.1, 1.0)
        of sdl.K_LSHIFT:
          v.tMeasure = v.x2time(v.mouseX)
        of sdl.K_LALT:
          v.showGui = true
        of sdl.K_a:
          app.updateEvents(true)
          v.yTop = 0
        of sdl.K_c:
          v.isOpen.clear
        of sdl.K_COMMA:
            v.zoomX 1.0/0.9
        of sdl.K_PERIOD:
            v.zoomX 0.9
        of sdl.K_LEFT:
            v.panX -50
        of sdl.K_RIGHT:
            v.panX 50
        of sdl.K_h:
          discard sdl.showSimpleMessageBox(0, "help", helpText, v.win);
        else:
          discard

    if e.kind == sdl.KeyUp:
      let key = e.key.keysym.sym
      let v = app.views[e.key.windowId]
      case key
      of sdl.K_LSHIFT:
        v.tMeasure = NoTime
      of sdl.K_LALT:
        v.showGui = false
      else:
        discard

    if e.kind == sdl.MouseMotion:
      let v = app.views[e.motion.windowId]
      v.gui.mouseMove e.motion.x, e.motion.y
      v.mouseX = e.motion.x
      v.mouseY = e.motion.y
      let dx = v.dragX - v.mouseX
      let dy = v.dragY - v.mouseY
      v.dragX = e.button.x
      v.dragY = e.button.y

      if not v.gui.isActive():

        if v.dragButton != ButtonNone:
          inc v.dragged, abs(dx) + abs(dy)

        if v.dragButton == ButtonLeft:
          v.yTop -= dy
          v.panX dx

        if v.dragButton == ButtonRight:
          v.zoomX pow(1.01, dy.float)
          v.panX dx

        if v.dragButton == ButtonMiddle:
          v.alpha = (v.alpha * pow(1.01, dy.float)).clamp(0.1, 1.0)


    if e.kind == sdl.MouseButtonDown:
      let b = e.button.button.MouseButton
      let v = app.views[e.button.windowId]
      v.gui.mouseButton e.button.x, e.button.y, 1
      v.dragButton = b
      v.dragged = 0

      if b == ButtonMiddle:
        v.tMeasure = v.x2time(e.button.x)

    if e.kind == sdl.MouseButtonUp:
      let b = e.button.button.MouseButton

      for id, v in app.views:
        if e.button.windowId == 0 or e.button.windowID == id:
          v.gui.mouseButton e.button.x, e.button.y, 0
          v.dragButton = ButtonNone
          if v.dragged < 3:

            if b == ButtonLeft:
              if v.curGroup != nil:
                if v.curGroup in v.isOpen:
                  v.isOpen.excl v.curGroup
                else:
                  v.isOpen.incl v.curGroup

            if b == ButtonRight:
              if v.curGroup != nil:
                v.isOpen.incl v.curGroup
                let dt = v.curGroup.ts.v2 - v.curGroup.ts.v1
                v.ts.v1 = v.curGroup.ts.v1 - (dt / 5)
                v.ts.v2 = v.curGroup.ts.v2 + (dt / 20)
    
          if b == ButtonMiddle:
            v.tMeasure = NoTime

    if e.kind == sdl.MouseWheel:
      let v = app.views[e.wheel.windowId]
      if v.curGroup != nil:
        let h = v.groupScale.mgetOrPut(v.curGroup, 0)
        inc v.groupScale[v.curGroup], e.wheel.y
        v.groupScale[v.curGroup] = v.groupScale[v.curGroup].clamp(0, 6)

    if e.kind == sdl.WindowEvent:
      let v = app.views[e.window.windowId]
      if e.window.event == sdl.WINDOWEVENT_RESIZED:
        v.w = e.window.data1
        v.h = e.window.data2



proc run*(app: App): bool =

  var redraw = 0

  while true:

    if app.pollSdl():
      redraw = 2

    if redraw > 0:
      for _, v in app.views:
        v.draw()
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

  app.newView(w, h)

  discard app.readEvents()
  app.updateEvents(true)

  return app


discard sdl.init(sdl.InitVideo or sdl.InitAudio)
let a = newApp(600, 400)

echo sizeof(Event)

#a.loadEvents("events")
discard a.run()


# vi: ft=nim sw=2 ts=2 

