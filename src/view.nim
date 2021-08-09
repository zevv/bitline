
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
  colGrid         = sdl.Color(r:128, g:128, b:128, a: 96)
  colTicks        = sdl.Color(r:196, g:196, b:196, a:196)
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

proc ts2x(v: View, ts: TimeSpan): (int, int) =
  let x1 = v.time2x(ts.lo)
  let x2 = if ts.hi != NoTime: v.time2x(ts.hi) else: x1
  (x1, x2)

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
    y2 = v.h - v.cfg.rowSize * 2 - 7
    y4 = v.h - v.cfg.rowSize * 1 - 4

  v.setColor(colGrid)
  v.drawLine(0, y1, v.w, y1)
  v.drawLine(0, y4, v.w, y4)

  if v.tMeasure != NoTime:
    return

  let dt = v.cfg.ts.hi - v.cfg.ts.lo
  let tpp = dt / v.w.Time
  let tFrom = v.cfg.ts.lo.fromUnixFloat.utc
  let tTo = v.cfg.ts.hi.fromUnixFloat.utc
  var dy = 0

  template aux(interval: Time,
               iyear: int, imonth: Month, imday: MonthdayRange,
               ihour, imin, isec: int,
               fmt1, fmt2: string,
               code: untyped) {.dirty.} =

    if tpp * 10 < interval:
      var (year, month, mday)= (iyear.int, imonth.int, imday.int)
      var (hour, min, sec, nsec) = (ihour.int, imin.int, isec.int, 0)
      var nLabels = 0
      while true:
        let t = initDateTime(mday.MonthDayRange, month.Month, year, hour, min, sec, nsec, utc())
        if t > tTo:
          break
        if t > tFrom:
          let
            dx = v.w.float * interval / dt
            x = v.time2x(t.toTime.toUnixFloat)

          var col = colTicks
          col.a = dx.clamp(0, 255).uint8
          
          v.setColor col
          v.drawLine(x, y1, x, y4)
          var l: string

          if dx > 100:
            l = t.format(fmt2)
          elif dx > 30:
            l = t.format(fmt1)
          if l != "":
            v.drawText(x+2, y2 - dy, l, col)
            inc nLabels

        code

        if nsec >= 1000000000: (inc sec; nsec = 0)
        if sec >= 60: (inc min; sec = 0)
        if min >= 60: (inc hour; min = 0)
        if hour >= 24: (hour = 0; inc mday)
        if month < 13 and mday > getDaysInMonth(month.Month, year): (mday = 1; inc month)
        if month > 12: (month = 1; inc year)

      if nLabels > 0:
        dy += v.cfg.rowSize

  var t = v.cfg.ts.lo.fromUnixFloat.utc
  aux(0.001,        t.year, t.month, t.monthday, t.hour, t.minute, t.second, "fff", "s'.'fff"): inc nsec,   1 * 1000 * 1000
  aux(0.01,         t.year, t.month, t.monthday, t.hour, t.minute, t.second, "fff", "s'.'fff"): inc nsec,  10 * 1000 * 1000
  aux(0.1,          t.year, t.month, t.monthday, t.hour, t.minute, t.second, "fff", "s'.'fff"): inc nsec, 100 * 1000 * 1000
  aux(1,            t.year, t.month, t.monthday, t.hour, t.minute, t.second, "ss", "HH:mm:ss"): inc sec
  aux(10,           t.year, t.month, t.monthday, t.hour, t.minute, 0,        "ss", "HH:mm:ss"): inc sec, 10
  aux(60,           t.year, t.month, t.monthday, t.hour, t.minute, 0,        "mm", "HH:mm:ss"): inc min
  aux(60*10,        t.year, t.month, t.monthday, t.hour, 0,        0,        "mm", "HH:mm"): inc min, 10
  aux(60*60,        t.year, t.month, t.monthday, t.hour, 0,        0,        "HH", "HH:mm"): inc hour
  aux(60*60*6,      t.year, t.month, t.monthday, 0,      0,        0,        "HH", "HH:mm"): inc hour, 6
  aux(60*60*24,     t.year, t.month, t.monthday, 0,      0,        0,        "dd", "MMM dd"): inc mday
  aux(60*60*24*30,  t.year, t.month, 1,          0,      0,        0,        "MMM", "MMM '`'yy"): inc month
  aux(60*60*24*365, t.year, mJan,    1,          0,      0,        0,        "yy", "yyyy"): inc year

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

  # Binary search for event indices which lie in the current view
  var i1 = g.events.lowerbound(v.cfg.ts.lo, (e, t) => cmp(if e.ts.hi != NoTime: e.ts.hi else: e.ts.lo, t))
  var i2 = g.events.upperbound(v.cfg.ts.hi, (e, t) => cmp(e.ts.lo, t))

  if i1 > 0: dec i1
  if i2 < g.events.len: inc i2

  var
    kind = g.events[i1].kind
    i = i1
    x1Next, x2Next: int
    valueNext: Value
    x1Cur = int.low
    x2Cur = int.low
    vTot, vMin, vMax, nTot: Value

  proc emit() =
    var x1 = x1Cur.clamp(-1, v.w)
    var x2 = x2Cur.clamp(-1, v.w)
    case kind
      of ekOneshot:
        rects.add Rect(x: x1, y: y, w: 1, h: h)
      of ekSpan:
        rects.add Rect(x: x1, y: y, w: x2-x1+1, h: h)
      of ekCounter, ekGauge:
        graphRects.add Rect(x: x1, y: y, w: x2-x1+1, h: h)
        pointsAvg.add Point(x: x1, y: val2y(vTot / nTot))
        if nTot > 1:
          let yMin = vMin.val2Y
          let yMax = vMax.val2Y
          graphRects.add Rect(x: x1, y: yMax, w: x2-x1+1, h: yMin-yMax)

  while i < i2:

    # Collect all events on the current x position
    while i < i2:
      let e = g.events[i]
      inc i
      let (x1, x2) = v.ts2x(e.ts)
      let value = e.value
      if x1 > x2Cur+1 or x2 > x2Cur+1:
        (x1Next, x2Next, valueNext) = (x1, x2, value)
        break
      vTot += value
      vMin = min(vMin, value)
      vMax = max(vMax, value)
      nTot += 1

    if x1Cur != int.low:
      emit()

    x1Cur = x1Next
    x2Cur = x2Next
    vTot = valueNext
    vMin = valueNext
    vMAx = valueNext
    nTot = 1

  emit()


  var col = v.groupColor(g)
  v.setColor(col)

  if rects.len > 0:
    discard v.rend.renderFillRects(rects[0].addr, rects.len)

  if pointsAvg.len > 0:
    discard v.rend.renderDrawLines(pointsAvg[0].addr, pointsAvg.len)

  if graphRects.len > 0:
    col.a = 96
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
          v.zoomX 1.0/0.8
        of sdl.K_PERIOD:
          v.zoomX 0.8
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
