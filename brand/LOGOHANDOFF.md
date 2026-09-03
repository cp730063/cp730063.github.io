# FantasyMags logo — implementation handoff

Three SVG files, no build step, no dependencies. Everything is plain paths — no gradients,
no filters, no raster, no external fonts inside the artwork.

| File | What it is | Where it goes |
|---|---|---|
| `favicon.svg` | Head only. Self-contained, has its own light/dark switch. | Browser tab, PWA |
| `fm-mark.svg` | Head only. Themeable — colours come from CSS. | Site header, avatars, anywhere small |
| `fm-logo.svg` | Full scene: seated on a chair, reading, head turned to camera. | Hero, About page, footer, share cards |

**Rule of thumb:** below about 40px the full scene turns to mush. Use `fm-mark.svg` for
anything smaller than a 64px box. Use `fm-logo.svg` where it has real room.

---

## 1. Favicon

`favicon.svg` is fully self-contained — it carries its own `prefers-color-scheme` block, so
it lightens itself on dark browser chrome. Drop it at the site root and add:

```html
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon.ico" sizes="32x32">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
```

Still to generate (I can't produce raster here):

- `favicon.ico` — 32×32, for older browsers.
- `apple-touch-icon.png` — 180×180. **Must have an opaque background** — iOS does not honour
  transparency and a black dog on a transparent ground becomes a black square. Use the cream
  plate `#F4F1E8` behind the mark, with the mark inset to about 80% of the box.
- `icon-512.png` — 512×512 maskable for the web manifest, same cream plate, mark inset to 70%
  so the safe zone crop doesn't clip her ears.

Export all three from `fm-mark.svg`, not from the full scene.

---

## 2. Theming (`fm-mark.svg` and `fm-logo.svg`)

Every fill is `var(--fm-*, <light fallback>)`. **Inline the SVG** into the page (or import it
as a component) so the cascade reaches it — an `<img src>` cannot be themed.

The light palette is already baked in as fallbacks, so if you do nothing it renders correctly
in light mode. To support dark mode, paste this into the stylesheet. It follows the same
three-state pattern the site already uses:

```css
/* light — also the fallbacks already inside the SVGs */
:root{
  --fm-fur:#191d24;  --fm-fur-lt:#272e38; --fm-fur-dk:#0d1014;
  --fm-grz:#bdb8aa;  --fm-grz-lt:#d8d3c5;
  --fm-nose:#0a0c10; --fm-eye:#4a3320;    --fm-pupil:#130e07;
  --fm-sclera:#d8cfbe; --fm-hl:#ffffff;   --fm-tongue:#c9737e;
  --fm-blaze:#efece2;
  --fm-pg:#f7f5ef;   --fm-pg2:#e9e5da;    --fm-pgline:#cfc9bb; --fm-seam:#b04a3c;
  --fm-wood:#a8783a; --fm-wood-dk:#7a5622; --fm-wood-lt:#bb8b45;
  --fm-acc:#1f7a4d;  --fm-acc2:#8a6320;   --fm-acctx:#f7f5ef;
}

@media (prefers-color-scheme:dark){
  :root:not([data-theme="light"]){
    --fm-fur:#39434f;  --fm-fur-lt:#4b5764; --fm-fur-dk:#28303a;
    --fm-grz:#c6c1b3;  --fm-grz-lt:#e0dbcd;
    --fm-nose:#1a1f28; --fm-eye:#c39a63;    --fm-pupil:#231a10;
    --fm-sclera:#8d8574; --fm-hl:#ffffff;   --fm-tongue:#cf7d88;
    --fm-blaze:#f2efe6;
    --fm-pg:#f2efe7;   --fm-pg2:#e2ded2;    --fm-pgline:#c6c0b2; --fm-seam:#c9584a;
    --fm-wood:#b3853f; --fm-wood-dk:#8a6229; --fm-wood-lt:#c69652;
    --fm-acc:#3f9c6b;  --fm-acc2:#c6a15b;   --fm-acctx:#12171d;
  }
}

:root[data-theme="dark"]{
  /* same block as the media query above — repeat it verbatim */
}
```

**Why the dark set is not an inversion:** she is a black dog. At full black she vanishes on the
`#0F1318` ground, so the fur lifts to a blue-charcoal and the eyes warm to amber. Do not try to
generate the dark version with a CSS `filter: invert()` — it will turn the magazine black and
her grey muzzle into a bright stain.

---

## 3. Header lockup

Mark plus wordmark, baseline-aligned:

```html
<a class="fm-logo" href="/">
  <!-- paste the contents of fm-mark.svg here -->
  <span class="fm-wordmark">
    <span class="fm-name">Fantasy<i>Mags</i></span>
    <span class="fm-tag">Your personal fantasy magazine</span>
  </span>
</a>
```

```css
.fm-logo{display:flex;align-items:center;gap:14px;text-decoration:none}
.fm-logo svg{width:44px;height:44px;flex:none}
.fm-wordmark{display:flex;flex-direction:column;line-height:1}
.fm-name{
  font-family:"Barlow Condensed",Arial Narrow,sans-serif;
  font-weight:700;text-transform:uppercase;font-size:30px;letter-spacing:.012em;
  color:var(--ink);
}
.fm-name i{font-style:normal;color:var(--green)}   /* MAGS in the green accent */
.fm-tag{
  font-family:"IBM Plex Mono",monospace;
  font-size:7.5px;letter-spacing:.175em;text-transform:uppercase;
  margin-top:7px;color:var(--muted);white-space:nowrap;
}
```

The tagline is deliberately sized so its width matches the wordmark above it. If you change the
wordmark size, rescale the tagline to match — that optical alignment is the point of the caps.

---

## 4. Clear space and minimum sizes

- **Clear space:** keep a margin equal to the height of one ear on all sides. Nothing crosses it.
- **Minimum sizes:** `fm-mark.svg` down to 16px. `fm-logo.svg` no smaller than 64px.
- **Do not** put the mark on a busy photo, add a drop shadow, outline it, rotate it, recolour
  her fur to a brand colour, or stretch either file non-uniformly.
- Both files are square. `fm-mark.svg` is `viewBox="127 7 210 210"`; `fm-logo.svg` is
  `viewBox="0 0 400 400"` with the artwork pre-inset — it needs no extra padding in a badge.

---

## 5. Open graph / share card

1200×630, cream `#F4F1E8` ground, `fm-logo.svg` at 420px on the left, wordmark and tagline on
the right, ink `#161B22` on cream. Needs to be exported as PNG — most scrapers won't take SVG.

---

## Status

This is **pass 2** of the illustration and it's approved for use, not finished. Expect a
revised drawing later; the file names, viewBoxes and custom-property names will stay the same,
so a future update is a file swap with no code change. Build against the token names, not
against the paths.
