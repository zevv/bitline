
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
import window
import view_types
import view_grid


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
    rects = newSeqOfCap[Rect](v.w)
    graphRects = newSeqOfCap[Rect](v.w)
    graphPoints = newSeqOfCap[Point](v.w)

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
        graphPoints.add Point(x: x1, y: val2y(vTot / nTot))
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
      if x2 > x2Cur+1:
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

  if graphPoints.len > 0:
    discard v.rend.renderDrawLines(graphPoints[0].addr, graphPoints.len)

  if graphRects.len > 0:
    col.a = 96
    v.setColor(col)
    discard v.rend.renderFillRects(graphRects[0].addr, graphRects.len)


proc genMeasure(v: View, group: Group): string =

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

  if count > 0:
    parts.add "n=" & siFmt(count)
  if time > 0:
    parts.add "t=" & siFmt(time,  "s")
    parts.add "dc=" & &"{dutyCycle:.1f}%"

  if vMin != Value.high:
    parts.add "min=" & siFmt(vMin)
    parts.add "max=" & siFmt(vMax)

  if parts.len > 0:
    result = " " & parts.join(", ") & " "



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
    let label = v.genMeasure(g)
    let x1 = v.time2x(v.tMeasure)
    let x2 = v.mouse_x
    labels.add Label(x: x2+2, y: y, text: label, col: col)

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



proc drawData*(v: View) =

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


# vi: ft=nim sw=2 ts=2
