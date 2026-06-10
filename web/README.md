# Native Plants Web MVP

Static catalog MVP for moving the plant browser to `herringtonhq.com`.

## Local Preview

Run a static server from the repo root:

```sh
python3 -m http.server 4173 --directory web
```

Then open `http://localhost:4173`.

## Deploy Shape

The `web/` folder is self-contained:

- `index.html`
- `styles.css`
- `app.js`
- `data/plants.json`
- `images/*.png`

Copy those files into the target `herringtonhq` path and keep the relative
`data/` and `images/` directories next to `index.html`.

## Refresh Data

After changing the iOS catalog, refresh the static web payload from the repo root:

```sh
cp NativePlants/plants.json web/data/plants.json
cp NativePlants/Images/*.png web/images/
```
