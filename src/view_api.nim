
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
import sdl2_nim/sdl except Event

import textcache
import usage
import gui
import misc
import view_types
import view_grid
import view_data


proc resetConfig*(v: View) =
  v.cfg.ts = initSpan[Time](0.0, 1.0)
  v.cfg.rowSize = 12
  v.cfg.luma = 60
  v.cfg.groupViews.clear()
  v.cfg.hideBin.reset()
  v.cfg.utc = false
  v.groupView(v.rootGroup).isOpen = true


proc saveConfig*(v: View, fname: string) =
  let js = pretty(%v.cfg)
  writeFile(fname.expandTilde, js)


proc loadConfig*(v: View, fname: string) = 
  try:
    let js = readFile(fname.expandTilde)
    v.cfg = to(parseJson(js), ViewConfig)
  except:
    v.resetConfig()


proc handleCmd*(v: View, s: string) =
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


proc setBin*(v:View, g: Group, bin: Bin) =
  proc aux(g: Group) =
    let gv = v.groupView(g)
    gv.bin = bin
    for _, cg in g.groups:
      aux(cg)
  aux(g)


proc toggleBin*(v:View, bin: Bin) =
  toggle v.cfg.hideBin[bin]


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


# vi: ft=nim sw=2 ts=2
