import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { window } from '@kit.ArkUI';
import { AppearanceMode, AppColors, colorsFor, normalizeAppearance } from '../model/Appearance';

export class AppearanceStore {
  async read(context: common.UIAbilityContext): Promise<AppearanceMode> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, { name: 'steam_hours' });
      return normalizeAppearance(await store.get('appearanceMode', 'night') as string);
    } catch (_) {
      return 'night';
    }
  }

  async save(context: common.UIAbilityContext, mode: AppearanceMode): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(context, { name: 'steam_hours' });
    await store.put('appearanceMode', mode);
    await store.flush();
  }
}

// Apply before HDS material creation; this does not depend on a loaded window.
export function applyColorMode(context: common.UIAbilityContext, mode: AppearanceMode): void {
  try {
    context.getApplicationContext().setColorMode(mode === 'day' ?
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  } catch (_) {
    console.warn('SteamHours: system color mode could not be applied.');
  }
}

// Call only after loadContent succeeds. Appearance errors must not disrupt library or login.
export async function applyAppearance(context: common.UIAbilityContext, mode: AppearanceMode): Promise<void> {
  const colors: AppColors = colorsFor(mode);
  applyColorMode(context, mode);
  try {
    const mainWindow: window.Window = await window.getLastWindow(context);
    // Component-level drawing expansion keeps interactive content in the native safe area.
    let transparentBars: boolean = false;
    try {
      await mainWindow.setWindowLayoutFullScreen(false);
      transparentBars = true;
    } catch (_) {}
    await mainWindow.setWindowSystemBarProperties({
      statusBarColor: transparentBars ? '#00000000' : colors.background, statusBarContentColor: colors.text,
      navigationBarColor: transparentBars ? '#00000000' : colors.background, navigationBarContentColor: colors.text
    });
    try { mainWindow.setWindowBackgroundColor(colors.background); } catch (_) {}
  } catch (_) {
    console.warn('SteamHours: system bar colors could not be applied.');
  }
}
