import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { effectKit } from '@kit.ArkGraphics2D';
import { imageThemeColors } from '../model/ThemeColors';

export class ImageThemePicker {
  // Return a temporary palette only. Applying a color uses PersonalizationStore.saveColor.
  async chooseColors(): Promise<Array<string> | null> {
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const selection: photoAccessHelper.PhotoSelectResult = await new photoAccessHelper.PhotoViewPicker().select(options);
    if (selection.photoUris.length === 0) return null;
    let input: fs.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    let pixels: image.PixelMap | undefined = undefined;
    try {
      input = await fs.open(selection.photoUris[0], fs.OpenMode.READ_ONLY);
      const stat: fs.Stat = await fs.stat(input.fd);
      if (stat.size <= 0 || stat.size > 50 * 1024 * 1024) throw new Error('请选择小于 50 MB 的图片。');
      source = image.createImageSource(input.fd);
      const info: image.ImageInfo = await source.getImageInfo();
      const width: number = info.size.width;
      const height: number = info.size.height;
      if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0 || width * height > 100000000) {
        throw new Error('图片尺寸过大或无效，请选择其他图片。');
      }
      const scale: number = Math.min(1, 256 / Math.max(width, height));
      pixels = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888, desiredSize: {
        width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale))
      } });
      const picker: effectKit.ColorPicker = await effectKit.createColorPicker(pixels);
      const colors: Array<effectKit.Color | null> = [];
      try { colors.push(await picker.getMainColor()); } catch (_) {}
      try { colors.push(...picker.getTopProportionColors(4)); } catch (_) {}
      const palette: Array<string> = imageThemeColors(colors);
      if (palette.length === 0) throw new Error('未能从图片提取颜色，请换一张图片。');
      return palette;
    } finally {
      if (pixels !== undefined) { try { await pixels.release(); } catch (_) {} }
      if (source !== undefined) { try { await source.release(); } catch (_) {} }
      if (input !== undefined) { try { await fs.close(input); } catch (_) {} }
    }
  }
}
