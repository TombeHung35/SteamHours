import { PrivacyStore } from '../service/PrivacyStore';
import { LocalDataCleaner } from '../service/LocalDataCleaner';
import { privacyAccess } from '../model/PrivacyAccess';
import { PrivacyStatus } from '../model/PrivacyPolicy';
import { Personalization, PersonalizationStore } from '../service/PersonalizationStore';
import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppearanceMode } from '../model/Appearance';
import { AppearanceStore, applyAppearance, applyColorMode } from '../service/AppearanceStore';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
  private keyboardChanged: (height: number) => void = (height: number) => {
    AppStorage.setOrCreate('keyboardVisible', height > 0);
  };

  onWindowStageDestroy(): void {
    try {
      if (this.mainWindow !== null) this.mainWindow.off('keyboardHeightChange', this.keyboardChanged);
    } catch (_) {}
    this.mainWindow = null;
    AppStorage.setOrCreate('keyboardVisible', false);
    AppStorage.setOrCreate('keyboardObserved', false);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.loadMainPage(windowStage);
  }

  private async loadMainPage(windowStage: window.WindowStage): Promise<void> {
    privacyAccess.setAllowed(false);
    let privacyStatus: PrivacyStatus = await new PrivacyStore().read(this.context);
    let privacyMessage: string = '';
    if (privacyStatus === 'blocked') {
      try { await new LocalDataCleaner().clear(this.context); privacyStatus = 'pending'; }
      catch (_) { privacyMessage = '上次清除尚未完成，请在隐私页面重试；联网保持关闭。'; }
    }
    privacyAccess.setAllowed(privacyStatus === 'granted');
    AppStorage.setOrCreate('privacyStatus', privacyStatus);
    AppStorage.setOrCreate('privacyMessage', privacyMessage);
    const mode: AppearanceMode = await new AppearanceStore().read(this.context);
    // Restore before rendering so a saved day theme starts with the correct page palette.
    AppStorage.setOrCreate('appearanceMode', mode);
    const personalization: Personalization = await new PersonalizationStore().read(this.context);
    AppStorage.setOrCreate('themeColor', personalization.themeColor);
    AppStorage.setOrCreate('backgroundPath', personalization.backgroundPath);
    AppStorage.setOrCreate('backgroundOpacity', personalization.backgroundOpacity);
    AppStorage.setOrCreate('panelTransparency', personalization.panelTransparency);
    AppStorage.setOrCreate('foregroundBlurStrength', personalization.foregroundBlurStrength);
    AppStorage.setOrCreate('keyboardVisible', false);
    AppStorage.setOrCreate('keyboardObserved', false);
    // HDS reads the system color mode when its material is created. Restore it before rendering.
    applyColorMode(this.context, mode);
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        console.error('SteamHours: unable to load the main page, code: ' + error.code.toString());
        return;
      }
      applyAppearance(this.context, mode);
      try {
        this.mainWindow = windowStage.getMainWindowSync();
        this.mainWindow.on('keyboardHeightChange', this.keyboardChanged);
        AppStorage.setOrCreate('keyboardObserved', true);
      } catch (_) {
        // The page falls back to hiding the dock while an input has focus.
      }
    });
  }
}
