
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
import view_types
import view_api
import view_grid
import view_data
import view_control
import histogram


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
      "events: " & siFmt(aps.eventCount) & " (" &
      (if v.cfg.utc: "utc" else: "local") &
      (if v.cfg.follow: ", follow" else: "") &
      ")"

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

  if not v.cfg.showGui:
    return

  v.gui.start(20, v.cfg.rowSize*2)
  v.gui.start(PackHor)

  v.gui.label("Time settings:")
  discard v.gui.button("follow", v.cfg.follow)
  discard v.gui.button("UTC", v.cfg.utc)

  v.gui.stop()
  v.gui.stop()


proc loadConfig*(v: View, fname: string)



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

  v.tMeasure = NoTime
  v.cmdLine = CmdLine()
  
  v.loadConfig(v.cfgPath)
  
  return v




proc draw*(v: View, appStats: AppStats) =

  if v.cfg.ts.lo == 0.0 and v.cfg.ts.hi == 1.0 and v.rootGroup.ts.hi != NoTime:
    v.cfg.ts = v.rootGroup.ts

  v.cfg.rowSize = v.cfg.rowSize.clamp(4, 128)
  v.pixelsPerSecond = v.w.float / (v.cfg.ts.hi - v.cfg.ts.lo)
  v.tz = if v.cfg.utc: utc() else: local()

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

  if v.curGroup != nil:
    v.drawHistogram(v.curGroup)

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



proc tick*(v: View): bool =
  let tNow = sdl.getTicks()
  if v.cfg.follow:
    result = true
    sleep 10
    if v.tNow != 0:
      let dt = (tNow - v.tNow).float / 1000.0
      v.cfg.ts.lo += dt
      v.cfg.ts.hi += dt
  v.tNow = tNow

# vi: ft=nim sw=2 ts=2
