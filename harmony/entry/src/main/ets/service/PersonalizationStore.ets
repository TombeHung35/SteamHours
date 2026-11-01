import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { normalizeThemeColor, normalizeBackgroundOpacity, normalizeForegroundBlur, normalizePanelTransparency } from '../model/Appearance';

export interface Personalization {
  themeColor: string;
  backgroundPath: string;
  backgroundOpacity: number;
  foregroundBlurStrength: number;
  panelTransparency: number;
}

export class PersonalizationStore {
  private ownedPath(context: common.UIAbilityContext, path: string): boolean {
    const prefix: string = context.filesDir + '/appearance/';
    return path.startsWith(prefix) && /^background-[0-9]+-[0-9a-f]+\.jpg$/.test(path.substring(prefix.length));
  }

  private async store(context: common.UIAbilityContext): Promise<preferences.Preferences> {
    return preferences.getPreferences(context, { name: 'steam_hours' });
  }

  async read(context: common.UIAbilityContext): Promise<Personalization> {
    const result: Personalization = { themeColor: '', backgroundPath: '', backgroundOpacity: 0.22, foregroundBlurStrength: 0.4, panelTransparency: 0.25 };
    try {
      const store: preferences.Preferences = await this.store(context);
      result.themeColor = normalizeThemeColor(await store.get('themeColor', '') as string);
      result.backgroundOpacity = normalizeBackgroundOpacity(await store.get('backgroundOpacity', 0.22) as number);
      result.panelTransparency = normalizePanelTransparency(await store.get('panelTransparency', 0.25) as number);
      result.foregroundBlurStrength = normalizeForegroundBlur(await store.get('foregroundBlurStrength', 0.4) as number);
      const path: string = await store.get('backgroundPath', '') as string;
      if (this.ownedPath(context, path) && fs.accessSync(path)) result.backgroundPath = path;
    } catch (_) {}
    return result;
  }

  private async put(context: common.UIAbilityContext, key: string, value: string | number): Promise<void> {
    const store: preferences.Preferences = await this.store(context);
    const fallback: preferences.ValueType = key === 'backgroundOpacity' ? 0.22 : (key === 'foregroundBlurStrength' ? 0.4 : (key === 'panelTransparency' ? 0.25 : ''));
    const previous: preferences.ValueType = await store.get(key, fallback);
    try {
      await store.put(key, value);
      await store.flush();
    } catch (error) {
      // Restore the in-memory preference too: a later unrelated flush must not commit a failed image path.
      try { await store.put(key, previous); } catch (_) {}
      throw new Error('外观配置未能保存。');
    }
  }

  async saveColor(context: common.UIAbilityContext, value: string): Promise<string> {
    const color: string = normalizeThemeColor(value);
    if (value.trim() && !color) throw new Error('请输入 #RRGGBB 格式的主题色，例如 #4963C9。');
    await this.put(context, 'themeColor', color);
    return color;
  }

  async saveOpacity(context: common.UIAbilityContext, value: number): Promise<number> {
    const opacity: number = normalizeBackgroundOpacity(value);
    await this.put(context, 'backgroundOpacity', opacity);
    return opacity;
  }

  async saveForegroundBlur(context: common.UIAbilityContext, value: number): Promise<number> {
    const strength: number = normalizeForegroundBlur(value);
    await this.put(context, 'foregroundBlurStrength', strength);
    return strength;
  }

  async savePanelTransparency(context: common.UIAbilityContext, value: number): Promise<number> {
    const transparency: number = normalizePanelTransparency(value);
    await this.put(context, 'panelTransparency', transparency);
    return transparency;
  }

  private async discard(context: common.UIAbilityContext, path: string): Promise<void> {
    if (!this.ownedPath(context, path)) return;
    try { if (fs.accessSync(path)) await fs.unlink(path); } catch (_) {}
  }

  async removeBackground(context: common.UIAbilityContext): Promise<void> {
    const previous: Personalization = await this.read(context);
    await this.put(context, 'backgroundPath', '');
    await this.discard(context, previous.backgroundPath);
  }

  async chooseBackground(context: common.UIAbilityContext): Promise<string | null> {
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const selection: photoAccessHelper.PhotoSelectResult = await new photoAccessHelper.PhotoViewPicker().select(options);
    if (selection.photoUris.length === 0) return null;
    const previous: Personalization = await this.read(context);
    const directory: string = context.filesDir + '/appearance';
    const destination: string = directory + '/background-' + Date.now().toString() + '-' +
      Math.floor(Math.random() * 0xFFFFFFFF).toString(16) + '.jpg';
    let input: fs.File | undefined = undefined;
    let output: fs.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    let pixels: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    let committed: boolean = false;
    try {
      input = await fs.open(selection.photoUris[0], fs.OpenMode.READ_ONLY);
      const stat: fs.Stat = await fs.stat(input.fd);
      if (stat.size <= 0 || stat.size > 50 * 1024 * 1024) throw new Error('请选择小于 50 MB 的图片。');
      source = image.createImageSource(input.fd);
      const info: image.ImageInfo = await source.getImageInfo();
      if (info.size.width <= 0 || info.size.height <= 0 || info.size.width * info.size.height > 100000000) {
        throw new Error('图片尺寸过大或无效，请选择其他图片。');
      }
      const scale: number = Math.min(1, 2560 / Math.max(info.size.width, info.size.height));
      pixels = await source.createPixelMap({ desiredSize: {
        width: Math.max(1, Math.round(info.size.width * scale)),
        height: Math.max(1, Math.round(info.size.height * scale))
      } });
      packer = image.createImagePacker();
      const data: ArrayBuffer = await packer.packing(pixels, { format: 'image/jpeg', quality: 85 });
      if (!fs.accessSync(directory)) await fs.mkdir(directory);
      output = await fs.open(destination, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      let written: number = 0;
      while (written < data.byteLength) {
        const count: number = await fs.write(output.fd, data.slice(written));
        if (count <= 0) throw new Error('背景图片保存失败。');
        written += count;
      }
      await fs.close(output); output = undefined;
      await this.put(context, 'backgroundPath', destination);
      committed = true;
      await this.discard(context, previous.backgroundPath);
      return destination;
    } finally {
      if (output !== undefined) { try { await fs.close(output); } catch (_) {} }
      if (packer !== undefined) { try { await packer.release(); } catch (_) {} }
      if (pixels !== undefined) { try { await pixels.release(); } catch (_) {} }
      if (source !== undefined) { try { await source.release(); } catch (_) {} }
      if (input !== undefined) { try { await fs.close(input); } catch (_) {} }
      if (!committed) await this.discard(context, destination);
    }
  }
}
