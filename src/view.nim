
import sets
import algorithm
import os
import sugar
import strutils
import strformat
import times except Time
import hashes
import tables
import json
import math

import chroma except Color
import sdl2/sdl except Event

import textcache
import usage
import gui
import misc

const
  colBg           = sdl.Color(r:  0, g:  0, b: 16, a:255)
  colGrid         = sdl.Color(r:196, g:196, b:196, a: 96)
  colCursor       = sdl.Color(r:255, g:128, b:128, a:255)
  colMeasure      = sdl.Color(r:255, g:255, b:  0, a: 32)
  colGroupSel     = sdl.Color(r:255, g:255, b:255, a:  8)
  colStatusbar    = sdl.Color(r:255, g:255, b:255, a:128)
  colEvent        = sdl.Color(r:  0, g:255, b:173, a:150)

type

  GraphScale = enum gsLin, gsLog

  GroupView = ref object
    height: int
    graphScale: GraphScale
    isOpen: bool
    bin*: Bin

  ViewConfig = object
    yTop: int
    luma: int
    rowSize: int
    ts: TimeSpan
    groupViews: Table[string, GroupView]
    hideBin: array[10, bool]

  View* = ref object
    cfg: ViewConfig
    cfgPath: string
    rootGroup: Group
    pixelsPerSecond: float
    tMeasure: Time
    w, h: int
    mouseX, mouseY: int
    dragX, dragY: int
    dragButton: int
    dragged: int
    gui: Gui
    curGroup: Group
    curEvent: Event
    stats: ViewStats
    showGui: bool
    win: sdl.Window
    rend: sdl.Renderer
    textCache: TextCache
    cmdLine: CmdLine

  CmdLine = ref object
    active: bool
    s: string

  ViewStats = object
    renderTime: float

  Label = object
    text: string
    x: int
    y: int
    col: Color

# Misc helpers

proc resetConfig(v: View)

proc groupView(v: View, g: Group): GroupView =
  if g != nil:
    result = v.cfg.groupViews.mgetOrPut($g, GroupView(bin: 1))

proc time2x(v: View, t: Time): int =
  result = int((t - v.cfg.ts.lo) * v.pixelsPerSecond)

proc x2time(v: View, x: int): Time =
  v.cfg.ts.lo + (x / v.w) * (v.cfg.ts.hi - v.cfg.ts.lo)

proc binColor(v: View, bin: Bin, depth=0): Color =
  let hue = bin.float / 9.0 * 360 + 180
  let luma = float(v.cfg.luma) # + (100 - v.cfg.luma) / (depth+1)
  let col = chroma.ColorPolarLUV(h: hue, c: 100.0, l: luma).color()
  Color(r: (col.r * 255).uint8, g: (col.g * 255).uint8, b: (col.b * 255).uint8, a: 255.uint8)

proc groupColor(v: View, g: Group): Color =
  let gv = v.groupView(g)
  v.binColor(gv.bin, g.depth)

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
    y1 = v.cfg.rowSize + 2
    y2 = v.h - v.cfg.rowSize * 3 - 5
    y3 = v.h - v.cfg.rowSize * 2 - 5
    y4 = v.h - v.cfg.rowSize * 1 - 4

  v.setColor(colGrid)
  v.drawLine(0, y1, v.w, y1)
  v.drawLine(0, y4, v.w, y4)
  
  if v.tMeasure != NoTime:
    return

  proc aux(tFrom: DateTime, step: Duration, fmts1, fmts2: string) =
    var
      dt = inMilliseconds(step).float / 1000.0
      t = tFrom
      tTo = v.cfg.ts.hi.fromUnixFloat.utc
      dtw = v.w.float * dt / v.cfg.ts.duration
      alpha = uint8 min( 64, dtw)

    var col = colGrid
    col.a = alpha
    v.setColor col

    if dtw > 5 and dtw < v.w.float:
      while t < tTo:
        let x = v.time2x(t.toTime.toUnixFloat)
        if x > -80 and x < v.w:
          v.drawLine(x, y1, x, y4)
          if dtw > 80:
            v.drawText(x+2, y2, t.format(fmts1), col)
          if dtw > 20:
            v.drawText(x+2, y3, t.format(fmts2), col)
        t += step

  let t = v.cfg.ts.lo.fromUnixFloat.utc
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=t.hour, minute=t.minute, second=0, utc()),
      initDuration(milliseconds=1), "hh:mm:ss", "fff")
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=t.hour, minute=t.minute, second=0, utc()),
      initduration(milliseconds=10), "hh:mm:ss", "fff")
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=t.hour, minute=t.minute, second=0, utc()),
      initDuration(milliseconds=100), "hh:mm:ss", "fff")
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=t.hour, minute=t.minute, second=0, utc()),
      initDuration(seconds=1), "HH:mm:ss", "ss")
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=t.hour, minute=0, second=0, utc()),
      initDuration(seconds=10), "HH:mm:ss", "ss")
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=t.hour, minute=0, second=0, utc()),
      initDuration(minutes=1), "HH:mm:ss", "mm")
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=t.hour, minute=0, second=0, utc()),
      initDuration(minutes=10), "HH:mm", "mm")
  aux(initDateTime(year=t.year, month=t.month, monthday=t.monthday, hour=0, minute=0, second=0, utc()),
      initduration(hours=1), "HH:mm", "HH")
  aux(initDateTime(year=t.year, month=t.month, monthday=1, hour=0, minute=0, second=0, utc()),
      initduration(days=1), "ddd dd-MM", "dd")
  aux(initDateTime(year=t.year, month=mJan, monthday=1, hour=0, minute=0, second=0, utc()),
      initDuration(weeks=4), "MMM yyyy", "MMM")
  aux(initDateTime(year=1970, month=mJan, monthday=1, hour=0, minute=0, second=0, utc()),
      initDuration(weeks=52), "yyyy", "MMM")


proc drawCursor(v: View) =
  let
    x = v.mouseX
    t = v.x2time(x)

  v.setColor(colCursor)
  v.drawFillRect(x, v.cfg.rowSize, x, v.h)
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

    # Draw periodicy bars
    for i in -20..20:
      if i != 1:
        var col = colMeasure
        col.a = (255 /% (abs(i)+1)).uint8
        v.setColor(col)
        let dt3 = dt * i.float
        let x2 = v.time2x(v.tMeasure + dt3)
        v.drawLine(x2, 0, x2, v.h)

  v.drawText(x + 2, 0, label, colCursor, AlignCenter)


proc measure(v: View, group: Group): (string, int) =

  let
    tMouse = v.x2time(v.mouse_x)
    ts1 = min(tMouse, v.tMeasure)
    ts2 = max(tMouse, v.tMeasure)

  if ts1 == ts2:
    return

  var count = 0
  var time = 0.0
  var vMin = Value.high
  var vMax = Value.low

  proc aux(g: Group) =
    let gv = v.groupView(g)
    for id, ev in g.events:

      if ts1 < ev.ts.lo and ts2 >= ev.ts.hi:
        inc count
        if ev.value != NoValue:
          vMin = min(vMin, ev.value)
          vMax = max(vMax, ev.value)

      let tsint1 = max(ts1, ev.ts.lo)
      let tsint2 = min(ts2, ev.ts.hi)
      if tsint2 > tsint1:
        time += tsint2 - tsint1

    if not gv.isOpen:
      for id, cg in g.groups:
        aux(cg)

  aux(group)

  var parts: seq[string]

  let dutyCycle = 100.0 * time / (ts2-ts1)

  parts.add "n=" & siFmt(count)
  if time > 0:
    parts.add "t=" & siFmt(time,  "s")
    parts.add "dc=" & &"{dutyCycle:.1f}%"

  if vMin != Value.high:
    parts.add "min=" & siFmt(vMin)
    parts.add "max=" & siFmt(vMax)

  result = (parts.join(", "), dutyCycle.int)



proc drawEvents(v:View, g: Group, y: int, h: int) =

  if y < -h or y > v.h:
    return

  # precalulate stuff for value-to-y calculations

  let
    gv = v.groupView(g)
    lo = g.vs.lo
    hi = g.vs.hi
    ppv = if lo != hi: h.float / (hi - lo) else: 0.0
    logMin = log(max(lo, 1e-3), 10)
    logMax = log(max(hi, 1e-3), 10)
    ppvLog = h.float / (logMax - logMin)

  proc val2y(val: float): int =
    if gv.graphScale == gsLog:
      y + h - int((log(max(val, 1e-3), 10) - logMin) * ppvLog).clamp(0, h)
    else:
      y + h - int((val - lo) * ppv).clamp(0, h)

  # graph state
  var
    rects = newSeqOfCap[Rect](g.events.len)
    graphRects = newSeqOfCap[Rect](g.events.len)
    pointsAvg: seq[Point]
    pointsMin: seq[Point]
    pointsMax: seq[Point]
    prevX = int.low

    vMin = Value.high
    vMax = Value.low
    vTot = 0.Value
    nTot = 0

  # Binary search for event indices which lie in the current view
  var i1 = g.events.lowerbound(v.cfg.ts.lo, (e, t) => cmp(if e.ts.hi != NoTime: e.ts.hi else: e.ts.lo, t))
  var i2 = g.events.upperbound(v.cfg.ts.hi, (e, t) => cmp(e.ts.lo, t))

  if i1 > 0: dec i1
  if i2 < g.events.len: inc i2
  var i = 1
  var x = 0
  var x1 = 0
  var x2 = 0

  while i < i2:

    var nTot = 0.Value
    var vTot = 0.Value
    var e: Event

    while i < i2:
      e = g.events[i]
      vTot += e.value
      nTot += 1
      x1 = v.time2x(e.ts.lo)
      x2 = if e.ts.hi != NoTime: v.time2x(e.ts.hi) else: x1
      if x1 > x or x2 > x:
        break
      inc i

    case e.kind
      of ekOneshot, ekSpan:
        rects.add Rect(x: x1, y: y, w: x2-x1+1, h: h)

      of ekCounter, ekGauge:
        let vAvg = vTot / nTot
        echo nTot
        graphRects.add Rect(x: x1, y: y, w: x2-x1+1, h: h)
        pointsAvg.add Point(x: x1, y: vAvg.val2y)

    x = x2 + 1
    inc i

#  # Iterate visible events
#  for i in i1 ..< i2:
#
#    let e = g.events[i]
#
#    # Calculate x for event start and end time
#    var x1 = v.time2x(e.ts.lo)
#    var x2 = if e.ts.hi == NoTime or e.ts.hi == e.ts.lo:
#        x1 + 1 # Oneshot or incomplete span
#      else:
#        max(v.time2x(e.ts.hi), x1+1)
#
#    # Keep track of min, max and average of events with values
#    if e.kind in { ekCounter, ekGauge }:
#      vMin = min(vMin, e.value)
#      vMax = max(vMax, e.value)
#      vTot += e.value
#      inc nTot
#
#    # Only draw this event if it gets drawn on a different pixel then the
#    # previous event
#    if x2 > prevX:
#
#      # Never overlap over previous events
#      x1 = max(x1, prevX)
#
#      case e.kind
#
#        of ekOneshot, ekSpan:
#          # Draw event bar
#          rects.add Rect(x: x1, y: y, w: x2-x1, h: h)
#
#        of ekCounter, ekGauge:
#          # Events with a value get graphed
#          let vAvg = vTot / nTot.float
#          pointsMin.add Point(x: x1, y: vMin.val2y)
#          pointsAvg.add Point(x: x1, y: vAvg.val2y)
#          pointsMax.add Point(x: x1, y: vMax.val2y)
#          graphRects.add Rect(x: x1, y: y, w: x2-x1, h: h)
#          vMin = Value.high
#          vMax = Value.low
#          (vTot, nTot) = (0.0, 0)
#
#      # Incomplete span gets a little arrow
#      if e.ts.hi == NoTime:
#        for i in 1..<h /% 2:
#          rects.add Rect(x: x1+i, y: y+i, w: 1, h: h-i*2)
#
#      # Check for hovering
#      if initSpan(y, y+h).contains(v.mouseY) and initSpan(x1, x2).contains(v.mouseX):
#        v.curEvent = e
#
#      # Always leave a gap of 1 pixel between event, this makese sure gaps do
#      # not go unnoticed, on any zoom level
#      prevX = x2 + 1
#
  var col = v.groupColor(g)
  v.setColor(col)

  # Render all event rectangles
  if rects.len > 0:
    discard v.rend.renderFillRects(rects[0].addr, rects.len)

  # Render graph events and lines

  if pointsAvg.len > 0:
    #discard v.rend.renderDrawLines(pointsMin[0].addr, pointsMin.len)
    #discard v.rend.renderDrawLines(pointsMax[0].addr, pointsMax.len)
    discard v.rend.renderDrawLines(pointsAvg[0].addr, pointsAvg.len)

  if graphRects.len > 0:
    col.a = 64
    v.setColor(col)
    discard v.rend.renderFillRects(graphRects[0].addr, graphRects.len)



proc drawGroup(v: View, y: int, g: Group, labels: var seq[Label]): int =

  var y = y
  let gv = v.groupView(g)

  if g != v.rootGroup and v.cfg.hideBin[gv.bin]:
    for id, cg in g.groups:
      y = v.drawGroup(y, cg, labels)
    return y

  #if not v.cfg.ts.overlaps(g.ts):
  #  return

  let isOpen = gv.isOpen
  let yGroup = y
  let rowSize = v.cfg.rowSize * pow(1.5, gv.height.float).int

  # Horizontal separator
  v.setColor(colGrid)
  v.drawLine(0, y-1, v.w, y-1)

  # Draw label and events for this group
  var h = 0
  var c = v.groupColor(g)
  var arrow = ""
  if g.groups.len > 0:
    arrow = if isOpen: "▼ " else: "▶ "
  labels.add Label(x: 0, y: y, text: repeat(" ", g.depth) & arrow & g.id & " ", col: c)
  if g.events.len > 0:
    h = rowSize
    v.drawEvents(g, y + 3, h-4)

  # Draw measurements for this group
  if v.tMeasure != NoTime:
    var col = v.groupColor(g)
    let (label, duty) = v.measure(g)
    let x1 = v.time2x(v.tMeasure)
    let x2 = v.mouse_x
    labels.add Label(x: x2+2, y: y, text: label & " ", col: colEvent)
    v.setColor(col)
    v.drawFillRect(x1, y, x1-duty, y+h)
    col = sdl.Color(r: 0, g: 0, b: 0, a:255)
    v.setColor(col)
    v.drawFillRect(x1-duty, y, x1-100, y+h)

  y += h

  # For closed groups, draw a (limited) birds eye overview of all events under this group
  if not isOpen and g.groups.len > 0:
    var n = 0
    proc aux(g: Group) =
      if g.events.len > 0:
        let ts1 = g.events[0].ts.lo
        let ts2 = g.events[^1].ts.hi
        if ts1 < v.cfg.ts.hi and (ts2 == NoTime or ts2 > v.cfg.ts.lo):
          v.drawEvents(g, y, 1)
          inc y, 2
          inc n
      if n < rowSize:
        for id, cg in g.groups:
          aux(cg)
    aux(g)

  y = max(y, yGroup + v.cfg.rowSize) + 3

  if isOpen:
    for id, cg in g.groups:
      y = v.drawGroup(y, cg, labels)

  # Check for mouse hover
  if v.mouseY >= yGroup and v.mouseY < y:
    if v.curGroup == nil:
      v.curGroup = g
    v.setColor(colGroupSel)
    v.drawFillRect(0, yGroup, v.w, y-1)

  return y



proc drawData(v: View) =

  v.curGroup = nil
  v.curEvent.ts.lo = NoTime

  # Recursively draw all groups

  var y = v.cfg.yTop + 20
  var labels: seq[Label]
  discard v.drawGroup(y, v.rootGroup, labels)

  # Draw evdata for current event

  let e = v.curEvent
  if e.ts.lo != NoTime and v.tMeasure == NoTime:
    var text = e.data
    if e.value != NoValue:
      text = text & " (" & e.value.siFmt & ")"
    labels.add Label(x: v.mouseX + 15, y: v.mouseY, text: text, col: colEvent)

  # Render all labels on top

  var col = colBg
  col.a = 240
  for l in labels:
    let tt = v.textCache.renderText(l.text, l.col)
    if tt != nil:
      var r = Rect(x: l.x, y: l.y, w: tt.w, h: tt.h)
      v.setColor(col)
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

  let h = v.cfg.rowSize + 3
  let y = v.h - h
  var r = Rect(x: 0, y: y, w: v.w, h: h)

  var col = colBg
  col.a = 196
  v.setColor(col)
  discard v.rend.renderFillRect(r.addr)
  v.drawText(2, v.h - h, text, colStatusbar)

  for bin in Bin.low .. Bin.high:
    var col = if v.cfg.hideBin[bin]:
      colGrid
    else:
      v.binColor(bin)
    v.drawText(v.w - 128 + bin.int*13, v.h - h, $bin, col)



proc drawGui(v: View) =

  if not v.showGui:
    return

  v.gui.start(0, 0)
  v.gui.start(PackVer)

  #discard v.gui.slider("C", C, 0, 100, true)
  #discard v.gui.slider("L", L, 0, 100, true)

  v.gui.stop()
  v.gui.stop()


proc loadConfig*(v: View, fname: string)
 
proc resetConfig(v: View) =
  v.cfg.ts = initSpan[Time](0.0, 1.0)
  v.cfg.rowSize = 12
  v.cfg.luma = 60
  v.cfg.groupViews.clear()
  v.cfg.hideBin.reset()
  v.groupView(v.rootGroup).isOpen = true

proc newView*(rootGroup: Group, w, h: int, cfgPath: string): View =
  let v = View(
    rootGroup: rootGroup,
    w: w,
    h: h,
    cfgPath: cfgPath,
  )

  v.win = createWindow("events",
    WindowPosUndefined, WindowPosUndefined,
    w, h, WINDOW_RESIZABLE)

  v.rend = createRenderer(v.win, -1, sdl.RendererAccelerated and sdl.RendererPresentVsync)
  v.textCache = newTextCache(v.rend, "font.ttf")

  discard v.rend.setRenderDrawBlendMode(BLENDMODE_BLEND)

  v.gui = newGui(v.rend, v.textcache)
  v.resetConfig()

  v.tMeasure = NoTime
  v.cmdLine = CmdLine()
  
  v.loadConfig(v.cfgPath)
  
  return v


proc closeAll*(v: View) =
  for _, gv in v.cfg.groupViews:
    gv.isOpen = false

proc openAll*(v: View) =
  proc aux(g: Group) =
    v.groupView(g).isOpen = true
    for id, cg in g.groups:
      aux(cg)
  aux(v.rootGroup)

proc zoomX*(v: View, f: float) =
  let tm = v.x2time(v.mouseX)
  v.cfg.ts.lo = tm - (tm - v.cfg.ts.lo) * f
  v.cfg.ts.hi = tm + (v.cfg.ts.hi - tm) * f

proc zoomAll*(v: View) =
  v.cfg.yTop = 0
  if v.rootGroup.ts.lo != NoTime and v.rootGroup.ts.hi != NoTime:
    v.cfg.ts = v.rootGroup.ts

proc panY*(v: View, dy: int) =
  v.cfg.yTop -= dy

proc panX*(v: View, dx: int) =
  let dt = (v.cfg.ts.hi - v.cfg.ts.lo) / v.w.float * dx.float
  v.cfg.ts.lo = v.cfg.ts.lo + dt
  v.cfg.ts.hi = v.cfg.ts.hi + dt

proc getWindow*(v: View): Window =
  v.win
 
proc setTMeasure*(v: View, t: Time) =
  v.tMeasure = t

proc draw*(v: View, appStats: AppStats) =

  if v.cfg.ts.lo == 0.0 and v.cfg.ts.hi == 1.0 and v.rootGroup.ts.hi != NoTime:
    v.cfg.ts = v.rootGroup.ts

  v.cfg.rowSize = v.cfg.rowSize.clamp(4, 128)
  v.pixelsPerSecond = v.w.float / (v.cfg.ts.hi - v.cfg.ts.lo)

  let t1 = cpuTime()

  v.setColor colBg
  var r = Rect(x: 0, y: 0, w: v.w, h: v.h)
  discard v.rend.renderFillRect(r.addr)

  var rTop = Rect(x:0, y:0, w:v.w, h:v.cfg.rowSize + 2)
  var rBot = Rect(x:0, y:v.h - rTop.h, w:v.w, h:v.cfg.rowSize + 2)
  var rMain = Rect(x:0, y:rTop.h, w:v.w, h:v.h-rTop.h-rBot.h)
  v.textCache.setFontSize(v.cfg.rowSize)

  discard v.rend.rendersetClipRect(addr rMain)

  v.drawGrid()
  v.drawData()

  discard v.rend.rendersetClipRect(nil)

  v.drawCursor()
  v.drawGui()
  v.drawStatusbar(appStats)

  v.rend.renderPresent

  v.stats.renderTime = cpuTime() - t1


proc saveConfig*(v: View, fname: string) =
  let js = pretty(%v.cfg)
  writeFile(fname.expandTilde, js)


proc loadConfig*(v: View, fname: string) = 
  try:
    let js = readFile(fname.expandTilde)
    v.cfg = to(parseJson(js), ViewConfig)
  except:
    v.resetConfig()


proc handleCmd(v: View, s: string) =
  if s[0] == '/':
    let search = s[1..^1]
    proc aux(g: Group): bool =
      result = g.id.toLowerAscii.find(search.toLowerAscii) != -1
      for id, gc in g.groups:
        if aux(gc):
          result = true
      if result:
        v.groupView(g).isOpen = true
    discard aux(v.rootGroup)


proc setBin(v:View, g: Group, bin: Bin) =
  proc aux(g: Group) =
    let gv = v.groupView(g)
    gv.bin = bin
    for _, cg in g.groups:
      aux(cg)
  aux(g)


proc toggleBin(v:View, bin: Bin) =
  v.cfg.hideBin[bin] = not v.cfg.hideBin[bin]


proc sdlEvent*(v: View, e: sdl.Event) =

  case e.kind

    of sdl.TextInput:
      let
        c = v.cmdLine
      if c.active:
        var i = 0
        while e.text.text[i] != '\0':
          c.s.add $e.text.text[i]
          inc i

    of sdl.KeyDown:
      let
        key = e.key.keysym.sym
        c = v.cmdLine

      if c.active:
        case key
        of sdl.K_RETURN:
          c.active = false
          v.handleCmd(c.s)
          c.s=""
        of sdl.K_ESCAPE:
          c.active = false
        of sdl.K_BACKSPACE:
          if c.s.len > 0:
            c.s = c.s[0..^2]
        else:
          discard

      else:

        case key
        of sdl.K_Q:
          quit(0)
        of sdl.K_SEMICOLON, sdl.K_SLASH:
          c.active = true
        of sdl.K_EQUALS:
          inc v.cfg.rowSize
        of sdl.K_MINUS:
          dec v.cfg.rowSize
        of sdl.K_0:
          v.cfg.rowSize = 12
        of sdl.K_LSHIFT:
          v.tMeasure = v.x2time(v.mouseX)
        of sdl.K_r:
          v.resetConfig()
        of sdl.K_s:
          v.saveConfig(v.cfgPath)
        of sdl.K_a:
          v.zoomAll()
        of sdl.K_c:
          v.closeAll()
        of sdl.K_o:
          v.openAll()
        of sdl.K_1..sdl.K_9:
          let bin = key.int - sdl.K_1.int + 1
          if (getModState().int32 and (KMOD_LSHIFT.int32 or KMOD_RSHIFT.int32)) != 0:
            v.toggleBin(bin)
          else:
            if v.curGroup != nil:
              v.setBin(v.curGroup, bin)
        of sdl.K_COMMA:
          v.zoomX 1.0/0.9
        of sdl.K_PERIOD:
          v.zoomX 0.9
        of sdl.K_LEFT:
          v.panX -50
        of sdl.K_RIGHT:
          v.panX +50
        of sdl.K_UP:
          v.cfg.yTop += 50
        of sdl.K_DOWN:
          v.cfg.yTop -= 50
        of sdl.K_h:
          discard sdl.showSimpleMessageBox(0, "help", usage(), v.getWindow());
        of sdl.K_RIGHTBRACKET:
          v.cfg.luma = min(v.cfg.luma+10, 100)
        of sdl.K_LEFTBRACKET:
          v.cfg.luma = max(v.cfg.luma-10, 20)
        of sdl.K_l:
          if v.curGroup != nil:
            let gv = v.groupView(v.curGroup)
            gv.graphScale = if gv.graphScale == gsLin: gsLog else: gsLin
        else:
          discard

    of sdl.KeyUp:
      let key = e.key.keysym.sym
      case key
      of sdl.K_LSHIFT:
        v.tMeasure = NoTime
      else:
        discard

    of sdl.MouseMotion:
      if v.gui.mouseMove(e.motion.x, e.motion.y):
        return

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

    of sdl.MouseButtonDown:
      let b = e.button.button
      if v.gui.mouseButton(e.button.x, e.button.y, 1):
        return

      v.dragButton = b
      v.dragged = 0

      if b == sdl.BUTTON_MIDDLE:
        v.tMeasure = v.x2time(e.button.x)

    of sdl.MouseButtonUp:
      let b = e.button.button
      if v.gui.mouseButton(e.button.x, e.button.y, 0):
        return

      v.dragButton = 0

      if v.dragged < 3:

        if b == sdl.BUTTON_Left:
          if v.curGroup != nil:
            if v.groupView(v.curGroup).isOpen:
              v.groupView(v.curGroup).isOpen = false
            else:
              if v.curGroup.groups.len > 0:
                echo "opened"
                v.groupView(v.curGroup).isOpen = true

        if b == sdl.BUTTON_RIGHT:
          if v.curGroup != nil:
            v.groupView(v.curGroup).isOpen = true
            let dt = v.curGroup.ts.hi - v.curGroup.ts.lo
            v.cfg.ts.lo = v.curGroup.ts.lo - (dt / 5)
            v.cfg.ts.hi = v.curGroup.ts.hi + (dt / 20)

      if b == sdl.BUTTON_MIDDLE:
        v.tMeasure = NoTime

    of sdl.MouseWheel:
      if v.curGroup != nil:
        let gv = v.groupView(v.curGroup)
        gv.height = (gv.height + e.wheel.y).clamp(0, 10)

    of sdl.WindowEvent:
      if e.window.event == sdl.WINDOWEVENT_RESIZED:
        v.w = e.window.data1
        v.h = e.window.data2

    of sdl.MultiGesture:
      let z = pow(1.02, -v.w.float * e.mgesture.dDist)
      v.zoomx z

    else:
      discard


# vi: ft=nim sw=2 ts=2
