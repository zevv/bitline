
import chroma except Color
import sdl2/sdl except Event

import textcache

type
  Win* = ref object of RootObj
    win*: sdl.Window
    rend*: sdl.Renderer
    w*, h*: int
    textCache*: TextCache


method sdlEvent*(w: Win, e: sdl.Event) =

  case e.kind:
    of sdl.WindowEvent:
      if e.window.event == sdl.WINDOWEVENT_RESIZED:
        w.w = e.window.data1
        w.h = e.window.data2
    else:
      discard

  return

method tick*(w: Win): bool =
  return

method draw*(w: Win) =
  return


# Drawing primitives

proc setColor*(w: Win, col: sdl.Color) =
  discard w.rend.setRenderDrawColor(col)


proc drawLine*(w: Win, x1, y1, x2, y2: int) =
  if (x1 > 0 or x2 > 0) and (x1 < w.w or x2 < w.w):
    discard w.rend.renderDrawLine(x1, y1, x2, y2)


proc drawFillRect*(w: Win, x1, y1, x2, y2: int) =
  if (x1 > 0 or x2 > 0) and (x1 < w.w or x2 < w.w):
    var r = Rect(x: x1, y: y1, w: x2-x1+1, h: y2-y1+1)
    discard w.rend.renderFillRect(r.addr)


proc drawRect*(w: Win, x1, y1, x2, y2: int) =
  if (x1 > 0 or x2 > 0) and (x1 < w.w or x2 < w.w):
    var r = Rect(x: x1, y: y1, w: x2-x1+1, h: y2-y1+1)
    discard w.rend.renderDrawRect(r.addr)


proc drawText*(w: Win, x, y: int, text: string, col: sdl.Color, align=AlignLeft) =
  w.textCache.drawText(text, x, y, col, align)


