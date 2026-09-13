/**
 * Structural checks per sheet: exact dimensions, and every populated cell
 * has >=2% non-transparent pixels (pins the blank-cell / tiny-character
 * defect class). No idle/sit seam-continuity check here - every animal's
 * idle/sit are cut from separate clips, so there's no shared seam to pin.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';

import { PNG } from 'pngjs';

import { RUN_HEAD_PAD } from './sheet-metrics';

const ASSETS = path.join(import.meta.dirname, '../assets');
const CELL = 240;

const ANIMALS = ['panda', 'cat', 'turtle', 'raccoon', 'bird', 'squirrel'];

interface SheetGeom {
  suffix: 'idle' | 'run' | 'sit';
  cols: number;
  rows: number;
  /** populated frame count - run's 4x3 grid has 12 cells but only 11 frames */
  frames: number;
}

const SHEET_GEOMS: SheetGeom[] = [
  { suffix: 'idle', cols: 5, rows: 5, frames: 25 },
  { suffix: 'run', cols: 4, rows: 3, frames: 11 },
  { suffix: 'sit', cols: 5, rows: 5, frames: 25 },
];

function readSheet(name: string): PNG {
  return PNG.sync.read(readFileSync(path.join(ASSETS, name)));
}

/** fraction of a cell's pixels with alpha > 0, stride-sampled to keep runtime reasonable */
function alphaCoverage(png: PNG, index: number, cols: number, stride = 2): number {
  const cx = (index % cols) * CELL;
  const cy = Math.floor(index / cols) * CELL;
  let opaque = 0;
  let sampled = 0;
  for (let y = 0; y < CELL; y += stride) {
    for (let x = 0; x < CELL; x += stride) {
      const i = ((cy + y) * png.width + cx + x) * 4;
      sampled += 1;
      if (png.data[i + 3] > 0) {
        opaque += 1;
      }
    }
  }
  return opaque / sampled;
}

/** first row (within the cell) holding any pixel with alpha > 20% */
function topOpaqueRow(png: PNG, index: number, cols: number): number {
  const cx = (index % cols) * CELL;
  const cy = Math.floor(index / cols) * CELL;
  for (let y = 0; y < CELL; y += 1) {
    for (let x = 0; x < CELL; x += 1) {
      if (png.data[((cy + y) * png.width + cx + x) * 4 + 3] > 51) {
        return y;
      }
    }
  }
  return CELL;
}

let checks = 0;

for (const animal of ANIMALS) {
  for (const geom of SHEET_GEOMS) {
    const png = readSheet(`${animal}-${geom.suffix}-sprite.png`);
    assert.equal(png.width, geom.cols * CELL, `${animal}-${geom.suffix} width`);
    assert.equal(png.height, geom.rows * CELL, `${animal}-${geom.suffix} height`);
    checks += 2;

    for (let f = 0; f < geom.frames; f += 1) {
      const coverage = alphaCoverage(png, f, geom.cols);
      assert.ok(
        coverage >= 0.02,
        `${animal}-${geom.suffix} frame ${f}: only ${(coverage * 100).toFixed(1)}% opaque pixels (< 2%) - looks blank`
      );
      checks += 1;
    }

    if (geom.suffix === 'run') {
      // RUN_HEAD_PAD must never claim more empty space than the sheet has:
      // the around route would hang the head into the home indicator
      let minTop = CELL;
      for (let f = 0; f < geom.frames; f += 1) {
        minTop = Math.min(minTop, topOpaqueRow(png, f, geom.cols));
      }
      const measuredPad = (minTop / CELL) * 54;
      const claimed = RUN_HEAD_PAD[animal];
      assert.ok(claimed !== undefined, `${animal}: RUN_HEAD_PAD entry`);
      assert.ok(
        claimed <= measuredPad,
        `${animal}-run: RUN_HEAD_PAD ${claimed}pt exceeds the measured ${measuredPad.toFixed(1)}pt`
      );
      assert.ok(
        measuredPad - claimed < 2,
        `${animal}-run: RUN_HEAD_PAD ${claimed}pt is stale, sheet has ${measuredPad.toFixed(1)}pt`
      );
      checks += 2;
    }
  }
}

console.log(`companion-sheets: ${checks} checks passed`);
