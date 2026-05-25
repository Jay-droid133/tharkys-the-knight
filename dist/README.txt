================================================================
  THARKYS THE KNIGHT
  A ZX Spectrum 128K game in a portable desktop wrapper
================================================================

WHAT'S INSIDE
-------------
  tharkys.exe   The game. Just run it.
  LICENSES.txt  Third-party software + asset licenses.
  README.txt    This file.

QUICK START
-----------
  Double-click tharkys.exe. Wait through the splash cards; the
  game's "Press any key" prompt appears once the music has
  played through its third bar.

CONTROLS
--------
  Move      Q A O P  or  W A S D  or  arrow keys
  Fire      Space  or  Ctrl
  Map       M
  Pause     Esc          (Esc twice to quit while paused)
  Help      F1
  CRT FX    F2
  Border    F3           (cycles full / medium / minimal)
  Window    F11          (toggle fullscreen)

  Gamepad:  D-pad / left stick to move, any face button to fire,
            Start to pause, Back to open the map.

  Wrapper splash + story pages skip on any input.

COMMAND-LINE OPTIONS
--------------------
  --fullscreen        Boot straight into fullscreen.
  --windowed          Skip the default maximised window.
  --sna <path>        Load an external 128K .sna instead of the
                      embedded tape.
  --tap <path>        Load an external .tap.
  --no-soft-clip      Skip the audio soft limiter (A/B testing).
  --no-audio-pace     Use wall-clock instead of audio-queue pacing.
  --force-44100       Don't let SDL change the audio rate.
  --audio-debug       Log per-second beeper / AY peaks to tharkys.log.

CREDITS
-------
  Game design, pixel art, music
                       Jay Moreno (JayDroid)
  Code
                       Claude (Anthropic) under Jay's direction
  In-game font
                       "Reward" by Damien Guard
                       https://damieng.com/zx-origins

  Tools and libraries used in the desktop wrapper are listed in
  LICENSES.txt -- see them for full copyright notices.

================================================================
