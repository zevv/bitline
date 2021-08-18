
import chroma except Color
import sdl2/sdl except Event

import misc
import window
import textcache


type
  Histogram* = ref object or Win


proc newHistogram*(): Histogram =
  var h = Histogram()
  h.win = createWindow("histogram",
    WindowPosUndefined, WindowPosUndefined,
    640, 480, WINDOW_RESIZABLE)
  h.rend = createRenderer(h.win, -1, sdl.RendererAccelerated and sdl.RendererPresentVsync)
  h.textCache = newTextCache(h.rend, "font.ttf")
  discard h.rend.setRenderDrawBlendMode(BLENDMODE_BLEND)
  return h


