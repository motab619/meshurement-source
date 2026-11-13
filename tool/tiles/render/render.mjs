// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

// Renders raster map tiles from an OpenMapTiles-schema vector MBTiles
// (Planetiler output) with MapLibre Native, into a raster MBTiles that
// `pmtiles convert` turns into PMTiles.
//
//   node render.mjs --vector in.mbtiles --out out.mbtiles \
//     --bbox W,S,E,N --minzoom 8 --maxzoom 15 [--scale 2] [--format webp] \
//     [--quality 80] [--workers N] [--glyphs DIR] [--style style.json]
//     [--clip-to-source 1] [--tile-mask mask.txt]
//
// Re-runnable: tiles already in --out are skipped. With --clip-to-source,
// tiles with no vector data (none at that zoom, or no z14 parent above the
// source's max zoom) are skipped too, so a Planetiler --polygon clip carries
// through: the app falls back to OSM for a missing tile instead of showing
// an empty-land tile of ours. Planetiler's --polygon does not drop ocean
// tiles (the water polygons fill every tile in the bounds), so --tile-mask
// adds the clip outline itself: a text file whose first line is a zoom M
// and every further line "x y" (XYZ) of a zoom-M tile touching the outline
// (written by build_streets.sh with gdal_rasterize -at). A tile is rendered
// only if it lies in (z >= M) or contains (z < M) a listed tile.

// Child processes, not worker_threads: MapLibre Native is not a context-aware
// addon and refuses to load in a worker ("Module did not self-register").
import { fork } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';
import { gunzipSync } from 'node:zlib';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const GLYPH_URL = 'https://protomaps.github.io/basemaps-assets/fonts';

function args() {
  const a = {};
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i += 2) a[argv[i].replace(/^--/, '')] = argv[i + 1];
  if (!a.vector || !a.out || !a.bbox) {
    console.error('usage: render.mjs --vector in.mbtiles --out out.mbtiles --bbox W,S,E,N [options]');
    process.exit(2);
  }
  return {
    vector: a.vector,
    out: a.out,
    bbox: a.bbox.split(',').map(Number),
    minzoom: Number(a.minzoom ?? 8),
    maxzoom: Number(a.maxzoom ?? 15),
    scale: Number(a.scale ?? 2),
    format: a.format ?? 'webp',
    quality: Number(a.quality ?? 80),
    workers: Number(a.workers ?? Math.max(1, os.cpus().length - 2)),
    glyphs: a.glyphs ?? path.join(path.dirname(a.out), 'glyphs'),
    style: a.style ?? path.join(here, 'style.json'),
    clipToSource: a['clip-to-source'] === '1',
    tileMask: a['tile-mask'],
  };
}

const lon2x = (lon, z) => Math.floor(((lon + 180) / 360) * 2 ** z);
const lat2y = (lat, z) => {
  const r = (lat * Math.PI) / 180;
  return Math.floor(((1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2) * 2 ** z);
};
const x2lon = (x, z) => (x / 2 ** z) * 360 - 180;
const y2lat = (y, z) => {
  const n = Math.PI - (2 * Math.PI * y) / 2 ** z;
  return (180 / Math.PI) * Math.atan(Math.sinh(n));
};

function* tilesIn(bbox, minzoom, maxzoom) {
  const [w, s, e, n] = bbox;
  for (let z = minzoom; z <= maxzoom; z++) {
    for (let x = lon2x(w, z); x <= lon2x(e, z); x++) {
      for (let y = lat2y(n, z); y <= lat2y(s, z); y++) yield [z, x, y];
    }
  }
}

// ─── worker: one MapLibre map, renders tiles on request ───────────────────
async function worker() {
  const { vector, glyphs, style, scale, format, quality } = JSON.parse(process.env.RENDER_OPTS);
  const mbgl = (await import('@maplibre/maplibre-gl-native')).default;
  const sharp = (await import('sharp')).default;
  const db = new DatabaseSync(vector, { readOnly: true });
  const q = db.prepare('SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?');

  const map = new mbgl.Map({
    ratio: scale,
    mode: 'tile',
    request: (req, cb) => {
      try {
        const u = req.url;
        if (u.startsWith('mbtiles://')) {
          const [z, x, y] = u.slice(10).split('/').map(Number);
          const row = q.get(z, x, 2 ** z - 1 - y);
          if (!row) return cb();
          let data = Buffer.from(row.tile_data);
          if (data[0] === 0x1f && data[1] === 0x8b) data = gunzipSync(data);
          return cb(null, { data });
        }
        if (u.startsWith('glyphs://')) {
          const [stack, range] = decodeURIComponent(u.slice(9)).split('/');
          const file = path.join(glyphs, stack, `${range}.pbf`);
          if (fs.existsSync(file)) return cb(null, { data: fs.readFileSync(file) });
          fetch(`${GLYPH_URL}/${encodeURIComponent(stack)}/${range}.pbf`)
            .then(async (r) => {
              if (!r.ok) return cb();
              const data = Buffer.from(await r.arrayBuffer());
              fs.mkdirSync(path.dirname(file), { recursive: true });
              const tmp = `${file}.${process.pid}.${Math.random()}`;
              fs.writeFileSync(tmp, data);
              fs.renameSync(tmp, file);
              cb(null, { data });
            })
            .catch(() => cb());
          return;
        }
        cb();
      } catch (e) {
        cb(e);
      }
    },
  });
  map.load(JSON.parse(fs.readFileSync(style, 'utf8')));

  process.on('message', ([z, x, y]) => {
    // A 256 px XYZ tile at zoom z is MapLibre zoom z-1 (512 px world).
    const center = [x2lon(x + 0.5, z), y2lat(y + 0.5, z)];
    map.render({ zoom: z - 1, center, width: 256, height: 256 }, async (err, pixels) => {
      if (err) return process.send({ z, x, y, err: String(err) });
      const size = 256 * scale;
      let img = sharp(pixels, { raw: { width: size, height: size, channels: 4 } });
      img = format === 'png' ? img.png({ compressionLevel: 9, palette: true }) : img.webp({ quality });
      const data = await img.toBuffer();
      process.send({ z, x, y, data });
    });
  });
  process.send({ ready: true });
}

// ─── main: queue tiles, write MBTiles ─────────────────────────────────────
async function main() {
  const o = args();
  fs.mkdirSync(path.dirname(o.out), { recursive: true });
  fs.mkdirSync(o.glyphs, { recursive: true });
  const out = new DatabaseSync(o.out);
  out.exec(`
    CREATE TABLE IF NOT EXISTS metadata (name TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE IF NOT EXISTS tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);
    CREATE UNIQUE INDEX IF NOT EXISTS tile_index ON tiles (zoom_level, tile_column, tile_row);
    PRAGMA journal_mode = WAL;`);
  const meta = out.prepare('INSERT OR REPLACE INTO metadata VALUES (?, ?)');
  const [w, s, e, n] = o.bbox;
  for (const [k, v] of Object.entries({
    name: path.basename(o.out, '.mbtiles'),
    format: o.format,
    type: 'baselayer',
    bounds: o.bbox.join(','),
    center: `${(w + e) / 2},${(s + n) / 2},${o.minzoom + 3}`,
    minzoom: String(o.minzoom),
    maxzoom: String(o.maxzoom),
    attribution: '© OpenMapTiles © OpenStreetMap contributors',
  })) meta.run(k, v);

  const has = out.prepare('SELECT 1 FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?');
  const put = out.prepare('INSERT OR REPLACE INTO tiles VALUES (?, ?, ?, ?)');
  let inSource = () => true;
  if (o.clipToSource) {
    const src = new DatabaseSync(o.vector, { readOnly: true });
    const srcMax = Number(src.prepare("SELECT value FROM metadata WHERE name='maxzoom'").get()?.value ?? 14);
    const srcHas = src.prepare('SELECT 1 FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?');
    inSource = (z, x, y) => {
      const dz = Math.max(0, z - srcMax);
      const sz = z - dz, sx = x >> dz, sy = y >> dz;
      return !!srcHas.get(sz, sx, 2 ** sz - 1 - sy);
    };
  }
  let inMask = () => true;
  if (o.tileMask) {
    const lines = fs.readFileSync(o.tileMask, 'utf8').trim().split('\n');
    const mz = Number(lines[0]);
    // keys "z/x/y" of every listed tile and all its ancestors down to minzoom
    const keep = new Set();
    for (const l of lines.slice(1)) {
      let [x, y] = l.split(' ').map(Number);
      for (let z = mz; z >= 0; z--, x >>= 1, y >>= 1) {
        const k = `${z}/${x}/${y}`;
        if (keep.has(k)) break;
        keep.add(k);
      }
    }
    inMask = (z, x, y) => {
      const dz = Math.max(0, z - mz);
      return keep.has(`${z - dz}/${x >> dz}/${y >> dz}`);
    };
    console.log(`tile mask: ${lines.length - 1} tiles at z${mz}`);
  }
  const todo = [];
  let total = 0, clipped = 0;
  for (const [z, x, y] of tilesIn(o.bbox, o.minzoom, o.maxzoom)) {
    total++;
    if (!inMask(z, x, y) || !inSource(z, x, y)) { clipped++; continue; }
    if (!has.get(z, x, 2 ** z - 1 - y)) todo.push([z, x, y]);
  }
  console.log(`${total} tiles in bbox z${o.minzoom}-${o.maxzoom}, ${clipped} outside the clip/source, ${todo.length} to render, ${o.workers} workers`);
  if (todo.length === 0) return;

  let done = 0, failed = 0, next = 0, bytes = 0;
  const started = Date.now();
  out.exec('BEGIN');
  await new Promise((resolve) => {
    let live = o.workers;
    for (let i = 0; i < o.workers; i++) {
      const wk = fork(fileURLToPath(import.meta.url), ['--child'], {
        env: { ...process.env, RENDER_OPTS: JSON.stringify(o) },
        serialization: 'advanced', // Buffers cross intact
      });
      const feed = () => {
        if (next < todo.length) wk.send(todo[next++]);
        else { wk.kill(); if (--live === 0) resolve(); }
      };
      wk.on('message', (m) => {
        if (m.ready) return feed();
        if (m.err) { failed++; console.error(`${m.z}/${m.x}/${m.y}: ${m.err}`); }
        else {
          put.run(m.z, m.x, 2 ** m.z - 1 - m.y, m.data);
          bytes += m.data.length;
        }
        done++;
        if (done % 500 === 0) {
          out.exec('COMMIT'); out.exec('BEGIN');
          const rate = done / ((Date.now() - started) / 1000);
          console.log(`  ${done}/${todo.length} (${rate.toFixed(0)}/s, ~${((todo.length - done) / rate / 60).toFixed(1)} min left)`);
        }
        feed();
      });
      wk.on('error', (e) => { console.error('worker error', e); if (--live === 0) resolve(); });
    }
  });
  out.exec('COMMIT');
  out.close();
  console.log(`rendered ${done - failed} tiles (${(bytes / 1e6).toFixed(1)} MB), ${failed} failed, ${((Date.now() - started) / 1000).toFixed(0)} s`);
  if (failed) process.exitCode = 1;
}

if (process.argv.includes('--child')) worker(); else main();
