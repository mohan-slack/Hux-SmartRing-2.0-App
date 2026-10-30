# Brand kit generators (Python 3 + Pillow + NumPy; ffmpeg for video)

- `studio.py` – vector H (measured from images/logo.png), squircle masks, helpers
- `glass.py` – the Glass Charge mark: themes, glass ring, charge light, pearl, mono mark
- `brand.py` – crisp U/X glyphs cut from the wordmark
- `kit.py` – exports every icon (masters, iOS, Android, stores)
- `boards.py` – the 10 boards + social posters (needs the Urbanist TTFs)
- `anim3.py` – intro video (`square` | `portrait`)
- `apply_assets.py` – launch-screen and intro assets used by the app

Paths at the top of each script point at the machine they were made on —
edit `K`, `OUT`, `FD` and the logo path before running.
