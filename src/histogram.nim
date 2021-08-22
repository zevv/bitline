
import misc
import view_types
import math
import sdl2/sdl except Event

proc getVal(e: Event): Value =
  case e.kind
    of ekCounter, ekGauge:
      e.value
    of ekSpan:
      e.duration
    else:
      0


proc drawHistogram*(v: View, g: Group, w, h: int) =

  echo w, " ", h
  
  var vTot, nTot: Value
  for e in g.events:
    if v.cfg.ts.contains(e.time):
      vTot += e.getVal()
      nTot += 1

  if nTot == 0:
    return

  let vAvg = vTot / nTot
  var stdDev = 0.Value
  for e in g.events:
    if v.cfg.ts.contains(e.time):
      let d = e.getVal()
      stdDev += d * d
  stdDev = sqrt(stdDev / nTot)

  let bins = w /% 4
  var accum = newSeqOfCap[Value](bins)
  var accumMax = 0.Value

  for e in g.events:
    if v.cfg.ts.contains(e.time):
      let t = (e.getVal() - vAvg) / stdDev
      var bin = int(bins.Value * (0.5 + (e.getVal() - vAvg) / (stdDev * 2.0)))
      bin = bin.clamp(0, bins-1)
      if bin >= 0 and bin <= bins-1:
        accum[bin] += 1.0
        accumMax = max(accum[bin], accumMax)
  
  v.setColor sdl.Color(a: 128)
  v.drawFillRect(0, 0, w-1, h)
  
  v.setColor v.groupColor(g)
  v.drawRect(0, 0, w-1, h)

  for i in 0..<bins:
    let x1 = (w * (i+0) / bins).int
    let x2 = (w * (i+1) / bins).int - 2
    let y1 = h - 1 - (h.float * accum[i] / accumMax).int
    let y2 = h.int
    v.setColor sdl.Color(a: 255)
    v.drawFillRect(x1-1, y1-1, x2+1, y2+1)
    v.setColor v.groupColor(g)
    v.drawFillRect(x1, y1, x2, y2)

