# Optional Local Binaries

This folder is intentionally empty in the public source distribution.

For normal source builds, install the command-line tools with Homebrew:

```sh
brew install yt-dlp ffmpeg deno
```

`build_app.sh` will still build the app without bundled binaries. At runtime,
Offloadly looks for `yt-dlp` and `ffmpeg` in common Homebrew locations and on
`PATH`.

If you want to make a private self-contained build, you may place executable
files here:

```text
Resources/yt-dlp
Resources/ffmpeg
```

The build script will copy them into `Offloadly.app`. Do not commit those
binaries to a public repository unless you have verified that the exact binaries
are legally redistributable.

