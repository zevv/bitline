[![License: GPLv2](https://img.shields.io/badge/License-GPLv2-blue.svg)](https://opensource.org/licenses/GPL-2.0)
![Stability: experimental](https://img.shields.io/badge/stability-experimental-yellow.svg)

Bitline is a high performance tool for visualizing and inspecting time-based data.


![BitLine](/res/bitline.png)


## Building

Bitline is written in [Nim](https://nim-lang.org/) and uses SDL2 and SDL2-ttf.

```
nimble install sdl2_nim chroma
make
```

## Usage

```
usage: bitline [options] [FILE...]

options:

  -h, --help      display this help and exit
  -v, --version   output version information and exit
```

The name _Bitline_ is a homage to my all time favourite signal analyzer software:
[Baudline](http://baudline.com)
