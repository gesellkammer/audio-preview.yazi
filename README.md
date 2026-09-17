# audio-preview.yazi

A plugin for [yazi](https://github.com/sxyazi/yazi) to preview soundfiles as
spectrogram using `sox`, and to show audio metadata (duration, channels, sample
rate, and — for lossy codecs such as MP3 — bit rate) in the linemode.

## Requirements

- `sox` — for the spectrogram preview.
- `ffprobe` (from ffmpeg) **or** `soxi` (from sox) — for the linemode metadata.
  `ffprobe` is preferred when available, `soxi` is used as a fallback.

## Installation

```sh
ya pkg add 'gesellkammer/audio-preview'
```

## Setup

### Spectrogram previewer

Add this to your `yazi.toml`:

```toml
[plugin]
prepend_previewers = [
  { mime = "audio/*", run = "audio-preview" },
]

prepend_preloaders = [
  { mime = "audio/*", run = "audio-preview" },
]
```

### Linemode metadata

Register the plugin as a fetcher in your `yazi.toml` so audio metadata is
looked up in the background:

```toml
[[plugin.prepend_fetchers]]
mime  = "audio/*"
run   = "audio-preview"
group = "audio"
```

Then activate it as the linemode and initialize it from your `init.lua`:

```toml
[mgr]
linemode = "audio"
```

```lua
require("audio-preview"):setup {
	-- Optional, all shown below are the defaults.
	-- tool = "auto",     -- "auto" | "ffprobe" | "soxi"
	-- duration = true,
	-- channels = true,
	-- samplerate = true,
	-- bitrate = true,    -- only shown for lossy codecs (e.g. MP3)
	-- size = true,
}
```

`audio` is provided by this plugin, so it is **not** one of yazi's built-in
linemodes and won't appear in the documentation or any list. The `linemode`
setting and the `linemode` command accept any name and resolve it at render
time, so to use it:

- make it the default with `[mgr] linemode = "audio"` (above);
- bind a key, e.g. `run = "linemode audio"` (and `linemode none` to turn it off);
- or invoke the `linemode audio` command at runtime.

If `setup()` has not run, yazi has no `audio` method and renders the literal
text ` audio`.

The line is rendered as `duration channels x sample-rate [bit-rate] size`, with
the size always last, for example:

```
Thunderstorms.mp3   3:00:22 2x48k 128kb 170M
lucia.flac          0:04 2x44k1 370K
```

Sample rates use the `44k1` style (the `k` marks the decimal point). Sizes use
two significant figures, so `465,3K` becomes `470K`. Decimal fractions use a
comma. Non-audio files and directories simply show their size, so
`linemode = "audio"` can be used everywhere.

The audio metadata is also appended in every other linemode. This matters
because yazi's default sort keys (`,`,`m`, `,`,`b`, `,`,`s`, ...) also switch
the linemode, which would otherwise hide it:

```
# after `,` `m` (sort by modified time)
Thunderstorms.mp3   09/17 13:19 3:00:22 2x48k 128kb 170M
```

The size is only appended when the active linemode does not already show it
(so `size` mode yields `9,7M 10:35 2x44k1 128kb`, without a duplicate).

If you would rather keep `linemode = "audio"` while sorting, drop the second
command from the sort bindings in your `keymap.toml`, e.g.:

```toml
[[mgr.prepend_keymap]]
on   = [ ",", "m" ]
run  = "sort mtime --reverse=no"
desc = "Sort by modified time"
```

Since it is a fetcher, the metadata is only looked up for files that are
actually visible.

## License

MIT
