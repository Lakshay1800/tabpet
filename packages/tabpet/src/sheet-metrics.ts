/**
 * Measured margins of bundled run sheets, in pt at reference size (240px
 * cell = PERCH_SIZE); sheets.test.ts checks them against the PNGs.
 * RUN_HEAD_PAD: empty rows above the tallest drawing (alpha > 20%) across
 * all 11 cells, needed so the around route leans the companion only as far as
 * the screen allows. Measure with:
 *   magick <run-sprite.png> -crop 240x240+X+Y +repage -channel A -threshold 20% +channel -format '%@' info:
 * headPad = floor(min top offset / 240 * 54).
 */
export const RUN_HEAD_PAD: Record<string, number> = {
  panda: 2,
  cat: 12,
  turtle: 24,
  raccoon: 21,
  bird: 19,
  squirrel: 9,
};
