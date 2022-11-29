
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
  colBg*           = sdl.Color(r:  0, g:  0, b: 16, a:255)
  colGrid*         = sdl.Color(r:128, g:128, b:128, a: 96)
  colTicks*        = sdl.Color(r:196, g:196, b:196, a:196)
  colCursor*       = sdl.Color(r:255, g:128, b:128, a:255)
  colMeasure*      = sdl.Color(r:  0, g:255, b:255, a: 32)
  colGroupSel*     = sdl.Color(r:255, g:255, b:255, a:  8)
  colStatusbar*    = sdl.Color(r:255, g:255, b:255, a:128)
  colEvent*        = sdl.Color(r:  0, g:255, b:173, a:150)

type

  GraphScale* = enum gsLin, gsLog

  GroupView* = ref object
    height*: int
    graphScale*: GraphScale
    isOpen*: bool
    bin*: Bin

  ViewConfig* = object
    yTop*: int
    luma*: int
    rowSize*: int
    ts*: TimeSpan
    groupViews*: Table[string, GroupView]
    hideBin*: array[10, bool]
    follow*: bool
    utc*: bool
    showGui*: bool

  View* = ref object
    cfg*: ViewConfig
    cfgPath*: string
    rootGroup*: Group
    pixelsPerSecond*: float
    tMeasure*: Time
    w*, h*: int
    mouseX*, mouseY*: int
    dragX*, dragY*: int
    dragButton*: int
    dragged*: int
    gui*: Gui
    curGroup*: Group
    curEvent*: Event
    stats*: ViewStats
    win*: sdl.Window
    rend*: sdl.Renderer
    textCache*: TextCache
    cmdLine*: CmdLine
    tNow*: uint32
    tz*: TimeZone

  CmdLine* = ref object
    active*: bool
    s*: string

  ViewStats* = object
    renderTime*: float

  Label* = object
    text*: string
    x*: int
    y*: int
    col*: Color

# Drawing primitives

proc setColor*(v: View, col: sdl.Color) =
  discard v.rend.setRenderDrawColor(col)


proc drawLine*(v: View, x1, y1, x2, y2: int) =
  if (x1 > 0 or x2 > 0) and (x1 < v.w or x2 < v.w):
    discard v.rend.renderDrawLine(x1, y1, x2, y2)


proc drawFillRect*(v: View, x1, y1, x2, y2: int) =
  if (x1 > 0 or x2 > 0) and (x1 < v.w or x2 < v.w):
    var r = Rect(x: x1, y: y1, w: x2-x1+1, h: y2-y1+1)
    discard v.rend.renderFillRect(r.addr)


proc drawRect*(v: View, x1, y1, x2, y2: int) =
  if (x1 > 0 or x2 > 0) and (x1 < v.w or x2 < v.w):
    var r = Rect(x: x1, y: y1, w: x2-x1+1, h: y2-y1+1)
    discard v.rend.renderDrawRect(r.addr)


proc drawText*(v: View, x, y: int, text: string, col: sdl.Color, align=AlignLeft) =
  v.textCache.drawText(text, x, y, col, align)


proc groupView*(v: View, g: Group): GroupView =
  if g != nil:
    result = v.cfg.groupViews.mgetOrPut($g, GroupView(bin: 1))


proc time2x*(v: View, t: Time): int =
  result = int((t - v.cfg.ts.lo) * v.pixelsPerSecond)


proc ts2x*(v: View, ts: TimeSpan): (int, int) =
  let x1 = v.time2x(ts.lo)
  let x2 = if ts.hi != NoTime: v.time2x(ts.hi) else: x1
  (x1, x2)


proc x2time*(v: View, x: int): Time =
  v.cfg.ts.lo + (x / v.w) * (v.cfg.ts.hi - v.cfg.ts.lo)


proc binColor*(v: View, bin: Bin, depth=0): Color =
  let hue = bin.float / 9.0 * 360 + 170
  let luma = float(v.cfg.luma) # + (100 - v.cfg.luma) / (depth+1)
  let col = chroma.ColorPolarLUV(h: hue, c: 150.0, l: luma).color()
  Color(r: (col.r * 255).uint8, g: (col.g * 255).uint8, b: (col.b * 255).uint8, a: 255.uint8)


proc groupColor*(v: View, g: Group): Color =
  let gv = v.groupView(g)
  v.binColor(gv.bin, g.depth)

proc toggle*(v: var bool) =
  v = not v

# vi: ft=nim sw=2 ts=2
