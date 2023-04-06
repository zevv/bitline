
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
import view_api



proc sdlEvent*(v: View, e: sdl.Event) =
        
  let modShift = (getModState().int32 and (KMOD_LSHIFT.int32 or KMOD_RSHIFT.int32)) != 0

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
        of sdl.K_0:
          v.cfg.rowSize = 12
        of sdl.K_1..sdl.K_9:
          let bin = key.int - sdl.K_1.int + 1
          if modShift:
            v.toggleBin(bin)
          else:
            if v.curGroup != nil:
              v.setBin(v.curGroup, bin)
        of sdl.K_a:
          v.zoomAll()
        of sdl.K_c:
          v.closeAll()
        of sdl.K_f:
          toggle v.cfg.follow
        of sdl.K_g:
          toggle v.cfg.showGui
        of sdl.K_h:
          discard sdl.showSimpleMessageBox(0, "help", usage(), v.getWindow());
        of sdl.K_o:
          v.openAll()
        of sdl.K_r:
          v.resetConfig()
        of sdl.K_s:
          v.saveConfig(v.cfgPath)
        of sdl.K_t:
          toggle v.cfg.utc
        of sdl.K_q:
          quit(0)
        of sdl.K_SEMICOLON, sdl.K_SLASH:
          c.active = true
        of sdl.K_EQUALS:
          inc v.cfg.rowSize
        of sdl.K_MINUS:
          dec v.cfg.rowSize
        of sdl.K_LSHIFT:
          v.tMeasure = v.x2time(v.mouseX)
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
        of sdl.K_PAGE_UP:
          v.cfg.yTop += v.h /% 2
        of sdl.K_PAGE_DOWN:
          v.cfg.yTop -= v.h /% 2
        of sdl.K_RIGHTBRACKET:
          if v.curGroup != nil:
            let gv = v.groupView(v.curGroup)
            gv.height = (gv.height + 1).clamp(0, 10)
        of sdl.K_LEFTBRACKET:
          if v.curGroup != nil:
            let gv = v.groupView(v.curGroup)
            gv.height = (gv.height - 1).clamp(0, 10)
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

      if v.dragButton != 0:
        inc v.dragged, abs(dx) + abs(dy)

      if v.dragButton == sdl.BUTTON_Left:
        v.panY dy
        v.panX dx

      if v.dragButton == sdl.BUTTON_RIGHT:
        v.zoomX pow(1.01, dy.float)
        v.panX dx

    of sdl.MouseButtonDown:
      if v.gui.mouseButton(e.button.x, e.button.y, 1):
        return

      let b = e.button.button
      v.dragButton = b
      v.dragged = 0

      if b == sdl.BUTTON_MIDDLE:
        v.tMeasure = v.x2time(e.button.x)

    of sdl.MouseButtonUp:
      if v.gui.mouseButton(e.button.x, e.button.y, 0):
        return

      let b = e.button.button
      v.dragButton = 0

      if v.dragged < 3:

        if b == sdl.BUTTON_Left:
          if v.curGroup != nil:
            if v.groupView(v.curGroup).isOpen:
              v.groupView(v.curGroup).isOpen = false
            else:
              if v.curGroup.groups.len > 0:
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
      if modShift:
        if v.curGroup != nil:
          let gv = v.groupView(v.curGroup)
          gv.height = (gv.height + e.wheel.y).clamp(0, 10)
      else:
        v.cfg.yTop += e.wheel.y * 50

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
