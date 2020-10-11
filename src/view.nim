
import sdl2/sdl except Event
import sdl2/sdl_ttf as ttf
import sets
import algorithm
import sugar
import strutils
import os
import npeg
import npeg
import strformat
import times except Time
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
  colKey          = sdl.Color(r:255, g:200, b:  0, a:128)
  colKeyOpen      = sdl.Color(r:255, g:200, b:  0, a:255)
  colEventSel     = sdl.Color(r:255, g:255, b:255, a: 30)
  colStatusbar    = sdl.Color(r:255, g:255, b:255, a:128)
  colGraphEvent   = sdl.Color(r:255, g:255, b:  0, a: 64)
  colGraphLine    = sdl.Color(r:255, g:255, b:  0, a:250)

type

  View* = ref object
    ts: TimeSpan
    pixelsPerSecond: float
    tMeasure: Time
    ytop: int
    rowSize: int
    lineSpacing: float
    w, h: int
    mouseX, mouseY: int
    dragX, dragY: int
    dragButton: int
    dragged: int
    gui: Gui
    isOpen: HashSet[Group]
    groupScale: Table[Group, int]
    curGroup: Group
    curEvent: Event
    alpha: float
    stats: ViewStats
    showGui: bool
    win: sdl.Window
    rend: sdl.Renderer
    textCache: TextCache
    cmdLine: CmdLine
  
  CmdLine = ref object
    active: bool
    s: string
    pos: int

  ViewStats = object
    renderTime: float


# Helpers

proc time2x(v: View, t: Time): int =
  result = int((t - v.ts.v1) * v.pixelsPerSecond)

proc x2time(v: View, x: int): Time =
  v.ts.v1 + (x / v.w) * (v.ts.v2 - v.ts.v1)



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

proc drawGrid(v: View) =

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


proc drawCursor(v: View) =
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


proc drawData(v: View, root: Group) =

  v.curGroup = nil
  v.curEvent.ts.v1 = NoTime

  type Label = object
    text: string
    x: int
    y: int
    col: Color

  var labels: seq[Label]

  # Draw events

  proc drawEvents(g: Group, y: int, h: int) =

    var rects = newSeqOfCap[Rect](g.events.len)
    var graphRects = newSeqOfCap[Rect](g.events.len)
    var points: seq[Point]
    var xprev = int.low

    # Binary search for event indices which lie in the current view
    var i1 = g.events.lowerbound(v.ts.v1, (e, t) => cmp(if e.ts.v2 != NoTime: e.ts.v2 else: e.ts.v1, t))
    var i2 = g.events.upperbound(v.ts.v2, (e, t) => cmp(e.ts.v1, t))

    if i1 > 0: dec i1
    if i2 < g.events.len: inc i2

    var vmin = Value.high
    var vMax = Value.low

    proc v2y(v: float): int =
      y + h - int(h.float * (v - g.vs.v1) / (g.vs.v2 - g.vs.v1))

    # Iterate visible events
    for i in i1 ..< i2:

      let e = g.events[i]
      var x1 = v.time2x(e.ts.v1)
      var x2 = if e.ts.v2 == NoTime or e.ts.v2 == e.ts.v1:
          x1 + 1 # Oneshot or incomplete span
        else:
          max(v.time2x(e.ts.v2), x1+1)

      if e.value != NoValue:
        vMin = min(vMin, e.value)
        vMax = max(vMax, e.value)

      # Only draw this event if it gets drawn on a different pixel then the
      # previous event
      if x2 > xprev:

        # Never overlap over previous events
        x1 = max(x1, xprev)

        if e.value != NoValue:
          # Events with a value get graphed
          let y1 = v2y(vMax)
          let y2 = v2y(vMin)
          points.add Point(x: x1, y: (y1+y2) div 2)
          graphRects.add Rect(x: x1, y: y1, w: x2-x1, h: y2-y1)
          vmin = Value.high
          vMax = Value.low
        else:
          # Draw event bar
          rects.add Rect(x: x1, y: y, w: x2-x1, h: h)

        # Incomplete span gets a little arrow
        if e.ts.v2 == NoTime:
          for i in 1..<h /% 2:
            rects.add Rect(x: x1+i, y: y+i, w: 1, h: h-i*2)
        
        # Check for hovering
        if initSpan(y, y+h).contains(v.mouseY) and initSpan(x1, x2).contains(v.mouseX):
          v.curEvent = e

        # Always leave a gap of 1 pixel between event, this makese sure gaps do
        # not go unnoticed, on any zoom level
        xprev = x2 + 1

    
    # Render all event rectangles
    if rects.len > 0:
      var col = colEvent
      col.a = uint8(v.alpha * 255)
      v.setColor(col)
      discard v.rend.renderFillRects(rects[0].addr, rects.len)
    
    # Render graph events and lines
    if graphRects.len > 0:
      v.setColor(colGraphEvent)
      discard v.rend.renderFillRects(graphRects[0].addr, graphRects.len)

    if points.len > 0:
      v.setColor(colGraphLine)
      discard v.rend.renderDrawLines(points[0].addr, points.len)


  # Draw groups

  var y = v.yTop + 20

  proc drawGroup(g: Group, depth: int) =

    let isOpen = g in v.isOpen
    let yGroup = y
    let scale = 1 shl v.groupScale.getOrDefault(g, 0)

    # Draw label and events for this group
    var h = 0
    var c = if isOpen: colKeyOpen else: colKey
    labels.add Label(x: depth*10, y: y, text: g.id, col: c)
    if g.events.len > 0:
      h = v.rowSize * scale
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
            drawEvents(g, y, scale)
            y += scale
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

  drawGroup(root, 0)

  # Draw evdata for current event

  let e = v.curEvent
  if e.ts.v1 != NoTime and v.tMeasure == NoTime:
    if e.value != NoValue:
      labels.add Label(x: v.mouseX + 15, y: v.mouseY, text: e.value.siFmt, col: colEvent)
    elif e.data != "":
      labels.add Label(x: v.mouseX + 15, y: v.mouseY, text: e.data, col: colEvent)

  # Render all labels on top

  var col = colBg
  col.a = 240
  for l in labels:
    let tt = v.textCache.renderText(" " & l.text & " ", l.col)
    var r = Rect(x: l.x, y: l.y, w: tt.w, h: tt.h)
    v.setColor(col)
    col.a = 200
    discard v.rend.renderFillRect(r.addr)
    discard v.rend.renderCopy(tt.tex, nil, r.addr)



proc drawStatusbar(v: View, aps: AppStats) =

  let
    c = v.cmdLine
  var text: string

  if c.active:
    text = c.s

  else:

    let
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



proc drawGui(v: View) =

  if not v.showGui:
    return

  v.gui.start(0, 0)
  v.gui.start(PackHor)


  v.gui.stop()
  v.gui.stop()


proc update(v: View) =
  v.rowSize = v.rowSize.clamp(4, 128)
  v.pixelsPerSecond = v.w.float / (v.ts.v2 - v.ts.v1)



proc newView*(root: Group, w, h: int): View =
  let v = View()

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
  v.isOpen.incl root
  v.tMeasure = NoTime
  v.alpha = 0.7
  v.cmdLine = CmdLine()

  return v


proc closeAll*(v: View) =
  v.isOpen.clear

proc setSpan*(v: View, ts: TimeSpan, force=false) =
  if force or v.ts.v1 == NoTime:
    v.ts = ts

proc zoomX*(v: View, f: float) =
  let tm = v.x2time(v.mouseX)
  v.ts.v1 = tm - (tm - v.ts.v1) * f
  v.ts.v2 = tm + (v.ts.v2 - tm) * f

proc panY*(v: View, dy: int) =
  v.yTop -= dy

proc panX*(v: View, dx: int) =
  let dt = (v.ts.v2 - v.ts.v1) / v.w.float * dx.float
  v.ts.v1 = v.ts.v1 + dt
  v.ts.v2 = v.ts.v2 + dt

proc getWindow*(v: View): Window =
  v.win
 
proc setTMeasure*(v: View, t: Time) =
  v.tMeasure = t

proc draw*(v: View, root: Group, appStats: AppStats) =

  if v.ts.v2 == NoTime:
    echo "no time"
    return

  v.update()

  let t1 = cpuTime()


  v.setColor colBg
  var r = Rect(x: 0, y: 0, w: v.w, h: v.h)
  discard v.rend.renderFillRect(r.addr)

  var rTop = Rect(x:0, y:0, w:v.w, h:v.rowSize + 2)
  var rBot = Rect(x:0, y:v.h - rTop.h, w:v.w, h:v.rowSize + 2)
  var rMain = Rect(x:0, y:rTop.h, w:v.w, h:v.h-rTop.h-rBot.h)
  v.textCache.setFontSize(clamp(v.rowSize, 8, 14))

  discard v.rend.rendersetClipRect(addr rMain)

  v.drawGrid()
  v.drawData(root)

  discard v.rend.rendersetClipRect(nil)

  v.textCache.setFontSize(clamp(v.rowSize, 8, 14))
  v.drawCursor()
  v.drawGui()
  v.drawStatusbar(appStats)

  v.rend.renderPresent

  v.stats.renderTime = cpuTime() - t1


proc sdlEvent*(v: View, e: sdl.Event) =

    if e.kind == sdl.TextInput:
      let
        c = v.cmdLine
      if c.active:
        var i = 0
        while e.text.text[i] != '\0':
          c.s.add $e.text.text[i]
          inc i

    if e.kind == sdl.KeyDown:
      let
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

      when true:

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
        of sdl.K_c:
          v.closeAll()
        of sdl.K_COMMA:
            v.zoomX 1.0/0.9
        of sdl.K_PERIOD:
            v.zoomX 0.9
        of sdl.K_LEFT:
            v.panX -50
        of sdl.K_RIGHT:
            v.panX 50
        #of sdl.K_h:
        #  discard sdl.showSimpleMessageBox(0, "help", helpText, v.getWindow());
        else:
          discard

    if e.kind == sdl.KeyUp:
      let key = e.key.keysym.sym
      case key
      of sdl.K_LSHIFT:
        v.tMeasure = NoTime
      of sdl.K_LALT:
        v.showGui = false
      else:
        discard

    if e.kind == sdl.MouseMotion:
      v.gui.mouseMove e.motion.x, e.motion.y
      v.mouseX = e.motion.x
      v.mouseY = e.motion.y
      let dx = v.dragX - v.mouseX
      let dy = v.dragY - v.mouseY
      v.dragX = e.button.x
      v.dragY = e.button.y

      if not v.gui.isActive():

        if v.dragButton != 0:
          inc v.dragged, abs(dx) + abs(dy)

        if v.dragButton == sdl.BUTTON_Left:
          v.panY dy
          v.panX dx

        if v.dragButton == sdl.BUTTON_RIGHT:
          v.zoomX pow(1.01, dy.float)
          v.panX dx

        if v.dragButton == sdl.BUTTON_MIDDLE:
          v.alpha = (v.alpha * pow(1.01, dy.float)).clamp(0.1, 1.0)


    if e.kind == sdl.MouseButtonDown:
      let b = e.button.button
      v.gui.mouseButton e.button.x, e.button.y, 1
      v.dragButton = b
      v.dragged = 0

      if b == sdl.BUTTON_MIDDLE:
        v.tMeasure = v.x2time(e.button.x)

    if e.kind == sdl.MouseButtonUp:
      let b = e.button.button
      v.gui.mouseButton e.button.x, e.button.y, 0
      v.dragButton = 0

      if v.dragged < 3:

        if b == sdl.BUTTON_Left:
          if v.curGroup != nil:
            if v.curGroup in v.isOpen:
              v.isOpen.excl v.curGroup
            else:
              if v.curGroup.groups.len > 0:
                v.isOpen.incl v.curGroup

        if b == sdl.BUTTON_RIGHT:
          if v.curGroup != nil:
            v.isOpen.incl v.curGroup
            let dt = v.curGroup.ts.v2 - v.curGroup.ts.v1
            v.ts.v1 = v.curGroup.ts.v1 - (dt / 5)
            v.ts.v2 = v.curGroup.ts.v2 + (dt / 20)

      if b == sdl.BUTTON_MIDDLE:
        v.tMeasure = NoTime

    if e.kind == sdl.MouseWheel:
      if v.curGroup != nil:
        let h = v.groupScale.mgetOrPut(v.curGroup, 0)
        inc v.groupScale[v.curGroup], e.wheel.y
        v.groupScale[v.curGroup] = v.groupScale[v.curGroup].clamp(0, 6)

    if e.kind == sdl.WindowEvent:
      if e.window.event == sdl.WINDOWEVENT_RESIZED:
        v.w = e.window.data1
        v.h = e.window.data2


# vi: ft=nim sw=2 ts=2
