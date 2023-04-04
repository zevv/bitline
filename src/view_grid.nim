
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


# Draw UI components

proc drawGrid*(v: View) =

  let
    y1 = v.cfg.rowSize + 2
    y2 = v.h - v.cfg.rowSize * 2 - 7
    y4 = v.h - v.cfg.rowSize * 1 - 4

  v.setColor(colGrid)
  v.drawLine(0, y1, v.w, y1)
  v.drawLine(0, y4, v.w, y4)

  let dt = v.cfg.ts.hi - v.cfg.ts.lo
  let tpp = dt / v.w.Time
  let tFrom = v.cfg.ts.lo.fromUnixFloat.inZone(v.tz)
  let tTo = v.cfg.ts.hi.fromUnixFloat.inZone(v.tz)
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
        let t = initDateTime(mday.MonthDayRange, month.Month, year, hour, min, sec, nsec, v.tz)
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

  var t = v.cfg.ts.lo.fromUnixFloat.inZone(v.tz)
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


# vi: ft=nim sw=2 ts=2
