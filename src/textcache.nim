
import sdl2_nim/sdl
import sdl2_nim/sdl_ttf
import tables
    
type

  Stats = object
    hits: int
    misses: int
    gcs: int

  TextAlign* = enum
    AlignLeft, AlignCenter, AlignRight

  TextTex* = ref object
    tex*: Texture
    w*, h*: int
    age: int
  
  TextCache* = ref object
    fonts: Table[int, Font]
    cache: Table[string, TextTex]
    rend: Renderer
    ticks: int
    fontSize: int
    stats: Stats

const ttfConst = readFile("res/font.ttf")
let ttf = ttfConst


proc getFont(tc: TextCache, size: int): Font =
  if size notin tc.fonts:
    let rw = rwFromConstMem(ttf[0].unsafeAddr, ttf.len)
    let font = openFontRW(rw, 0, size)
    setFontHinting(font, HINTING_MONO);
    tc.fonts[size] = font
  tc.fonts[size]


proc newTextCache*(rend: Renderer, fontname: string): TextCache =
  TextCache(rend: rend)

proc pruneCache(tc: TextCache) =
  tc.ticks = tc.ticks + 1
  if tc.ticks > 128:
    tc.ticks = 0
    var remove: seq[string]
    for s, tex in pairs(tc.cache):
      inc(tex.age)
      if tex.age > 100:
        remove.add s
    for s in remove:
      destroyTexture(tc.cache[s].tex)
      tc.cache.del(s)
      inc tc.stats.gcs

    #echo tc.stats

proc setFontSize*(tc: TextCache, size: int) =
  tc.fontSize = size

proc renderText*(tc: TextCache, text: string, color: Color): TextTex =
  if len(text) > 0:
    let key = text & "." & $color.r.int & "." & $color.g.int & "." & $color.b.int & "." & $color.a.int & "." & $tc.fontSize
    if key in tc.cache:
      result = tc.cache[key]
      inc tc.stats.hits
    else:
      let font = tc.getFont(tc.fontSize)
      let s = font.renderUTF8_Blended(text, color)
      let tex = tc.rend.createTextureFromSurface(s)
      result = TextTex(tex: tex, w: s.w, h: s.h)
      freeSurface(s)
      tc.cache[key] = result
      inc tc.stats.misses
  if result != nil:
    result.age = 0
  tc.pruneCache()

proc drawText*(tc: TextCache, text: string, x, y: int, color: Color, align=AlignLeft) =
  let tt = tc.renderText(text, color)
  if tt != nil:
    var rect = sdl.Rect(x: x, y: y, w: tt.w, h: tt.h)
    if align == AlignCenter:
      rect.x -= rect.w /% 2
    if align == AlignRight:
      rect.x -= rect.w
    discard tc.rend.renderCopy(tt.tex, nil, addr(rect))


discard sdl_ttf.init()

# vi: ft=nim et ts=2 sw=2

