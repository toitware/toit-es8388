// Copyright (C) 2025 Florian Loitsch <florian@loitsch.com>
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the examples/LICENSE file.

import gpio
import i2c
import i2s
import net

import es8388

/**
Example of a Toit program that runs on an ESP32-LyraT board.

It accepts PCM data on a TCP socket and streams the audio to the ES8388 codec.
*/

MCLK ::= 0
SCLK ::= 5
LRCK ::= 25
DSDIN ::= 26
ASDOUT ::= 35

SCL ::= 23
SDA ::= 18

SENSOR-VP ::= 36
SENSOR-VN ::= 39

PLAY ::= 33
SET ::= 32
VOL-DOWN ::= 13
VOL-UP ::= 27

SAMPLE-RATE ::= 48_000
MCLK-MULTIPLE ::= 256 // 384
MCLK-FREQUENCY ::= SAMPLE-RATE * MCLK-MULTIPLE

stream channel/i2s.Bus:
  network := net.open
  server-socket := network.tcp-listen 7017
  print "$network.address:$server-socket.local-address.port"
  socket := server-socket.accept
  reader := socket.in
  while true:
    data := reader.read
    consumed := channel.preload data
    if consumed != data.size:
      reader.unget data[consumed..]
      break

  print "Preloading done. Starting."

  channel.start
  last-error := channel.errors
  while true:
    data := reader.read
    channel.write data
    if channel.errors != last-error:
      last-error = channel.errors
      print_ "Errors: $last-error"

main:
  i2c-bus := i2c.Bus
      --scl=gpio.Pin SCL
      --sda=gpio.Pin SDA

  print i2c-bus.scan

  i2c-device := i2c-bus.device es8388.Es8388.I2C-ADDRESS

  channel := i2s.Bus
      --master
      --mclk=gpio.Pin MCLK
      --tx=gpio.Pin DSDIN
      --ws=gpio.Pin LRCK
      --sck=gpio.Pin SCLK

  codec := es8388.Es8388 i2c-device channel
      --bits-per-sample=16
      --sample-rate=SAMPLE-RATE
      --slots=i2s.Bus.SLOTS-STEREO-BOTH
      --no-start

  stream channel
