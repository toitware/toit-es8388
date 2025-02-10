// Copyright (C) 2025 Florian Loitsch <florian@loitsch.com>
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the examples/LICENSE file.

import fs
import net
import host.file
import system

/**
Server that forwards PCM data to an ESP32-LyraT board running
  the `lyrat.toit` program.
*/

make-mono --left/bool=true bytes/ByteArray -> ByteArray:
  result := ByteArray bytes.size / 2
  right-offset := left ? 0 : 2
  for i := 0; i < result.size; i += 2:
    result[i] = bytes[2 * i + right-offset]
    result[i + 1] = bytes[2 * i + 1 + right-offset]

  return result

fix-esp32 bytes/ByteArray --mono/bool=false --bits-per-sample/int -> ByteArray:
  result/ByteArray := ?
  if bits-per-sample == 8:
    result = ByteArray bytes.size * 2
    bytes.size.repeat: | i |
      result[2 * i + 1] = 0
      result[2 * i] = bytes[i]
  else if bits-per-sample == 24:
    result = ByteArray bytes.size * 4 / 3
    j := 1
    for i := 0; i < bytes.size; i += 3:
      result[j] = bytes[i]
      result[j + 1] = bytes[i + 1]
      result[j + 2] = bytes[i + 2]
      j += 4
  else:
    result = bytes.copy

  if mono and (bits-per-sample == 8 or bits-per-sample == 16):
    // Swap every two bytes.
    for i := 0; i < bytes.size; i += 4:
      t := bytes[i]
      bytes[i] = bytes[i + 2]
      bytes[i + 2] = t
      t = bytes[i + 1]
      bytes[i + 1] = bytes[i + 3]
      bytes[i + 3] = t

  return bytes

main args:
  ip-port := args[0]
  pcm := args[1]

  program-dir := fs.dirname system.program-path
  pcm-path := fs.to-absolute pcm
  pcm-content := file.read-contents pcm-path

  // These two configurations must be synchronized with the code that runs
  // on the device.
  mono := false
  bits-per-sample := 16

  if mono: pcm-content = make-mono pcm-content --left
  pcm-content = fix-esp32 pcm-content --mono=mono --bits-per-sample=bits-per-sample

  network := net.open

  parts := ip-port.split ":"
  ip := parts[0]
  port := int.parse parts[1]
  socket := network.tcp-connect ip port

  while true:
    socket.out.write pcm-content
