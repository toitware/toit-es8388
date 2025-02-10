# ES8388 Examples

The I2S takes uncompressed PCM as input. Under Linux you can use
  `ffmpeg` to convert audio files to PCM format.

```bash
# Stereo 16-bit 44.1kHz
ffmpeg -i input.mp3 -f s16le -acodec pcm_s16le -ar 44100 -ac 2 output.pcm

# Mono 16-bit 44.1kHz
ffmpeg -i input.mp3 -f s16le -acodec pcm_s16le -ar 44100 -ac 1 output.pcm
```

Run the `lyrat.toit` example on the device, then run the `server.toit`
  example on your computer with the URL of the device and the PCM file.

```bash
# Start a jag monitor in another terminal.
jag run lyrat.toit
jag -d host run server.toit -- $URL_FROM_JAG_MONITOR output.pcm
```
