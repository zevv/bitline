
import sdl2/sdl_ttf as ttf
import sdl2/sdl
import sets
import algorithm
import sugar
import strutils
import os
import npeg
import npeg
import strformat
import times
import hashes
#import chroma
import tables
import math
import textcache

import gui
import misc

const
  colBg           = sdl.Color(r: 32, g: 32, b: 32, a:255)
  colGrid         = sdl.Color(r:196, g:196, b:196, a: 96)
  colCursor       = sdl.Color(r:255, g:128, b:128, a:255)
  colMeasure      = sdl.Color(r:255, g:255, b:128, a: 32)
  colEvent        = sdl.Color(r:  0, g:255, b:173, a:150)
  colKey          = sdl.Color(r:250, g:200, b:100, a:255)
  colEventSel     = sdl.Color(r:255, g:255, b:255, a: 30)
  colStatusbar    = sdl.Color(r:255, g:255, b:255, a:128)
  colGraph        = sdl.Color(r:180, g:  0, b:255, a:255)

# Helpers

proc time2x*(v: View, t: TimeFloat): int =
  result = int(v.w.float * (t - v.ts.v1) / (v.ts.v2 - v.ts.v1))

proc x2time*(v: View, x: int): TimeFloat =
  v.ts.v1 + (x / v.w) * (v.ts.v2-v.ts.v1)


# Drawing primitives

proc setColor(v: View, col: sdl.Color) =
  discard v.rend.setRenderDrawColor(col)

proc drawLine(v: View, x1, y1, x2, y2: int) =
  if (x1 > 0 or x2 > 0) and (x1 < v.w or x2 < v.w):
    discard v.rend.renderDrawLine(x1, y1, x2, y2)

proc drawFillRect(v: View, x1, y1, x2, y2: int) =
  if (x1 > 0 or x2 > 0) and (x1 < v.w or x2 < v.w):
    var r = Rect(x: x1, y: y1, w: x2-x1+1, h: y2-y1+1)
    discard v.rend.renderFillRect(r.addr)

proc drawRect(v: View, x1, y1, x2, y2: int) =
  if (x1 > 0 or x2 > 0) and (x1 < v.w or x2 < v.w):
    var r = Rect(x: x1, y: y1, w: x2-x1+1, h: y2-y1+1)
    discard v.rend.renderDrawRect(r.addr)

proc drawText(v: View, x, y: int, text: string, col: sdl.Color, align=AlignLeft) =
  v.textCache.drawText(text, x, y, col, align)


# Draw UI components

proc drawGrid*(v: View) =

  let
    y1 = v.rowSize + 2
    y2 = v.h - v.rowSize * 3 - 5
    y3 = v.h - v.rowSize * 2 - 5
    y4 = v.h - v.rowSize * 1 - 4

  v.setColor(colGrid)
  v.drawLine(0, y1, v.w, y1)
  v.drawLine(0, y4, v.w, y4)
  
  if v.tMeasure != NoTime:
    return

  proc aux(tFrom: DateTime, dt: float, fmts1, fmts2: string) =
    var
      t = tFrom.toTime.toUnixFloat
      dtw = v.w.float * dt / v.ts.duration
      alpha = uint8 min( 64, dtw)

    var col = colGrid
    col.a = alpha
    v.setColor col

    if dtw > 5 and dtw < v.w.float:
      while t < v.ts.v2:
        let x = v.time2x(t)
        if x > -80 and x < v.w:
          v.drawLine(x, y1, x, y4)
          if dtw > 80:
            v.drawText(x+2, y2, t.fromUnixFloat.utc.format(fmts1), col)
          if dtw > 20:
            v.drawText(x+2, y3, t.fromUnixFloat.utc.format(fmts2), col)
        t += dt

  let t = v.ts.v1.fromUnixFloat.utc
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=t.hour, minute=t.minute, second=0, utc()), 0.001, "mm:ss", "fff")
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=t.hour, minute=t.minute, second=0, utc()), 0.01, "mm:ss", "fff")
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=t.hour, minute=t.minute, second=0, utc()), 0.1, "mm:ss", "fff")
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=t.hour, minute=t.minute, second=0, utc()), 1.0, "HH:mm:ss", "ss")
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=t.hour, minute=0, second=0, utc()), 10.0, "HH:mm:ss", "ss")
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=t.hour, minute=0, second=0, utc()), 60.0, "HH:mm:ss", "mm")
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=t.hour, minute=0, second=0, utc()), 600.0, "HH:mm", "mm")
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=0, minute=0, second=0, utc()), 3600.0, "HH:mm", "HH")
  aux(initDateTime(year=t.year, month=t.month, monthday=1, hour=0, minute=0, second=0, utc()), 24*3600.0, "ddd dd-MM", "dd")
  aux(initDateTime(year=t.year, month=mJan, monthday=1, hour=0, minute=0, second=0, utc()), 30*24*3600.0, "MMM yyyy", "MMM")
  aux(initDateTime(year=1970, month=mJan, monthday=1, hour=0, minute=0, second=0, utc()), 365*24*3600.0, "yyyy", "MMM")


proc drawCursor*(v: View) =
  let
    x = v.mouseX
    t = v.x2time(x)

  v.setColor(colCursor)
  v.drawFillRect(x, v.rowSize, x, v.h)
  var label = ""
  
  if v.tMeasure == NoTime:

    label = t.fromUnixFloat.utc.format("ddd yyyy-MM-dd HH:mm:ss,fff")

  else:

    let dt = t - v.tMeasure
    let x2 = v.time2x(v.tMeasure)
    v.setColor(colMeasure)
    v.drawFillRect(x, 0, x2, v.h)

    label = fmtDuration(dt)
    if dt != 0.0:
      label.add " / " & fmtFrequency(1.0/dt)

    for i in -20..20:
      if i != 1:
        var col = colMeasure
        col.a = (255 /% (abs(i)+1)).uint8
        v.setColor(col)
        let dt3 = dt * i.float
        let x2 = v.time2x(v.tMeasure + dt3)
        v.drawLine(x2, 0, x2, v.h)

  v.drawText(x + 2, 0, label, colCursor, AlignCenter)


proc measure(v: View, group: Group): string =

  let
    tMouse = v.x2time(v.mouse_x)
    ts1 = min(tMouse, v.tMeasure)
    ts2 = max(tMouse, v.tMeasure)

  if ts1 == ts2:
    return

  var count = 0
  var time = 0.0

  proc aux(g: Group) =
    for id, ev in g.events:
      if ts1 < ev.ts.v1 and ts2 >= ev.ts.v2:
        inc count
      let tsint1 = max(ts1, ev.ts.v1)
      let tsint2 = min(ts2, ev.ts.v2)
      if tsint2 > tsint1:
        time += tsint2 - tsint1

    for id, cg in g.groups:
      aux(cg)

  aux(group)

  var parts: seq[string]

  let dutyCycle = 100.0 * time / (ts2-ts1)

  parts.add siFmt(count, "",  true)
  if time > 0:
    parts.add siFmt(time,  "s", true)
    parts.add &"{dutyCycle:.1f}%"

  result.add parts.join(" / ")


proc drawData*(v: View) =

  let app = v.app
  v.curGroup = nil
  v.curEvent = nil

  type Label = object
    text: string
    x: int
    y: int
    col: Color

  var labels: seq[Label]

  # Draw events

  proc drawEvents(g: Group, y: int, h: int) =

    var rects = newSeqOfCap[Rect](g.events.len)
    var points: seq[Point]
    var xprev = 0

    # Binary search for event indices which lie in the current view
    var i1 = g.events.lowerbound(v.ts.v1, (e, t) => cmp(if e.ts.v2 != NoTime: e.ts.v2 else: e.ts.v1, t))
    var i2 = g.events.upperbound(v.ts.v2, (e, t) => cmp(e.ts.v1, t))

    for i in i1 ..< i2:

      let e = g.events[i]
      var x1 = v.time2x(e.ts.v1)
      var x2 = if e.ts.v2 == NoTime or e.ts.v2 == e.ts.v1:
          x1 + 1 # Oneshot or incomplete span
        else:
          max(v.time2x(e.ts.v2), x1+1)

      # Only draw this event if it is at least 1 pixel away from the last drawn
      # event. This is a huge optimization because we will never need to draw
      # more then view.w events per group
      if x2 > xprev:

        # Never overlap over previous events
        x1 = max(x1, xprev)

        # Graph events with a value
        if h > 1 and e.value != NoValue:
          let y2 = y + h - int(h.float * (e.value - g.vs.v1) / (g.vs.v2 - g.vs.v1))
          points.add Point(x: x1, y: y2)

        # Draw event bar
        rects.add Rect(x: x1, y: y, w: x2-x1, h: h)

        # Incomplete span gets a little arrow
        if e.ts.v2 == NoTime:
          for i in 1..<h /% 2:
            rects.add Rect(x: x1+i, y: y+i, w: 1, h: h-i*2)

        xprev = x2 + 1

      # Check for hovering
      if initSpan(y, y+h).contains(v.mouseY) and initSpan(x1, x2).contains(v.mouseX):
        v.curEvent = e
    
    # Render all event rectangles
    var col = colEvent
    col.a = uint8(v.alpha * 255)
    v.setColor(col)
    discard v.rend.renderFillRects(rects[0].addr, rects.len)

    # Render all graph lines
    v.setColor(colGraph)
    discard v.rend.renderDrawLines(points[0].addr, points.len)


  # Draw groups

  var y = v.yTop + 20

  proc drawGroup(g: Group, depth: int) =

    let isOpen = g in v.isOpen
    let yGroup = y

    # Draw label and events for this group
    var h = 0
    var c = colKey
    c.a = uint8(255.0 / sqrt(depth.float))
    labels.add Label(x: depth*10, y: y, text: g.id, col: c)
    if g.events.len > 0:
      h = v.rowSize + v.groupHeight.getOrDefault(g, 0)
      drawEvents(g, y, h)

    # Draw measurements for this group
    if v.tMeasure != NoTime:
      labels.add Label(x: v.mouse_x+2, y: y, text: v.measure(g), col: colEvent)

    y += h

    # For closed groups, draw a birds eye overview of all events under this group
    if not isOpen and g.groups.len > 0:
      proc aux(g: Group) =
        if g.events.len > 0:
          let ts1 = g.events[0].ts.v1
          let ts2 = g.events[^1].ts.v2
          if ts1 < v.ts.v2 and (ts2 == NoTime or ts2 > v.ts.v1):
            drawEvents(g, y, 1)
            y += 1
        for id, cg in g.groups:
          aux(cg)
      aux(g)

    y = max(y, yGroup + v.rowSize) + 4

    if isOpen:
      for id, cg in g.groups:
        drawGroup(cg, depth+1)

    # Check for mouse hover
    if v.mouseY >= yGroup and v.mouseY < y and v.curGroup == nil:
      v.curGroup = g
      v.setColor(colEventSel)
      v.drawFillRect(0, yGroup, v.w, y-1)


  # Recursively draw all groups

  drawGroup(app.root, 0)

  # Draw evdata for current event

  let e = v.curEvent
  if e != nil and v.tMeasure == NoTime:
    if e.value != NoValue:
      labels.add Label(x: v.mouseX, y: v.mouseY, text: e.value.siFmt, col: colEvent)
    elif e.data != "":
      labels.add Label(x: v.mouseX, y: v.mouseY, text: e.data, col: colEvent)

  # Render all labels on top

  var col = colBg
  col.a = 240
  for l in labels:
    let tt = v.textCache.renderText(" " & l.text & " ", l.col)
    var r = Rect(x: l.x, y: l.y, w: tt.w, h: tt.h)
    v.setColor(col)
    discard v.rend.renderFillRect(r.addr)
    discard v.rend.renderCopy(tt.tex, nil, r.addr)



proc drawStatusbar*(v: View) =

  let
    app = v.app
    c = v.cmdLine
  var text: string

  if c.active:
    text = c.s

  else:

    let
      aps = app.stats
      vws = v.stats

    text =
      "render: " & siFmt(vws.renderTime, "s") & ", " &
      "groups: " & siFmt(aps.groupCount) & ", " &
      "events: " & siFmt(aps.eventCount)

  let h = v.rowSize + 3
  let y = v.h - h
  var r = Rect(x: 0, y: y, w: v.w, h: h)

  var col = colBg
  col.a = 196
  v.setColor(col)
  discard v.rend.renderFillRect(r.addr)
  v.drawText(2, v.h - h, text, colStatusbar)



proc drawGui*(v: View) =

  if not v.showGui:
    return

  v.gui.start(0, 0)
  v.gui.start(PackHor)


  v.gui.stop()
  v.gui.stop()



proc draw*(v: View) =

  if v.ts.v2 == NoTime:
    echo "no time"
    return


  let t1 = cpuTime()

  v.rowSize = v.rowSize.clamp(4, 128)

  v.setColor colBg
  var r = Rect(x: 0, y: 0, w: v.w, h: v.h)
  discard v.rend.renderFillRect(r.addr)

  var rTop = Rect(x:0, y:0, w:v.w, h:v.rowSize + 2)
  var rBot = Rect(x:0, y:v.h - rTop.h, w:v.w, h:v.rowSize + 2)
  var rMain = Rect(x:0, y:rTop.h, w:v.w, h:v.h-rTop.h-rBot.h)
  v.textCache.setFontSize(clamp(v.rowSize, 8, 14))

  discard v.rend.rendersetClipRect(addr rMain)

  v.drawGrid()
  v.drawData()

  discard v.rend.rendersetClipRect(nil)

  v.textCache.setFontSize(clamp(v.rowSize, 8, 14))
  v.drawCursor()
  v.drawGui()
  v.drawStatusbar()

  v.rend.renderPresent

  v.stats.renderTime = cpuTime() - t1


proc zoomX*(v: View, f: float) =
  let tm = v.x2time(v.mouseX)
  v.ts.v1 = tm - (tm - v.ts.v1) * f
  v.ts.v2 = tm + (v.ts.v2 - tm) * f

proc panX*(v: View, dx: int) =
  let dt = (v.ts.v2 - v.ts.v1) / v.w.float * dx.float
  v.ts.v1 = v.ts.v1 + dt
  v.ts.v2 = v.ts.v2 + dt




proc newView*(app: App, w, h: int) =
  let v = View()

  v.app = app

  v.win = createWindow("events",
    WindowPosUndefined, WindowPosUndefined,
    w, h, WINDOW_RESIZABLE)

  v.rend = createRenderer(v.win, -1, sdl.RendererAccelerated and sdl.RendererPresentVsync)
  v.textCache = newTextCache(v.rend, "font.ttf")

  discard v.rend.setRenderDrawBlendMode(BLENDMODE_BLEND)

  v.w = w
  v.h = h
  v.gui = newGui(v.rend, v.textcache)
  v.ts.v1 = getTime().toUnixFloat
  v.ts.v2 = v.ts.v1 + 60.0
  v.rowSize = 12
  v.lineSpacing = 3
  v.isOpen.incl app.root
  v.tMeasure = NoTime
  v.alpha = 0.7
  v.cmdLine = CmdLine()

  app.views[v.win.getWindowId()] = v



# vi: ft=nim sw=2 ts=2
