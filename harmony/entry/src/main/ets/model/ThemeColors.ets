// Color components returned by the official effectKit ColorPicker.
export interface ImageThemeColor {
  red: number;
  green: number;
  blue: number;
  alpha: number;
}

export function imageThemeColors(colors: Array<ImageThemeColor | null>): Array<string> {
  const result: Array<string> = [];
  for (const color of colors) {
    if (color === null || !Number.isFinite(color.alpha) || color.alpha <= 0 ||
      !Number.isFinite(color.red) || !Number.isFinite(color.green) || !Number.isFinite(color.blue)) continue;
    const channels: Array<number> = [color.red, color.green, color.blue];
    let hex: string = '#';
    for (const channel of channels) {
      hex += Math.max(0, Math.min(255, Math.round(channel))).toString(16).padStart(2, '0').toUpperCase();
    }
    if (!result.includes(hex)) result.push(hex);
    if (result.length === 5) break;
  }
  return result;
}
