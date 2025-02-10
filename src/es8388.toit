// Copyright (C) 2025 Florian Loitsch <florian@loitsch.com>
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

/**
A driver for the ES8388 audio codec.
*/

// Partially inspired by
// https://github.com/espressif/esp-adf/tree/master/components/audio_hal/driver/es8388

import i2s
import serial

/**
A driver for the ES8388 audio codec.
*/
class Es8388:
  /** The default I2C address. */
  static I2C-ADDRESS     ::= 0x10
  /** The alternate I2C address. */
  static I2C-ADDRESS-ALT ::= 0x11

  /** The maximum I2C frequency for this chip. */
  static I2C-FREQUENCY ::= 400_000

  static REGISTER-CHIP-CONTROL-1_ ::= 0
  static REGISTER-CHIP-CONTROL-2_ ::= 1
  static REGISTER-CHIP-POWER_ ::= 2
  static REGISTER-ADC-POWER_ ::= 3
  static REGISTER-DAC-POWER_ ::= 4

  static REGISTER-MASTER-MODE-CONTROL_ ::= 8

  /** Mic input. */
  static REGISTER-ADC-CONTROL-2_ ::= 10
  /** ADC volume control left. */
  static REGISTER-ADC-CONTROL-8_ ::= 16
  /** ADC volume control right. */
  static REGISTER-ADC-CONTROL-9_ ::= 17

  /**
  - Swap LR.
  - Bits per sample.
  - Format.
  - Inverted data.
  */
  static REGISTER-DAC-CONTROL-1_ ::= 23
  /** DAC mute, among other configurations. */
  static REGISTER-DAC-CONTROL-3_ ::= 25
  static REGISTER-DAC-CONTROL-3-DEFAULT_ ::= 0b0010_0010

  /** DAC volume control left. */
  static REGISTER-DAC-CONTROL-4_ ::= 26
  /** DAC volume control right. */
  static REGISTER-DAC-CONTROL-5_ ::= 27

  /** IN mux. */
  static REGISTER-DAC-CONTROL-16_ ::= 38
  /** Left DAC to left mixer. */
  static REGISTER-DAC-CONTROL-17_ ::= 39
  /** Right DAC to right mixer. */
  static REGISTER-DAC-CONTROL-42_ ::= 42

  /** LRCLK control. */
  static REGISTER-DAC-CONTROL-21_ ::= 43
  static REGISTER-DAC-CONTROL-21-DEFAULT_ ::= 0b0000_0000

  /** LOUT1 Volume. */
  static REGISTER-DAC-CONTROL-24_ ::= 46
  /** ROUT1 Volume. */
  static REGISTER-DAC-CONTROL-25_ ::= 47

  /** LOUT2 Volume. */
  static REGISTER-DAC-CONTROL-26_ ::= 48
  /** ROUT2 Volume. */
  static REGISTER-DAC-CONTROL-27_ ::= 49

  /**
  The input to the in mux (with output 'LIN'/'RIN').
  */
  static IN1_ ::= 0
  static IN2_ ::= 1
  static MIC_ ::= 3

  // In SPI mode, only write operations are supported.
  // We therefore don't use read operations in this driver.
  registers_/serial.Registers

  /**
  Constructs a new ES8388 driver.

  The $device must be an I2C device connected to the codec.
  The I2S $bus must be in master mode and will be reconfigured according to
    the given $bits-per-sample, $sample-rate, $slots, and codec requirements.
  If $start is true, then the $bus is started after configuration.

  See $set-gain for the $gain variable, and $set-out-volume for the $volume variable.
  */
  constructor
      device/serial.Device
      bus/i2s.Bus
      --muted/bool=false
      --bits-per-sample/int
      --sample-rate/int
      --slots=i2s.Bus.SLOTS-STEREO-BOTH
      --start/bool
      --gain/int=-120
      --volume/int=-90:

    if not bus.is-master: throw "UNIMPLEMENTED"

    bus.stop

    bus.configure
        --mclk-multiplier=bits-per-sample % 3 == 0 ? 384  : 256
        --bits-per-sample=bits-per-sample
        --sample-rate=sample-rate
        --format=i2s.Bus.FORMAT-PHILIPS
        --slots=slots

    registers_ = device.registers

    set-mute true

    power_ --dac true
    power_ --analog true
    mclk-config_
        --no-master
        --no-double
        --no-invert
        --divider=null // Auto detect.

    set-same-lrclk_

    set-bits-per-sample_ bits-per-sample

    set-gain --dac gain

    route-dac-to-output-mixer_

    set-out-volume --output=1 volume

    enable-digital-processing_

    if not muted: set-mute false

    if start: bus.start

  /**
  Sets the DAC volume.

  The $gain must be a value between -960 and 0, corresponding to
    -96.0dB to 0.0dB. The gain is in 0.5dB steps.
  */
  set-gain --dac/True gain/int:
    set-gain_ --adc=false gain

  /**
  Sets the ADC volume.

  This is used for to the internal ADC->DAC route.

  See $(set-gain --dac gain).
  */
  set-gain --adc/True gain/int:
    set-gain_ --adc=true gain

  set-gain_ --adc/bool gain/int:
    if not -960 <= gain <= 0: throw "INVALID_ARGUMENT"
    gain = -gain
    half := gain % 10 > 5
    db := gain / 10
    value := (db << 1) | (half ? 1 : 0)

    register-left := adc ? REGISTER-ADC-CONTROL-8_ : REGISTER-DAC-CONTROL-4_
    register-right := adc ? REGISTER-ADC-CONTROL-9_ : REGISTER-DAC-CONTROL-5_

    write-register_ register-left value
    write-register_ register-right value

  /**
  Sets the mixer input.

  In the diagram of the datasheet, this is the mux with output 'LIN'/'RIN'.

  The $input must be one of $IN1_, $IN2_, $MIC_.

  Sets both the left and right input.
  */
  set-in-mux_ input/int:
    if input != IN1_ and input != IN2_ and input != MIC_: throw "INVALID_ARGUMENT"
    value := (input << 4) | input
    write-register_ REGISTER-DAC-CONTROL-16_ value

  /**
  Sets the mic input.

  In the diagram of the datasheet, this is the mux with the output
    that goes into the 'mic amp'.

  Must be one of $IN1_, or $IN2_. Differential inputs (LIN1-RIN2, ...)
    are not supported.

  By default, the codec sets $IN1_.
  */
  set-mic-mux_ input/int:
    if input != IN1_ and input != IN2_: throw "INVALID_ARGUMENT"
    value := (input << 6) | (input << 4)
    write-register_ REGISTER-ADC-CONTROL-2_ value

  power_ --adc/True value/bool:
    write-register_ REGISTER-ADC-POWER_ (value ? 0x00 : 0xFF)

  power_ --dac/True value/bool:
    // Turn everything on/off.
    write-register_ REGISTER-DAC-POWER_ (value ? 0b00111100 : 0x1100_0000)

  power_ --analog/True value/bool:
    write-register_ REGISTER-CHIP-CONTROL-2_ (value ? 0b00 : 0xFF)

  set-mute value/bool:
    mute-bit := value ? 0b0000_0100 : 0
    new-bits := REGISTER-DAC-CONTROL-3-DEFAULT_ |  mute-bit
    write-register_ REGISTER-DAC-CONTROL-3_ new-bits

  /**
  Supported clock dividers for the master mode.

  The BCLK (SCLK) is generated by dividing the master clock by the
    divider.

  For internal reasons the dividers are not sorted.
  */
  static MCLK-BCLK-DIVIDERS_ ::= [
    1, 2, 3, 4, 6, 8, 9, 11, 12, 16, 18, 22, 24, 33,
    36, 44, 48, 66, 72, 5, 10, 15, 17, 20, 25, 30, 32, 34
  ]
  /**
  If $double is true, the codec is configured in double speed mode.
    In that case the master clock is divided by two.

  In slave mode, the codec can automatically detect the ratio between
    the master clock and the sampling frequency. However, the allowed
    configurations are more limited. The following ratios are supported:
  - In single mode: the frequency must be 8kHz to 50kHz, and the
    master-clock multiplier must be one of 256, 384, 512, 768, or 1024.
  - In $double mode: the frequency must be 50kHz to 100kHz, and the
    master-clock multiplier must be one of 128, 192, 256, 384, or 512.

  In master mode, the rations in $MCLK-BCLK-DIVIDERS_ are supported.
  */
  mclk-config_
      --master/bool
      --double/bool
      --invert/bool
      --divider/int?:
    divider-bits/int := ?
    if divider:
      index := MCLK-BCLK-DIVIDERS_.index-of divider
      if index == -1: throw "INVALID_ARGUMENT"
      divider-bits = index + 1
    else:
      // The master mode BCLK is generated automatically based on the clock table.
      divider-bits = 0

    bits := (master ? 0x1000_0000 : 0)
        | (double ? 0x0100_0000 : 0)
        | (invert ? 0x0010_0000 : 0)
        | divider-bits

    write-register_ REGISTER-MASTER-MODE-CONTROL_ bits

  /**
  Sets the mclk multiplier.

  The mclk-multiplier is the ratio between mclk and sampling frequency (the
    LRCLK frequency; where LRCLK is also often called WS). The mclk-multiplier
    must be one of 128, 192, 256, 384, 512, 768, 1024, 1152, 1408, 1536, 2112,
    or 2304.
  */
  set-mclk-multiplier_ value/int:
    throw "UNIMPLEMENTED"

  /**
  Whether the LRCLK (WS) is the same for the ADC and the DAC.

  The codec internally has two LRCLKs, one for the ADC (ALRCK) and one for the
    DAC (DLRCK). However, only one pin is used externally for it. The easiest
    is to set the same LRCLK for both the ADC and the DAC.
  */
  set-same-lrclk_:
    // Use same LRCK for ADC and DAC.
    // When being the master use the one of the DAC.
    bits := REGISTER-DAC-CONTROL-21-DEFAULT_ | 0b1000_0000
    write-register_ REGISTER-DAC-CONTROL-21_ bits

  /**
  Routes both DACs to their respective mixers.

  The gain must be one of 6, 3, 0, -3, -6, -9, -12 or -15dB.
  */
  route-dac-to-output-mixer_ --gain/int=0:
    if not -15 <= gain <= 6: throw "INVALID_ARGUMENT"
    if gain % 3 != 0: throw "INVALID_ARGUMENT"
    gain-bits := ((-gain / 3) + 2) << 3
    dac-to-mixer-enable-bits := 0x80
    value := dac-to-mixer-enable-bits | gain-bits
    write-register_ REGISTER-DAC-CONTROL-17_ value
    write-register_ REGISTER-DAC-CONTROL-42_ value

  /**
  Sets the volume of output 1.

  The $volume value must be in range -450 (-4.5dB) to 45 (4.5dB) in
    steps of 15 (1.5dB).
  */
  set-out-volume --output/int volume/int:
    if not -450 <= volume <= 45: throw "INVALID_ARGUMENT"
    if volume % 15 != 0: throw "INVALID_ARGUMENT"
    value := (volume + 450) / 15
    register-left := output == 1 ? REGISTER-DAC-CONTROL-24_ : REGISTER-DAC-CONTROL-26_
    register-right := output == 1 ? REGISTER-DAC-CONTROL-25_ : REGISTER-DAC-CONTROL-27_
    write-register_ register-left value
    write-register_ register-right value

  enable-digital-processing_:
    write-register_ REGISTER-CHIP-POWER_ 0x00

  set-bits-per-sample_ bits-per-sample/int:
    unshifted/int := ?
    if bits-per-sample == 24: unshifted = 0b000
    else if bits-per-sample == 20: unshifted = 0b001
    else if bits-per-sample == 18: unshifted = 0b010
    else if bits-per-sample == 16: unshifted = 0b011
    else if bits-per-sample == 32: unshifted = 0b100
    else: throw "INVALID_ARGUMENT"

    bits := unshifted << 3
    // Set word length (bits-per-sample) with Philips format.
    write-register_ REGISTER-DAC-CONTROL-1_ bits

  /**
  Writes the given $value to the $register.

  Since the codec only supports write operations in SPI mode, we
    don't have a corresponding read operation.
  */
  write-register_ register/int value/int:
    registers_.write-u8 register value
