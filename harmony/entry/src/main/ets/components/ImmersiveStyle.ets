import { deviceInfo } from '@kit.BasicServicesKit';
import { uiMaterial, LengthMetrics } from '@kit.ArkUI';
import { AppearanceMode, AppColors, colorsFor, normalizeThemeColor } from '../model/Appearance';

// The modifier itself exists on API 12; new material APIs are called only after the capability check.
export class MaterialButtonStyle implements AttributeModifier<ButtonAttribute> {
  private material: uiMaterial.Material | undefined;
  private foreground: string;
  constructor(material: uiMaterial.Material | undefined, foreground: string) {
    this.material = material; this.foreground = foreground;
  }
  applyNormalAttribute(instance: ButtonAttribute): void {
    if (deviceInfo.sdkApiVersion >= 26 && deviceInfo.apiAvailable('26.0.0') && this.material !== undefined) instance.systemMaterial(this.material).fontColor(this.foreground);
  }
}

export class MaterialSelectStyle implements AttributeModifier<SelectAttribute> {
  private material: uiMaterial.Material | undefined;
  private menu: uiMaterial.Material | undefined;
  private foreground: string;
  constructor(material: uiMaterial.Material | undefined, menu: uiMaterial.Material | undefined, foreground: string) {
    this.material = material; this.menu = menu; this.foreground = foreground;
  }
  applyNormalAttribute(instance: SelectAttribute): void {
    if (deviceInfo.sdkApiVersion >= 26 && deviceInfo.apiAvailable('26.0.0') && this.material !== undefined && this.menu !== undefined) {
      instance.systemMaterial(this.material).menuSystemMaterial(this.menu).optionFontColor(this.foreground);
    }
  }
}

export class MaterialToggleStyle implements AttributeModifier<ToggleAttribute> {
  private material: uiMaterial.Material | undefined;
  constructor(material: uiMaterial.Material | undefined) { this.material = material; }
  applyNormalAttribute(instance: ToggleAttribute): void {
    if (deviceInfo.sdkApiVersion >= 26 && deviceInfo.apiAvailable('26.0.0') && this.material !== undefined) instance.systemMaterial(this.material);
  }
}

// One native tab defaults to a compact floating bar, but this tab contains three actions.
export function floatingActionBarWidth(viewportWidth: number): number {
  const viewport: number = Number.isFinite(viewportWidth) && viewportWidth > 0 ? viewportWidth : 360;
  return Math.max(1, viewport - 40);
}

export class MaterialTabsStyle implements AttributeModifier<TabsAttribute> {
  private material: uiMaterial.ImmersiveMaterial | undefined;
  private visible: boolean;
  private width: number;
  constructor(material: uiMaterial.ImmersiveMaterial | undefined, visible: boolean, viewportWidth: number = 360) {
    this.material = material; this.visible = visible; this.width = floatingActionBarWidth(viewportWidth);
  }
  applyNormalAttribute(instance: TabsAttribute): void {
    if (deviceInfo.sdkApiVersion >= 26 && deviceInfo.apiAvailable('26.0.0') && this.material !== undefined) {
      // An undefined floating style restores the non-floating bar when the keyboard hides it.
      if (this.visible) {
        instance.barFloatingStyle({
          barWidth: { smallBarWidth: this.width, mediumBarWidth: this.width, largeBarWidth: this.width },
          barSideMargin: 20, barBottomMargin: 16,
          // No one-vp mask strip: the floating capsule keeps its own official material.
          maskColor: '#00000000', maskHeight: 0,
          systemMaterial: this.material
        });
      } else {
        instance.barFloatingStyle(undefined);
      }
      // Apply after the floating style so its native defaults cannot reintroduce a divider.
      instance.divider({ strokeWidth: 0, color: '#00000000', startMargin: 0, endMargin: 0 });
    }
  }
}

export class ImmersiveTheme {
  readonly enabled: boolean;
  readonly button: MaterialButtonStyle;
  readonly primary: MaterialButtonStyle;
  readonly bottomButton: MaterialButtonStyle;
  readonly bottomPrimary: MaterialButtonStyle;
  readonly danger: MaterialButtonStyle;
  readonly select: MaterialSelectStyle;
  readonly toggle: MaterialToggleStyle;
  private title: uiMaterial.Material | undefined = undefined;
  private bottom: uiMaterial.ImmersiveMaterial | undefined = undefined;
  private stableTitleOptions: NavigationTitleOptions | undefined = undefined;

  private colors: AppColors;

  constructor(mode: AppearanceMode = 'night', themeColor: string = '') {
    this.colors = colorsFor(mode, themeColor);
    const day: boolean = mode === 'day';
    let neutral: uiMaterial.Material | undefined = undefined;
    let primary: uiMaterial.Material | undefined = undefined;
    let bottomNeutral: uiMaterial.Material | undefined = undefined;
    let bottomPrimary: uiMaterial.Material | undefined = undefined;
    let danger: uiMaterial.Material | undefined = undefined;
    let menu: uiMaterial.Material | undefined = undefined;
    let enabled: boolean = false;
    try {
      if (deviceInfo.sdkApiVersion >= 26 && deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported()) {
        neutral = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN, materialColor: day ? '#60E1EAF8' : '#40263453',
          interactive: true, lightEffect: { color: day ? '#FFFFFF' : '#CBD6FF' }
        });
        primary = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR, materialColor: '#E0' + this.colors.primary.substring(1),
          interactive: true, lightEffect: { color: this.colors.primary }
        });
        // Floating actions must not cast per-button rectangular shadows beneath the capsule.
        bottomNeutral = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN, materialColor: day ? '#60E1EAF8' : '#40263453',
          interactive: true, applyShadow: false, lightEffect: { color: day ? '#FFFFFF' : '#CBD6FF' }
        });
        bottomPrimary = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR, materialColor: '#E0' + this.colors.primary.substring(1),
          interactive: true, applyShadow: false, lightEffect: { color: this.colors.primary }
        });
        danger = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN, materialColor: day ? '#80F9E5E8' : '#6037222F',
          interactive: true, lightEffect: { color: day ? '#FFFFFF' : '#FFC5C5' }
        });
        menu = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THICK, materialColor: day ? '#A0EDF2FA' : '#60263453'
        });
        this.bottom = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR, materialColor: day ? '#60EDF2FA' : '#60263453',
          interactive: true, applyShadow: false, lightEffect: { color: day ? '#FFFFFF' : '#CBD6FF' }
        });
        this.title = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN, materialColor: day ? '#60F3F6FC' : '#400B1020', applyShadow: false,
          lightEffect: { color: day ? '#FFFFFF' : '#CBD6FF' }
        });
        enabled = true;
      }
    } catch (_) {
      // Optional visual capabilities must never prevent the library or login page from opening.
      neutral = undefined; primary = undefined; bottomNeutral = undefined; bottomPrimary = undefined; danger = undefined; menu = undefined;
      this.title = undefined; this.bottom = undefined;
    }
    this.enabled = enabled;
    this.button = new MaterialButtonStyle(neutral, this.colors.body);
    this.primary = new MaterialButtonStyle(primary, this.colors.primaryText);
    this.bottomButton = new MaterialButtonStyle(bottomNeutral, this.colors.body);
    this.bottomPrimary = new MaterialButtonStyle(bottomPrimary, this.colors.primaryText);
    this.danger = new MaterialButtonStyle(danger, this.colors.dangerText);
    this.select = new MaterialSelectStyle(neutral, menu, this.colors.body);
    this.toggle = new MaterialToggleStyle(neutral);
  }

  tabsStyle(visible: boolean, viewportWidth: number = 360): MaterialTabsStyle {
    return new MaterialTabsStyle(this.bottom, visible, viewportWidth);
  }

  titleOptions(): NavigationTitleOptions {
    // Keep official scroll blur and its transition metrics stable, without a status-bar-edge shadow.
    if (this.stableTitleOptions === undefined) {
      this.stableTitleOptions = this.enabled ?
        { backgroundColor: '#00000000', barStyle: BarStyle.STACK, systemMaterial: this.title,
          scrollEffectOptions: { scrollEffectType: ScrollEffectType.GRADUAL_BLUR,
            blurEffectiveStartOffset: LengthMetrics.vp(0), blurEffectiveEndOffset: LengthMetrics.vp(64) } } :
        { backgroundColor: this.colors.background, barStyle: BarStyle.STANDARD };
    }
    return this.stableTitleOptions;
  }
}

// Reuse a small set of system materials instead of creating GPU effects for every game row.
const nightTheme: ImmersiveTheme = new ImmersiveTheme('night');
let dayTheme: ImmersiveTheme | undefined = undefined;

let customDayTheme: ImmersiveTheme | undefined = undefined;
let customNightTheme: ImmersiveTheme | undefined = undefined;
let customDayColor: string = '';
let customNightColor: string = '';

export function immersiveFor(mode: AppearanceMode, themeColor: string = ''): ImmersiveTheme {
  const color: string = normalizeThemeColor(themeColor);
  // Keep only the most recent custom palette per mode; slider/input previews never allocate materials.
  if (color) {
    if (mode === 'day') {
      if (customDayTheme === undefined || customDayColor !== color) {
        customDayTheme = new ImmersiveTheme(mode, color); customDayColor = color;
      }
      return customDayTheme;
    }
    if (customNightTheme === undefined || customNightColor !== color) {
      customNightTheme = new ImmersiveTheme(mode, color); customNightColor = color;
    }
    return customNightTheme;
  }
  if (mode === 'day') {
    if (dayTheme === undefined) dayTheme = new ImmersiveTheme('day');
    return dayTheme;
  }
  return nightTheme;
}
