export type AppearanceMode = 'day' | 'night';

export interface AppColors {
  background: string;
  surface: string;
  settings: string;
  stats: string;
  detail: string;
  input: string;
  control: string;
  secondaryButton: string;
  headerButton: string;
  primary: string;
  primaryText: string;
  switchTrack: string;
  progress: string;
  progressTrack: string;
  text: string;
  body: string;
  secondary: string;
  placeholder: string;
  softText: string;
  buttonText: string;
  dangerText: string;
  dangerBackground: string;
  success: string;
  accent: string;
  iconText: string;
  statsSubtitle: string;
  notice: string;
  muted: string;
  edge: string;
  shine: string;
  shadow: string;
  rowShadow: string;
  glowBlue: string;
  glowViolet: string;
  heroEnd: string;
  dock: string;
  selectedSurface: string;
}

export const NIGHT_COLORS: AppColors = {
  background: '#0B1020',
  surface: '#151E32',
  settings: '#182238',
  stats: '#233254',
  detail: '#222E4D',
  input: '#0B1020',
  control: '#263453',
  secondaryButton: '#334164',
  headerButton: '#243250',
  primary: '#91A7FF',
  primaryText: '#10182D',
  switchTrack: '#91A7FF',
  progress: '#8EA5FF',
  progressTrack: '#29344D',
  text: '#F3F5FF',
  body: '#D8E0F2',
  secondary: '#B0BAD0',
  placeholder: '#8B95AB',
  softText: '#CBD6FF',
  buttonText: '#FFFFFF',
  dangerText: '#FFC5C5',
  dangerBackground: '#37222F',
  success: '#A6E0CA',
  accent: '#A6B7FF',
  iconText: '#BBC9FF',
  statsSubtitle: '#BCCAFF',
  notice: '#A5AFC5',
  muted: '#8996B1',
  edge: '#33456688',
  shine: '#667F9DDC',
  shadow: '#60000000',
  rowShadow: '#25000000',
  glowBlue: '#284A70DE',
  glowViolet: '#204F3CA6',
  heroEnd: '#1B2643',
  dock: '#EA182238',
  selectedSurface: '#202D4A',
};

export const DAY_COLORS: AppColors = {
  background: '#F3F6FC',
  surface: '#FFFFFF',
  settings: '#E9EFF8',
  stats: '#DCE7FA',
  detail: '#E4EBF7',
  input: '#EAF0F8',
  control: '#E2EAF8',
  secondaryButton: '#DBE5F7',
  headerButton: '#E0E8F6',
  primary: '#4963C9',
  primaryText: '#FFFFFF',
  switchTrack: '#4F65C9',
  progress: '#546CCB',
  progressTrack: '#DCE4F1',
  text: '#18243B',
  body: '#334563',
  secondary: '#53647F',
  placeholder: '#596984',
  softText: '#40578C',
  buttonText: '#334563',
  dangerText: '#963242',
  dangerBackground: '#F9E5E8',
  success: '#237452',
  accent: '#3A55AA',
  iconText: '#425EAC',
  statsSubtitle: '#40578C',
  notice: '#5B6C85',
  muted: '#5F718D',
  edge: '#D0DBEF',
  shine: '#CCFFFFFF',
  shadow: '#18243B64',
  rowShadow: '#102A4378',
  glowBlue: '#245C8EFF',
  glowViolet: '#187864D4',
  heroEnd: '#EDF2FC',
  dock: '#F2F5F8FF',
  selectedSurface: '#EEF3FF',
};

export function normalizeAppearance(value: string): AppearanceMode {
  return value === 'day' ? 'day' : 'night';
}

export function normalizeThemeColor(value: string): string {
  const color: string = value.trim().toUpperCase();
  return /^#[0-9A-F]{6}$/.test(color) ? color : '';
}

export function normalizeForegroundBlur(value: number): number {
  return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0.4;
}

export function normalizeBackgroundOpacity(value: number): number {
  return Number.isFinite(value) ? Math.min(1, Math.max(0.08, value)) : 0.22;
}

// Transparency affects painted card surfaces only, never the opacity of their children.
export function normalizePanelTransparency(value: number): number {
  return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0.25;
}

export function transparentPanelColor(color: string, transparency: number): string {
  if (!/^#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.test(color)) return color;
  const baseAlpha: number = color.length === 9 ? parseInt(color.substring(1, 3), 16) : 255;
  const alpha: number = Math.round(baseAlpha * (1 - normalizePanelTransparency(transparency)));
  const rgb: string = color.substring(color.length - 6).toUpperCase();
  return '#' + alpha.toString(16).padStart(2, '0').toUpperCase() + rgb;
}

function luminance(color: string): number {
  const channels: number[] = [1, 3, 5].map((offset: number) => {
    const value: number = parseInt(color.substring(offset, offset + 2), 16) / 255;
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
  });
  return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
}

export function colorContrast(a: string, b: string): number {
  const first: number = luminance(a); const second: number = luminance(b);
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
}

function readableAccent(color: string, background: string, day: boolean): string {
  let result: string = color;
  for (let step: number = 0; step < 24 && colorContrast(result, background) < 4.5; step++) {
    result = '#' + [1, 3, 5].map((offset: number) => {
      const channel: number = parseInt(result.substring(offset, offset + 2), 16);
      return Math.round(channel * 0.8 + (day ? 0 : 255) * 0.2).toString(16).padStart(2, '0');
    }).join('').toUpperCase();
  }
  return result;
}

export function colorsFor(mode: AppearanceMode, themeColor: string = ''): AppColors {
  const base: AppColors = mode === 'day' ? DAY_COLORS : NIGHT_COLORS;
  const color: string = normalizeThemeColor(themeColor);
  if (!color) return base;
  const result: AppColors = {
    background: base.background,
    surface: base.surface,
    settings: base.settings,
    stats: base.stats,
    detail: base.detail,
    input: base.input,
    control: base.control,
    secondaryButton: base.secondaryButton,
    headerButton: base.headerButton,
    primary: base.primary,
    primaryText: base.primaryText,
    switchTrack: base.switchTrack,
    progress: base.progress,
    progressTrack: base.progressTrack,
    text: base.text,
    body: base.body,
    secondary: base.secondary,
    placeholder: base.placeholder,
    softText: base.softText,
    buttonText: base.buttonText,
    dangerText: base.dangerText,
    dangerBackground: base.dangerBackground,
    success: base.success,
    accent: base.accent,
    iconText: base.iconText,
    statsSubtitle: base.statsSubtitle,
    notice: base.notice,
    muted: base.muted,
    edge: base.edge,
    shine: base.shine,
    shadow: base.shadow,
    rowShadow: base.rowShadow,
    glowBlue: base.glowBlue,
    glowViolet: base.glowViolet,
    heroEnd: base.heroEnd,
    dock: base.dock,
    selectedSurface: base.selectedSurface,
  };
  result.primary = color;
  result.primaryText = colorContrast('#FFFFFF', color) >= colorContrast('#000000', color) ? '#FFFFFF' : '#000000';
  result.switchTrack = color; result.progress = color;
  result.accent = readableAccent(color, base.stats, mode === 'day');
  result.iconText = readableAccent(color, base.control, mode === 'day');
  result.glowBlue = '#28' + color.substring(1);
  result.glowViolet = '#18' + color.substring(1);
  return result;
}
