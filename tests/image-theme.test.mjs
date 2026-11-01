import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const read = path => readFileSync(new URL('../harmony/entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replace(/^import[^\n]*\n/gm, '').replace(/\bexport /g, '');
const code = stripTypeScriptTypes(read('model/ThemeColors.ets') + '\n' + read('service/ImageThemePicker.ets')) +
  '\n({ ImageThemePicker, imageThemeColors })';
const rgb = (red, green, blue, alpha = 255) => ({ red, green, blue, alpha });

function harness(config = {}) {
  const events = []; const handles = new Set();
  const image = {
    PixelMapFormat: { RGBA_8888: 3 },
    createImageSource: fd => {
      assert.ok(handles.has(fd));
      return {
        getImageInfo: async () => ({ size: config.dimensions ?? { width: 6000, height: 4000 } }),
        createPixelMap: async options => {
          events.push(['decode', options]);
          if (config.decodeFailure) throw new Error('decode failed');
          return { release: async () => events.push(['release-pixels']) };
        },
        release: async () => events.push(['release-source'])
      };
    }
  };
  const fileApi = {
    OpenMode: { READ_ONLY: 0 },
    open: async (uri, mode) => {
      assert.equal(mode, 0); events.push(['open', uri]); handles.add(101); return { fd: 101 };
    },
    stat: async () => ({ size: config.size ?? 100 }),
    close: async file => { assert.ok(handles.delete(file.fd)); events.push(['close']); }
    // No write/delete APIs: extraction must not copy images or modify the background.
  };
  const effectKit = { createColorPicker: async pixels => {
    events.push(['color-picker']);
    if (config.pickerFailure) throw new Error('color picker failed');
    return {
      getMainColor: async () => {
        events.push(['main-color']);
        if (config.mainFailure) throw new Error('main color failed');
        return config.mainColor ?? rgb(18, 52, 86);
      },
      getTopProportionColors: count => {
        assert.equal(count, 4); events.push(['top-colors']);
        if (config.topFailure) throw new Error('top colors failed');
        return config.topColors ?? [rgb(18, 52, 86), rgb(171, 205, 239), null, rgb(255, 128, 0)];
      }
    };
  } };
  const photoAccessHelper = {
    PhotoViewMIMETypes: { IMAGE_TYPE: 'image/*' }, PhotoSelectOptions: class {},
    PhotoViewPicker: class { async select(options) {
      assert.equal(options.MIMEType, 'image/*'); assert.equal(options.maxSelectNumber, 1);
      events.push(['select']); return { photoUris: config.cancel ? [] : ['file://media/Photo/selected.png'] };
    } }
  };
  const api = runInNewContext(code, { fs: fileApi, image, effectKit, photoAccessHelper });
  return { ...api, picker: new api.ImageThemePicker(), events, handles };
}

test('System photo selection returns deduplicated main/representative colors without copying or saving anything', async () => {
  const h = harness(); const colors = await h.picker.chooseColors();
  assert.deepEqual(Array.from(colors), ['#123456', '#ABCDEF', '#FF8000']);
  const decode = h.events.find(event => event[0] === 'decode')[1];
  assert.deepEqual({ ...decode.desiredSize }, { width: 256, height: 171 });
  assert.equal(decode.desiredPixelFormat, 3); assert.equal(h.handles.size, 0);
  assert.deepEqual(h.events.slice(-3).map(event => event[0]), ['release-pixels', 'release-source', 'close']);
});

test('Cancelling color selection does not open or decode any image', async () => {
  const h = harness({ cancel: true }); assert.equal(await h.picker.chooseColors(), null);
  assert.deepEqual(h.events, [['select']]); assert.equal(h.handles.size, 0);
});

test('Small images are not enlarged; thin images retain at least one pixel', async () => {
  for (const [dimensions, desiredSize] of [[{ width: 16, height: 10 }, { width: 16, height: 10 }],
    [{ width: 1, height: 10000 }, { width: 1, height: 256 }]]) {
    const h = harness({ dimensions }); await h.picker.chooseColors();
    assert.deepEqual({ ...h.events.find(event => event[0] === 'decode')[1].desiredSize }, desiredSize);
  }
});

test('Empty/oversized files and invalid/oversized dimensions are rejected before pixel allocation', async () => {
  for (const config of [{ size: 0 }, { size: 51 * 1024 * 1024 },
    { dimensions: { width: 0, height: 1 } }, { dimensions: { width: NaN, height: 1 } },
    { dimensions: { width: 20000, height: 20000 } }]) {
    const h = harness(config); await assert.rejects(h.picker.chooseColors());
    assert.equal(h.events.some(event => event[0] === 'decode'), false); assert.equal(h.handles.size, 0);
  }
});

test('Decode and color-picker errors release every acquired image/file resource', async () => {
  for (const config of [{ decodeFailure: true }, { pickerFailure: true }]) {
    const h = harness(config); await assert.rejects(h.picker.chooseColors());
    assert.equal(h.handles.size, 0);
    assert.equal(h.events.filter(event => event[0] === 'release-source').length, 1);
    assert.equal(h.events.filter(event => event[0] === 'release-pixels').length, config.decodeFailure ? 0 : 1);
  }
});

test('Available representative colors survive main-color failure; main color survives representative-color failure', async () => {
  const mainFailure = harness({ mainFailure: true });
  assert.deepEqual(Array.from(await mainFailure.picker.chooseColors()), ['#123456', '#ABCDEF', '#FF8000']);
  const topFailure = harness({ topFailure: true });
  assert.deepEqual(Array.from(await topFailure.picker.chooseColors()), ['#123456']);
});

test('Fully transparent and invalid colors cannot become theme colors; no results reports a recoverable error', async () => {
  const h = harness({ mainColor: rgb(0, 0, 0, 0), topColors: [null, rgb(NaN, 1, 2), rgb(1, 2, 3, 0)] });
  await assert.rejects(h.picker.chooseColors(), /提取颜色/); assert.equal(h.handles.size, 0);
  assert.equal(h.events.filter(event => event[0].startsWith('release-')).length, 2);
});

test('Palette conversion bounds channels, deduplicates rounding, and returns at most five valid RGB colors', () => {
  const h = harness();
  const colors = h.imageThemeColors([null, rgb(Infinity, 0, 0), rgb(0, 0, 0, NaN), rgb(-1, 255.8, 42.2),
    rgb(0, 255, 42), ...Array.from({ length: 10 }, (_, i) => rgb(i, i, i))]);
  assert.deepEqual(Array.from(colors), ['#00FF2A', '#000000', '#010101', '#020202', '#030303']);
});
