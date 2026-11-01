import { ArtworkApi } from '../service/ArtworkApi';
import { pasteboard } from '@kit.BasicServicesKit';
import { privacyAccess } from '../model/PrivacyAccess';
import { PrivacyStatus, PrivacySection, PRIVACY_SECTIONS, POLICY_REVISION, DEVELOPER_NAME, SUPPORT_URL, APP_VERSION } from '../model/PrivacyPolicy';
import { PrivacyStore } from '../service/PrivacyStore';
import { LocalDataCleaner } from '../service/LocalDataCleaner';
import { BottomBarAutoHide } from '../model/BottomBarAutoHide';
import { bottomBarMotionAvailable, BottomBarMotion } from '../components/BottomBarMotion';
import { LibraryStore, normalizeLibrarySort } from '../service/LibraryStore';
import { steamArtworkUrl, ArtworkMap } from '../model/SteamImages';
import { AchievementsApi } from '../service/AchievementsApi';
import { Achievement, AchievementResponse } from '../model/AchievementData';
import { StatusBarScrollStyle } from '../components/StatusBarScrollStyle';
import { AccountNavigation } from '../model/AccountNavigation';
import { CustomTheme, ThemeControl } from '@kit.ArkUI';
import { ImageThemePicker } from '../service/ImageThemePicker';
import { PersonalizationStore } from '../service/PersonalizationStore';
import { AppearanceMode, AppColors, colorsFor, normalizeThemeColor, normalizeForegroundBlur, normalizePanelTransparency, transparentPanelColor } from '../model/Appearance';
import { webview } from '@kit.ArkWeb';
import { FamilyLogin } from '../components/FamilyLogin';
import { ImmersiveTheme, immersiveFor } from '../components/ImmersiveStyle';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Game, LibraryResponse, demoLibrary, emptyLibrary, formatHours } from '../model/Library';
import { LibraryApi } from '../service/LibraryApi';
import { KeyStore } from '../service/KeyStore';
import { AppearanceStore, applyAppearance } from '../service/AppearanceStore';
import { validateApiKey } from '../model/SteamData';

type MainPage = 'library' | 'accounts' | 'settings' | 'privacy' | 'about' | 'support';

@Entry
@Component
struct Index {
  @StorageLink('privacyStatus') private privacyStatus: PrivacyStatus = 'pending';
  @StorageLink('privacyMessage') private privacyMessage: string = '';
  @State private privacyBusy: boolean = false;
  @State private librarySaving: boolean = false;
  @State private infoReturnPage: MainPage = 'settings';
  @State private supportMessage: string = '';
  private dataGeneration: number = 0;
  private privacyStore: PrivacyStore = new PrivacyStore();
  private localDataCleaner: LocalDataCleaner = new LocalDataCleaner();

  @State private library: LibraryResponse = emptyLibrary();
  @State private libraryMessage: string = '';
  @State private artworkUrls: ArtworkMap = {};
  private artworkApi: ArtworkApi = new ArtworkApi();
  private artworkAttempted: Set<number> = new Set();
  private artworkLoading: boolean = false;
  @State private artworkFailures: Record<string, number> = {};
  @State private achievementAppId: number = 0;
  @State private achievementData: AchievementResponse | null = null;
  @State private achievementError: string = '';
  @State private achievementLoading: boolean = false;
  @State private achievementLimit: number = 30;
  private achievementRequest: number = 0;
  private achievementsApi: AchievementsApi = new AchievementsApi();
  private libraryStore: LibraryStore = new LibraryStore();
  private sortWrites: Promise<void> = Promise.resolve();
  @State private account: string = '';
  @State private apiKey: string = '';
  @State private familyToken: string = '';
  @State private includeFamily: boolean = false;
  @State private sourceFilter: number = 0;
  @State private rememberKey: boolean = true;
  @State private settingsReady: boolean = false;
  @State private savingSettings: boolean = false;
  @State private settingsMessage: string = '';
  @State private search: string = '';
  @State private sort: number = 0;
  @State private onlyRecent: boolean = false;
  @State private mainPage: MainPage = 'library';
  @State private loading: boolean = false;
  @State private errorText: string = '';
  @State private selected: Game | null = null;
  @State private visibleLimit: number = 60;
  @State @Watch('inputVisibilityChanged') private editingInput: boolean = false;
  @State private bottomBarScrollHidden: boolean = false;
  @State private bottomBarMotionSupported: boolean = bottomBarMotionAvailable();
  private bottomBarTracker: BottomBarAutoHide = new BottomBarAutoHide();
  private bottomBarMotion: BottomBarMotion = new BottomBarMotion();
  private tabsController: TabsController = new TabsController();
  private bottomBarMounted: boolean = false;
  @StorageLink('keyboardVisible') @Watch('inputVisibilityChanged') private keyboardVisible: boolean = false;
  @StorageLink('keyboardObserved') @Watch('inputVisibilityChanged') private keyboardObserved: boolean = false;
  private scroller: Scroller = new Scroller();
  private statusBarScrollStyle: StatusBarScrollStyle = new StatusBarScrollStyle();
  @State private pageStack: NavPathStack = new NavPathStack();
  private navigation: AccountNavigation = new AccountNavigation(this.pageStack);
  @State private viewportWidth: number = 360;
  @StorageLink('appearanceMode') private colorMode: AppearanceMode = 'night';

  @StorageLink('themeColor') private themeColor: string = '';
  @StorageLink('backgroundPath') private backgroundPath: string = '';
  @StorageLink('backgroundOpacity') private backgroundOpacity: number = 0.22;
  @StorageLink('panelTransparency') private panelTransparency: number = 0.25;
  @StorageLink('foregroundBlurStrength') private foregroundBlurStrength: number = 0.4;
  @State private imageThemePalette: Array<string> = [];
  @State private imageThemeMessage: string = '';
  private imageThemePicker: ImageThemePicker = new ImageThemePicker();
  @State private themeColorDraft: string = '';
  @State private personalizationBusy: boolean = false;
  private personalizationStore: PersonalizationStore = new PersonalizationStore();

  private colors(): AppColors { return colorsFor(this.colorMode, this.themeColor); }
  private panelColor(color: string): string { return transparentPanelColor(color, this.panelTransparency); }
  private customTheme(): CustomTheme {
    return { colors: { brand: this.colors().primary, iconEmphasize: this.colors().primary,
        backgroundEmphasize: this.colors().primary, fontEmphasize: this.colors().accent,
        fontPrimary: this.colors().text, fontSecondary: this.colors().body, fontTertiary: this.colors().secondary } };
  }
  private theme(): ImmersiveTheme { return immersiveFor(this.colorMode, this.themeColor); }
  @State private appearanceSaving: boolean = false;
  @State private appearanceMessage: string = '';
  private appearanceStore: AppearanceStore = new AppearanceStore();
  private api: LibraryApi = new LibraryApi();
  private keyStore: KeyStore = new KeyStore();
  private familyStore: KeyStore = new KeyStore('steam_hours_family_token_v1');
  private prefs: preferences.Preferences | null = null;

  aboutToAppear(): void {
    this.themeColorDraft = this.themeColor;
    this.restoreSettings();
  }

  onBackPress(): boolean {
    if (this.isInfoPage()) { this.switchPage(this.infoReturnPage); return true; }
    if (this.navigation.back()) { this.editingInput = false; this.resetBottomBar(); return true; }
    if (this.selected !== null) { this.selected = null; return true; }
    if (this.mainPage !== 'library') { this.openLibrary(); return true; }
    return false;
  }

  private hasConsent(): boolean { return this.privacyStatus === 'granted' && !this.privacyBusy; }
  private isInfoPage(): boolean { return this.mainPage === 'privacy' || this.mainPage === 'about' || this.mainPage === 'support'; }
  private isSettingsPage(): boolean { return this.mainPage !== 'library' && this.mainPage !== 'accounts'; }
  private openInfo(page: MainPage): void {
    if (!this.isInfoPage()) this.infoReturnPage = this.mainPage;
    this.switchPage(page);
  }
  private requireConsent(): boolean {
    if (this.hasConsent()) return true;
    this.openInfo('privacy'); this.privacyMessage = '启用 Steam 查询前，请阅读并同意隐私政策。'; return false;
  }
  private async acceptPrivacy(): Promise<void> {
    if (this.privacyBusy || this.privacyStatus === 'blocked' || this.privacyStatus === 'granted') return;
    this.privacyBusy = true; this.privacyMessage = '';
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.privacyStore.choose(context, true);
      privacyAccess.setAllowed(true); this.privacyStatus = 'granted'; this.mainPage = 'accounts';
      this.privacyBusy = false; this.settingsReady = false;
      await this.restoreSettings();
    } catch (_) { privacyAccess.setAllowed(false); this.privacyStatus = 'pending'; this.privacyMessage = '隐私选择未能保存，联网未启用。请重试。'; }
    finally { this.privacyBusy = false; this.returnToTop(); }
  }
  private async declinePrivacy(): Promise<void> {
    if (this.privacyBusy || this.privacyStatus === 'blocked') return;
    this.privacyBusy = true; privacyAccess.setAllowed(false);
    try { await this.privacyStore.choose(this.getUIContext().getHostContext() as common.UIAbilityContext, false); this.privacyMessage = ''; }
    catch (_) { this.privacyMessage = '本次离线选择已生效，但未能保存；下次打开可能再次提示。'; }
    finally {
      this.privacyStatus = 'declined'; this.privacyBusy = false; this.settingsReady = true;
      this.library = demoLibrary(); this.openLibrary();
    }
  }
  private canClearData(): boolean {
    return this.settingsReady && !this.privacyBusy && !this.savingSettings && !this.personalizationBusy && !this.appearanceSaving && !this.librarySaving;
  }
  private confirmClearData(withdraw: boolean = false): void {
    if (!this.canClearData()) return;
    try { ThemeControl.setDefaultTheme(this.customTheme()); } catch (_) {}
    this.getUIContext().showAlertDialog({
      title: withdraw ? '撤回同意并清除数据' : '清除全部本地数据',
      message: '将删除此应用的 API 密钥、家庭授权及网页登录数据、游戏库缓存、排序、外观偏好、背景副本、缓存及隐私选择，恢复初始状态。相册原图和 Steam 资料保留。此操作无法撤销。',
      autoCancel: true,
      backgroundColor: this.colors().surface, backgroundBlurStyle: BlurStyle.NONE,
      primaryButton: { value: '取消', fontColor: this.colors().accent, action: (): void => {} },
      secondaryButton: { value: withdraw ? '撤回并清除' : '确认清除', fontColor: this.colors().dangerText, action: (): void => { this.clearAllLocalData(); } }
    });
  }
  private resetLocalMemory(): void {
    this.account = ''; this.apiKey = ''; this.prefs = null; this.rememberKey = true;
    this.library = emptyLibrary(); this.libraryMessage = ''; this.errorText = ''; this.settingsMessage = '';
    this.selected = null; this.artworkFailures = {}; this.artworkUrls = {}; this.artworkAttempted.clear(); this.artworkApi.clearCache(); this.artworkLoading = false; this.search = ''; this.sort = 0; this.onlyRecent = false; this.sourceFilter = 0; this.visibleLimit = 60;
    this.familyToken = ''; this.includeFamily = false; this.navigation.returnLibrary();
    this.api.clearCache(); this.achievementsApi.clearCache(); this.resetAchievements();
    this.loading = false; this.librarySaving = false;
    this.colorMode = 'night'; this.themeColor = ''; this.themeColorDraft = ''; this.backgroundPath = '';
    this.backgroundOpacity = 0.22; this.panelTransparency = 0.25; this.foregroundBlurStrength = 0.4;
    this.imageThemePalette = []; this.imageThemeMessage = ''; this.appearanceMessage = ''; this.supportMessage = '';
    this.editingInput = false; this.resetBottomBar();
  }
  private async clearAllLocalData(): Promise<void> {
    if (!this.canClearData()) { this.privacyMessage = '配置正在保存，请稍后重试清除。'; return; }
    this.privacyBusy = true; this.settingsReady = false; this.dataGeneration++;
    this.privacyStatus = 'blocked'; privacyAccess.setAllowed(false);
    this.api.clearCache(); this.achievementsApi.clearCache(); this.resetAchievements();
    this.library = emptyLibrary(); this.apiKey = ''; this.account = ''; this.familyToken = ''; this.includeFamily = false;
    this.navigation.returnLibrary(); this.selected = null; this.loading = false;
    this.artworkApi.clearCache(); this.artworkAttempted.clear(); this.artworkUrls = {}; this.artworkLoading = false;
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await this.sortWrites;
      await this.localDataCleaner.clear(context);
      this.resetLocalMemory(); await applyAppearance(context, 'night');
      this.privacyStatus = 'pending'; this.privacyMessage = '已清除全部本地数据。你可以重新选择启用查询或离线使用。';
    } catch (error) { this.privacyMessage = (error as Error).message || '清除未完成，联网已关闭，请重试。'; }
    finally { this.privacyBusy = false; this.settingsReady = true; this.mainPage = 'privacy'; this.returnToTop(); }
  }
  private async copySupport(feedback: boolean = false): Promise<void> {
    const text: string = feedback ? '应用：游戏时光\n版本：' + APP_VERSION + '\n系统版本：请填写\n问题与复现步骤：\n预期结果：\n实际结果：\n请勿包含 API 密钥、密码或含凭据截图。' : SUPPORT_URL;
    try { await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)); this.supportMessage = feedback ? '反馈模板已复制。' : '反馈地址已复制。'; }
    catch (_) { this.supportMessage = '未能复制，请重试。'; }
  }
  private async openFeedback(): Promise<void> {
    try {
      await (this.getUIContext().getHostContext() as common.UIAbilityContext).startAbility({
        action: 'ohos.want.action.viewData', uri: SUPPORT_URL
      });
      this.supportMessage = '已尝试打开 GitHub，提交内容由你确认。';
    } catch (_) { this.supportMessage = '无法打开浏览器，请复制反馈地址后访问。'; }
  }

  private keyboardAllowsBottomBar(): boolean { return !(this.keyboardObserved ? this.keyboardVisible : this.editingInput); }
  private bottomBarVisible(): boolean { return this.keyboardAllowsBottomBar() && !this.bottomBarScrollHidden; }
  private bottomBarLayoutVisible(): boolean { return this.keyboardAllowsBottomBar() && (this.bottomBarMotionSupported || !this.bottomBarScrollHidden); }
  private currentScrollOffset(): number {
    try { return this.scroller.currentOffset().yOffset; } catch (_) { return 0; }
  }
  private syncBottomBar(animated: boolean = true): void {
    if (!this.bottomBarMounted || !this.bottomBarMotionSupported) return;
    if (!this.bottomBarMotion.move(this.tabsController, this.getUIContext(), this.bottomBarVisible(), animated && this.keyboardAllowsBottomBar())) {
      this.bottomBarMotionSupported = false;
    }
  }
  private resetBottomBar(): void {
    this.bottomBarTracker.reset(this.currentScrollOffset()); this.bottomBarScrollHidden = false;
    this.syncBottomBar();
  }
  private inputVisibilityChanged(): void { this.resetBottomBar(); }
  private contentDidScroll(state: ScrollState): void {
    let offset: number; let atEnd: boolean;
    try { offset = this.scroller.currentOffset().yOffset; atEnd = this.scroller.isAtEnd(); } catch (_) { return; }
    const hidden: boolean = this.bottomBarTracker.update(offset, this.keyboardAllowsBottomBar() && !this.busy(), state !== ScrollState.Idle, atEnd);
    if (hidden === this.bottomBarScrollHidden) return;
    this.bottomBarScrollHidden = hidden; this.syncBottomBar();
  }

  private returnToTop(): void {
    this.resetBottomBar();
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: true });
  }

  private switchPage(page: MainPage): void {
    if (this.mainPage === page) return;
    this.mainPage = page; this.selected = null; this.editingInput = false;
    this.returnToTop();
  }

  private openSettings(): void { this.switchPage('settings'); }
  private openAccounts(): void { this.switchPage('accounts'); }

  private openLibrary(): void {
    this.navigation.returnLibrary(); this.mainPage = 'library';
    this.selected = null; this.editingInput = false; this.returnToTop();
  }

  private readOrOpenLibrary(): void {
    if (this.mainPage !== 'library') this.openLibrary();
    else this.loadLibrary();
  }

  private requireAccounts(): void { this.openAccounts(); }

  private closeAccountPage(): void {
    this.editingInput = false;
    this.navigation.back();
  }
  private async saveThemeColor(value: string): Promise<void> {
    if (this.personalizationBusy || !this.settingsReady) return;
    this.personalizationBusy = true; this.appearanceMessage = '';
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.themeColor = await this.personalizationStore.saveColor(context, value);
      this.themeColorDraft = this.themeColor;
      this.appearanceMessage = this.themeColor ? '主题色已保存。' : '已恢复默认主题色。';
    } catch (_) {
      this.appearanceMessage = value.trim() && !normalizeThemeColor(value) ?
      '请输入 #RRGGBB 格式的颜色，例如 #4963C9。' : '主题色未能保存，请重试。';
    } finally { this.personalizationBusy = false; }
  }

  private async chooseImageTheme(): Promise<void> {
    if (this.personalizationBusy || !this.settingsReady) return;
    this.editingInput = false;
    this.personalizationBusy = true; this.imageThemeMessage = '正在提取图片颜色…';
    try {
      const palette: Array<string> | null = await this.imageThemePicker.chooseColors();
      if (palette === null) { this.imageThemeMessage = '已取消，当前主题色保留。'; return; }
      this.imageThemePalette = palette;
      this.imageThemeMessage = '点击下方颜色应用为主题色。';
    } catch (_) {
      this.imageThemeMessage = '未能提取颜色。请选择小于 50 MB 的普通图片后重试，当前主题色保留。';
    } finally { this.personalizationBusy = false; }
  }

  private foregroundBlurOptions(): ForegroundBlurStyleOptions {
    return { colorMode: this.colorMode === 'day' ? ThemeColorMode.LIGHT : ThemeColorMode.DARK,
      scale: normalizeForegroundBlur(this.foregroundBlurStrength) };
  }

  private async saveForegroundBlur(value: number): Promise<void> {
    if (this.personalizationBusy || !this.settingsReady) return;
    this.personalizationBusy = true;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.foregroundBlurStrength = await this.personalizationStore.saveForegroundBlur(context, value / 100);
      this.appearanceMessage = this.foregroundBlurStrength > 0 ? '前景材质模糊强度已保存。' : '已关闭前景材质模糊。';
    } catch (_) { this.appearanceMessage = '模糊调整在本次使用有效，但未能保存，请重试。'; }
    finally { this.personalizationBusy = false; }
  }

  private async chooseBackground(): Promise<void> {
    if (this.personalizationBusy || !this.settingsReady) return;
    this.personalizationBusy = true; this.appearanceMessage = '';
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const path: string | null = await this.personalizationStore.chooseBackground(context);
      if (path !== null) { this.backgroundPath = path; this.appearanceMessage = '背景已保存，重新打开应用仍会保留。'; }
    } catch (_) { this.appearanceMessage = '未能导入背景。请选择小于 50 MB 的普通图片后重试，原背景保留。'; }
    finally { this.personalizationBusy = false; }
  }

  private async removeBackground(): Promise<void> {
    if (this.personalizationBusy || !this.settingsReady) return;
    this.personalizationBusy = true; this.appearanceMessage = '';
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.personalizationStore.removeBackground(context);
      this.backgroundPath = ''; this.appearanceMessage = '已恢复默认背景。';
    } catch (_) { this.appearanceMessage = '背景未能恢复，请重试。'; }
    finally { this.personalizationBusy = false; }
  }

  private async saveBackgroundOpacity(value: number): Promise<void> {
    if (this.personalizationBusy || !this.settingsReady) return;
    this.personalizationBusy = true;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.backgroundOpacity = await this.personalizationStore.saveOpacity(context, value / 100);
      this.appearanceMessage = '背景浓度已保存。';
    } catch (_) { this.appearanceMessage = '浓度调整在本次使用有效，但未能保存，请重试。'; }
    finally { this.personalizationBusy = false; }
  }

  private async savePanelTransparency(value: number): Promise<void> {
    if (this.personalizationBusy || !this.settingsReady) return;
    this.personalizationBusy = true;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.panelTransparency = await this.personalizationStore.savePanelTransparency(context, value / 100);
      this.appearanceMessage = '卡片透明度已保存。';
    } catch (_) { this.appearanceMessage = '透明度调整在本次使用有效，但未能保存，请重试。'; }
    finally { this.personalizationBusy = false; }
  }

  private presetIndex(): number {
    return ['', '#4963C9', '#7C4DCC', '#21866C', '#C04C65', '#AF701D'].indexOf(this.themeColor);
  }
  private selectGame(game: Game): void {
    this.resetAchievements();
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.selected = this.selected !== null && this.selected.appId === game.appId ? null : game;
    });
  }

  private busy(): boolean {
    return this.privacyBusy || this.loading || this.savingSettings || !this.settingsReady;
  }

  private async changeAppearance(mode: AppearanceMode): Promise<void> {
    if (!this.settingsReady || this.appearanceSaving) return;
    this.colorMode = mode;
    this.appearanceSaving = true;
    this.appearanceMessage = '';
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await applyAppearance(context, mode);
      // Appearance is saved independently; changing colors never saves or deletes credentials.
      await this.appearanceStore.save(context, mode);
      this.appearanceMessage = '已保存，重新打开应用会保留当前模式。';
    } catch (_) {
      this.appearanceMessage = '颜色已切换，但未能保存；本次使用仍有效，请稍后重试。';
    } finally {
      this.appearanceSaving = false;
    }
  }

  private async restoreSettings(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (this.privacyStatus !== 'granted') { if (this.privacyStatus === 'declined') this.library = demoLibrary(); this.settingsReady = true; return; }
    let restored: boolean = false;
    try {
      try {
        this.prefs = await preferences.getPreferences(context, { name: 'steam_hours' });
        this.account = await this.prefs.get('account', '') as string;
        this.rememberKey = await this.prefs.get('rememberKey', true) as boolean;
        this.includeFamily = await this.prefs.get('includeFamily', false) as boolean;
      } catch (_) {}
      this.sort = await this.libraryStore.readSort(context);
      const cached: LibraryResponse | null = await this.libraryStore.read(context, this.account, this.includeFamily);
      if (cached !== null) {
        this.library = cached; restored = true;
        this.libraryMessage = '已恢复上次读取的游戏库；点击刷新更新数据。';
      }
      if (this.rememberKey) {
        this.apiKey = await this.keyStore.read();
        this.familyToken = await this.familyStore.read();
      }
    } catch (_) { this.settingsMessage = '保存的授权暂时不可用，请在游戏账号中重新填写。'; }
    finally { this.settingsReady = true; }
    if (!restored) {
      if (this.apiKey.trim() && this.account.trim()) await this.loadLibrary();
      else this.requireAccounts();
    }
  }

  private changeSort(value: number): void {
    this.sort = normalizeLibrarySort(value); this.visibleLimit = 60;
    if (this.privacyBusy) return;
    const dataGeneration: number = this.dataGeneration;
    const selectedSort: number = this.sort;
    this.sortWrites = this.sortWrites.then(async () => {
      if (dataGeneration !== this.dataGeneration) return;
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.libraryStore.saveSort(context, selectedSort);
    }).catch(() => { this.libraryMessage = '当前排序已生效，但未能保存，请重试。'; });
  }

  private artworkUrl(game: Game): string { return this.hasConsent() ? steamArtworkUrl(game, this.artworkFailures[game.appId.toString()] || 0, this.artworkUrls[game.appId.toString()] || []) : ''; }
  private async refreshArtwork(): Promise<void> {
    if (!this.hasConsent() || this.artworkLoading || this.mainPage !== 'library') return;
    const ids: number[] = this.visibleGames().slice(0, this.visibleLimit).map((game: Game) => game.appId).filter((id: number) => !this.artworkAttempted.has(id)).slice(0, 100);
    if (!ids.length) return;
    const generation: number = privacyAccess.begin(); this.artworkLoading = true;
    ids.forEach((id: number) => this.artworkAttempted.add(id));
    try {
      const urls: ArtworkMap = await this.artworkApi.load(ids);
      if (!privacyAccess.current(generation)) return;
      const combined: ArtworkMap = {}; Object.keys(this.artworkUrls).forEach((id: string) => { combined[id] = this.artworkUrls[id]; });
      const failures: Record<string, number> = {}; Object.keys(this.artworkFailures).forEach((id: string) => { failures[id] = this.artworkFailures[id]; });
      Object.keys(urls).forEach((id: string) => { combined[id] = urls[id]; failures[id] = 0; });
      this.artworkUrls = combined; this.artworkFailures = failures;
    } catch (_) {} finally {
      if (privacyAccess.current(generation)) { this.artworkLoading = false; this.refreshArtwork(); }
    }
  }
  private artworkErrorHandler(game: Game, url: string): () => void {
    return (): void => this.artworkFailed(game, url);
  }
  private artworkFailed(game: Game, url: string): void {
    if (this.artworkUrl(game) !== url) return;
    const failures: Record<string, number> = {};
    Object.keys(this.artworkFailures).forEach((id: string) => { failures[id] = this.artworkFailures[id]; });
    failures[game.appId.toString()] = (failures[game.appId.toString()] || 0) + 1;
    this.artworkFailures = failures;
  }

  private resetAchievements(): void {
    this.achievementRequest++; this.achievementAppId = 0; this.achievementData = null;
    this.achievementError = ''; this.achievementLoading = false; this.achievementLimit = 30;
  }
  private async loadAchievements(game: Game): Promise<void> {
    if (!this.requireConsent()) return;
    if (this.library.demo || !this.library.player.steamId) {
      this.achievementAppId = game.appId; this.achievementError = '请先读取本人游戏库，再查看真实成就。'; return;
    }
    if (!this.apiKey.trim()) { this.requireAccounts(); this.errorText = '查看成就需要填写 Steam Web API 密钥。'; return; }
    if (this.achievementLoading) return;
    this.achievementRequest++; const requestId: number = this.achievementRequest;
    const steamId: string = this.library.player.steamId;
    this.achievementAppId = game.appId; this.achievementLoading = true; this.achievementError = ''; this.achievementData = null;
    this.achievementLimit = 30;
    try {
      const result = await this.achievementsApi.load(steamId, game.appId, this.apiKey);
      if (requestId === this.achievementRequest && this.library.player.steamId === steamId && this.selected?.appId === game.appId) this.achievementData = result;
    } catch (error) {
      if (requestId === this.achievementRequest) this.achievementError = (error as Error).message || '成就暂不可用，请稍后重试。';
    } finally { if (requestId === this.achievementRequest) this.achievementLoading = false; }
  }

  private async persistSettings(): Promise<void> {
    if (!this.hasConsent()) throw new Error('尚未启用 Steam 查询。');
    const key: string = this.apiKey.trim();
    if (key) validateApiKey(key);
    if (this.rememberKey && key) await this.keyStore.save(key);
    else await this.keyStore.clear();
    if (this.rememberKey && this.familyToken) await this.familyStore.save(this.familyToken);
    else await this.familyStore.clear();
    this.apiKey = key;
    const prefs: preferences.Preferences | null = this.prefs;
    if (prefs !== null) {
      await prefs.put('account', this.account);
      await prefs.put('rememberKey', this.rememberKey);
      await prefs.put('includeFamily', this.includeFamily);
      await prefs.delete('baseUrl');
      await prefs.flush();
    }
  }

  private async saveSettings(): Promise<void> {
    if (!this.requireConsent() || this.busy()) return;
    this.savingSettings = true;
    this.settingsMessage = '';
    let saved: boolean = false;
    try {
      await this.persistSettings();
      saved = true;
      this.settingsMessage = !this.apiKey ? '配置已保存，当前没有 API 密钥。' :
      (this.rememberKey ? '密钥已安全保存在此设备。可以读取游戏库。' : '已移除设备保存的密钥，本次打开应用期间仍可查询。');
    } catch (error) {
      this.settingsMessage = (error as Error).message || '配置未能保存，请重试。';
    } finally {
      this.savingSettings = false;
    }
    if (saved && this.account.trim() && this.apiKey.trim()) await this.loadLibrary();
  }

  private async clearKey(): Promise<void> {
    if (this.busy()) return;
    this.savingSettings = true;
    this.settingsMessage = '';
    try {
      await this.keyStore.clear();
      this.apiKey = '';
      this.api.clearCache();
      this.achievementsApi.clearCache();
      this.resetAchievements();
      this.settingsMessage = '已清除设备保存的密钥和本次使用的密钥。';
    } catch (error) {
      this.settingsMessage = (error as Error).message;
    } finally {
      this.savingSettings = false;
    }
  }

  private async authorizeFamily(token: string): Promise<void> {
    if (!this.hasConsent()) return;
    this.familyToken = token;
    this.includeFamily = true;
    this.navigation.back();
    this.editingInput = false;
    this.api.clearCache();
    this.savingSettings = true;
    try {
      await this.persistSettings();
      this.settingsMessage = this.rememberKey ? '家庭登录授权已安全保存，请读取游戏库。' : '家庭授权仅在本次使用，请读取游戏库。';
    } catch (_) {
      this.settingsMessage = '家庭授权已取得，但未能安全保存。当前仅在本次使用。';
    } finally {
      this.savingSettings = false;
    }
    if (this.account.trim() && this.apiKey.trim()) await this.loadLibrary();
    else this.settingsMessage = 'Steam 登录已完成，请填写查询账号和 API 密钥以同步昵称、头像和游戏库。';
  }

  private async clearFamily(): Promise<void> {
    if (this.busy()) return;
    this.savingSettings = true;
    try {
      await this.familyStore.clear();
      this.familyToken = '';
      this.includeFamily = false;
      this.api.clearCache();
      webview.WebCookieManager.clearAllCookiesSync();
      webview.WebStorage.deleteAllData();
      if (!this.library.demo && this.library.familyStatus) {
        // Existing family rows came from an earlier authorization; require a fresh read.
        this.library = emptyLibrary();
        await this.libraryStore.clear(this.getUIContext().getHostContext() as common.UIAbilityContext);
        this.selected = null;
      }
      if (this.prefs !== null) {
        await this.prefs.put('includeFamily', false);
        await this.prefs.flush();
      }
      this.settingsMessage = '已移除家庭授权和此应用的 Steam 登录 Cookie。';
    } catch (_) {
      this.settingsMessage = '家庭授权移除未完成，请重试。';
    } finally {
      this.savingSettings = false;
    }
  }

  private async loadLibrary(): Promise<void> {
    if (!this.requireConsent() || this.busy()) return;
    const privacyGeneration: number = privacyAccess.begin();
    if (!this.apiKey.trim()) {
      this.requireAccounts();
      this.errorText = '请先在“游戏账号”中填写自己的 Steam Web API 密钥。';
      return;
    }
    if (this.includeFamily && !this.familyToken) {
      this.requireAccounts();
      this.errorText = '包含家庭共享需要先登录 Steam。';
      return;
    }
    this.loading = true;
    this.errorText = '';
    this.resetAchievements();
    this.selected = null;
    const queriedAccount: string = this.account;
    const queriedFamily: boolean = this.includeFamily;
    try {
      const data: LibraryResponse = await this.api.load(this.account, this.apiKey, this.includeFamily ? this.familyToken : '');
      if (!privacyAccess.current(privacyGeneration)) return;
      this.library = data;
      this.libraryMessage = '';
      this.artworkFailures = {}; this.artworkAttempted.clear(); this.artworkApi.clearCache();
      this.openLibrary();
      this.visibleLimit = 60;
      this.search = '';
      this.sourceFilter = 0;
      this.librarySaving = true;
      try {
        await this.libraryStore.save(this.getUIContext().getHostContext() as common.UIAbilityContext, queriedAccount, queriedFamily, data);
      } catch (_) { this.libraryMessage = '游戏库已更新，但未能保存本地缓存；下次打开可能需要重新读取。'; }
      try {
        await this.persistSettings();
        this.settingsMessage = this.rememberKey ? '密钥已安全保存在此设备。' : '密钥仅在本次打开应用期间使用。';
      } catch (error) {
        this.settingsMessage = '查询成功，但配置未能保存：' + (error as Error).message;
        this.libraryMessage = '游戏库已更新，但账号配置未能保存，请稍后在游戏账号中重试。';
      }
    } catch (error) {
      if (privacyAccess.current(privacyGeneration)) this.errorText = (error as Error).message || '查询失败，请检查网络后重试。';
    } finally {
      if (privacyAccess.current(privacyGeneration)) { this.loading = false; this.librarySaving = false; this.refreshArtwork(); }
    }
  }

  private visibleGames(): Game[] {
    const term: string = this.search.trim().toLowerCase();
    const games: Game[] = this.library.games.filter((game: Game) => {
      return (this.sourceFilter === 0 || (this.sourceFilter === 1 ? game.source !== 'family' : game.source === 'family')) && game.name.toLowerCase().includes(term) && (!this.onlyRecent || (game.recentMinutes !== null && game.recentMinutes > 0));
    });
    if (this.sort === 1) games.sort((a: Game, b: Game) => (b.recentMinutes === null ? -1 : b.recentMinutes) - (a.recentMinutes === null ? -1 : a.recentMinutes));
    else if (this.sort === 2) games.sort((a: Game, b: Game) => a.name.localeCompare(b.name));
    else if (this.sort === 3) games.sort((a: Game, b: Game) => b.lastPlayed - a.lastPlayed);
    else games.sort((a: Game, b: Game) => (b.totalMinutes === null ? -1 : b.totalMinutes) - (a.totalMinutes === null ? -1 : a.totalMinutes));
    return games;
  }

  private timeLabel(value: number | null): string {
    return value === null ? '暂不可用' : formatHours(value) + ' 小时';
  }

  private share(game: Game): number {
    if (game.totalMinutes === null || this.library.totalMinutes === null || this.library.totalMinutes <= 0) return 0;
    return Math.min(100, game.totalMinutes / this.library.totalMinutes * 100);
  }

  private lastPlayedLabel(game: Game): string {
    if (!game.lastPlayed) return '最近游玩时间未返回';
    return '最近游玩：' + new Date(game.lastPlayed * 1000).toLocaleDateString();
  }

  @Styles
  private privacyPanel() {
    .width('100%').padding(20).backgroundColor(this.colors().surface).borderRadius(24)
    .border({ width: 1, color: this.colors().edge })
  }

  @Styles
  private floatingPanel() {
    .width('100%').padding(20).backgroundColor(this.panelColor(this.colors().surface)).borderRadius(24)
    .border({ width: 1, color: this.panelColor(this.colors().edge) })
    .shadow({ radius: 16, color: this.panelColor(this.colors().rowShadow), offsetY: 5 })
  }

  @Builder
  private panelHeading(title: string, subtitle: string) {
    Row({ space: 10 }) {
      Stack() {}.width(4).height(30).borderRadius(2).backgroundColor(this.colors().primary)
      Column({ space: 5 }) {
        Text(title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.colors().text).width('100%')
        Text(subtitle).fontSize(12).fontColor(this.colors().secondary).lineHeight(19).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%')
  }

  @Builder
  private settings() {
    Column({ space: 16 }) {
      Column({ space: 14 }) {
        this.panelHeading('色彩模式', '日间通透，夜间柔和。')
        Row({ space: 10 }) {
          Button('日间模式').layoutWeight(1).height(40)
          .backgroundColor(this.colorMode === 'day' ? this.colors().primary : this.colors().control)
          .fontColor(this.colorMode === 'day' ? this.colors().primaryText : this.colors().body)
          .enabled(this.settingsReady && !this.appearanceSaving)
          .onClick(() => this.changeAppearance('day'))
          .attributeModifier(this.colorMode === 'day' ? this.theme().primary : this.theme().button)
          Button('夜间模式').layoutWeight(1).height(40)
          .backgroundColor(this.colorMode === 'night' ? this.colors().primary : this.colors().control)
          .fontColor(this.colorMode === 'night' ? this.colors().primaryText : this.colors().body)
          .enabled(this.settingsReady && !this.appearanceSaving)
          .onClick(() => this.changeAppearance('night'))
          .attributeModifier(this.colorMode === 'night' ? this.theme().primary : this.theme().button)
        }.width('100%')
        Text('当前：' + (this.colorMode === 'day' ? '日间模式' : '夜间模式'))
        .fontSize(12).fontColor(this.colors().secondary).width('100%')
      }.floatingPanel()
      if (this.appearanceMessage) {
        Text(this.appearanceMessage).fontSize(12).fontColor(this.colors().accent).lineHeight(19).width('100%')
      }
      Column({ space: 14 }) {
        this.panelHeading('卡片透明度', '调节板块背景，让图片与光晕透出来。')
        Text('透明度 ' + Math.round(this.panelTransparency * 100).toString() + '%')
        .fontSize(13).fontColor(this.colors().secondary).width('100%')
        Slider({ value: this.panelTransparency * 100, min: 0, max: 100, step: 1 })
        .selectedColor(this.colors().primary).trackColor(this.colors().progressTrack).width('100%')
        .accessibilityText('卡片透明度，0%不透明，100%完全透明')
        .enabled(this.settingsReady && !this.personalizationBusy)
        .onChange((value: number, mode: SliderChangeMode) => {
          this.panelTransparency = normalizePanelTransparency(value / 100);
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.savePanelTransparency(value);
        })
        Text('0%为不透明，100%为完全透明。文字、按钮和输入框保持清晰。')
        .fontSize(12).fontColor(this.colors().secondary).lineHeight(19).width('100%')
      }.floatingPanel()
      Column({ space: 14 }) {
        this.panelHeading('主题色', '选择预设色，或让界面呼应你的图片。')
        Select([{ value: '默认主题色' }, { value: '星海蓝' }, { value: '雾紫' }, { value: '薄荷绿' }, { value: '珊瑚红' }, { value: '金杏' }])
        .selected(this.presetIndex()).value(this.presetIndex() < 0 ? '自定义 ' + this.themeColor :
        ['默认主题色', '星海蓝', '雾紫', '薄荷绿', '珊瑚红', '金杏'][this.presetIndex()])
        .fontColor(this.colors().body).backgroundColor(this.colors().control).width('100%')
        .enabled(this.settingsReady && !this.personalizationBusy)
        .onSelect((index: number) => this.saveThemeColor(['', '#4963C9', '#7C4DCC', '#21866C', '#C04C65', '#AF701D'][index]))
        .attributeModifier(this.theme().select)
        Row({ space: 8 }) {
          TextInput({ text: this.themeColorDraft, placeholder: '#RRGGBB 自定义颜色' }).layoutWeight(1)
          .maxLength(7).fontSize(13).fontColor(this.colors().text).placeholderColor(this.colors().placeholder).backgroundColor(this.colors().input)
          .enabled(!this.personalizationBusy).onChange((value: string) => this.themeColorDraft = value)
          .onFocus(() => this.editingInput = true).onBlur(() => this.editingInput = false)
          Button('应用').height(44).fontSize(13).backgroundColor(this.colors().primary).fontColor(this.colors().primaryText)
          .enabled(this.settingsReady && !this.personalizationBusy).onClick(() => this.saveThemeColor(this.themeColorDraft))
          .attributeModifier(this.theme().primary)
        }.width('100%')
        Row({ space: 8 }) {
          Stack() {}.width(20).height(20).borderRadius(10).backgroundColor(this.colors().primary)
          Text('当前主题色 ' + this.colors().primary).fontSize(12).fontColor(this.colors().secondary)
        }.width('100%')
        Button(this.personalizationBusy ? '处理中…' : '从图片取主题色').width('100%').height(44)
        .backgroundColor(this.colors().control).fontColor(this.colors().body)
        .enabled(this.settingsReady && !this.personalizationBusy)
        .onClick(() => this.chooseImageTheme()).attributeModifier(this.theme().button)
        Text('从系统图库提取主色和代表色，点击色块应用。').fontSize(12).fontColor(this.colors().secondary).lineHeight(19).width('100%')
        if (this.imageThemeMessage) {
          Text(this.imageThemeMessage).fontSize(12).fontColor(this.colors().accent).lineHeight(19).width('100%')
        }
        if (this.imageThemePalette.length > 0) {
          Row({ space: 6 }) {
            ForEach(this.imageThemePalette, (color: string) => {
              Button(color).height(44).layoutWeight(1).fontSize(10).padding({ left: 2, right: 2 }).borderRadius(12)
              .backgroundColor(color).fontColor(colorsFor(this.colorMode, color).primaryText)
              .border({ width: this.themeColor === color ? 2 : 1, color: this.themeColor === color ? this.colors().text : this.colors().edge })
              .accessibilityText('应用图片主题色 ' + color + (this.themeColor === color ? '，已选中' : ''))
              .enabled(this.settingsReady && !this.personalizationBusy).onClick(() => this.saveThemeColor(color))
            }, (color: string) => color)
          }.width('100%')
        }
      }.floatingPanel()
      Column({ space: 14 }) {
        this.panelHeading('背景与光感', '营造喜欢的氛围，卡片与文字保持清晰。')
        if (this.backgroundPath) {
          Image('file://' + this.backgroundPath).width('100%').height(130).objectFit(ImageFit.Cover).borderRadius(14)
        }
        Row({ space: 8 }) {
          Button(this.personalizationBusy ? '处理中…' : (this.backgroundPath ? '更换背景' : '选择背景')).layoutWeight(1)
          .backgroundColor(this.colors().secondaryButton).fontColor(this.colors().buttonText)
          .enabled(this.settingsReady && !this.personalizationBusy).onClick(() => this.chooseBackground()).attributeModifier(this.theme().button)
          Button('恢复默认').backgroundColor(this.colors().control).fontColor(this.colors().body)
          .enabled(this.settingsReady && !this.personalizationBusy && !!this.backgroundPath)
          .onClick(() => this.removeBackground()).attributeModifier(this.theme().button)
        }.width('100%')
        if (this.backgroundPath) {
          Text('背景浓度 ' + Math.round(this.backgroundOpacity * 100).toString() + '%').fontSize(12).fontColor(this.colors().secondary).width('100%')
          Slider({ value: this.backgroundOpacity * 100, min: 8, max: 100, step: 1 })
          .selectedColor(this.colors().primary).trackColor(this.colors().progressTrack).width('100%')
          .enabled(this.settingsReady && !this.personalizationBusy)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.backgroundOpacity = value / 100;
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.saveBackgroundOpacity(value);
          })
        }
        Divider().color(this.colors().edge).margin({ top: 4, bottom: 4 })
        Text('前景材质模糊').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.colors().text).width('100%')
        Text('柔化背景图片和装饰光晕。强度为 0 时关闭。').fontSize(12).fontColor(this.colors().secondary).lineHeight(19).width('100%')
        Text('模糊强度 ' + Math.round(this.foregroundBlurStrength * 100).toString() + '%').fontSize(12).fontColor(this.colors().secondary).width('100%')
        Slider({ value: this.foregroundBlurStrength * 100, min: 0, max: 100, step: 5 })
        .selectedColor(this.colors().primary).trackColor(this.colors().progressTrack).width('100%')
        .accessibilityText('前景材质模糊强度').enabled(this.settingsReady && !this.personalizationBusy)
        .onChange((value: number, mode: SliderChangeMode) => {
          this.foregroundBlurStrength = normalizeForegroundBlur(value / 100);
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.saveForegroundBlur(value);
        })
      }.floatingPanel()
      Column({ space: 14 }) {
        this.panelHeading('隐私与帮助', '管理数据，了解应用与联系开发者。')
        Button('隐私政策与同意管理').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
        .onClick(() => this.openInfo('privacy')).attributeModifier(this.theme().button)
        Button('关于应用').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
        .onClick(() => this.openInfo('about')).attributeModifier(this.theme().button)
        Button('问题反馈').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
        .onClick(() => this.openInfo('support')).attributeModifier(this.theme().button)
        Button('清除全部本地数据').width('100%').height(44).backgroundColor(this.colors().dangerBackground).fontColor(this.colors().dangerText)
        .enabled(this.canClearData()).onClick(() => this.confirmClearData()).attributeModifier(this.theme().danger)
        Text('包含密钥、家庭授权、库缓存、排序、外观、背景副本、缓存和隐私选择；确认后才删除。')
        .fontSize(12).fontColor(this.colors().secondary).lineHeight(19).width('100%')
      }.floatingPanel()
      Text('游戏时光 · Steam Hours 0.3.24').fontSize(10).fontColor(this.colors().muted).padding({ top: 4, bottom: 8 })
    }.width('100%')
  }

  @Builder
  private privacyPrompt() {
    Column({ space: 18 }) {
      Text(this.privacyStatus === 'blocked' ? '需要完成数据清除' : '欢迎使用游戏时光')
      .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.colors().text).width('100%')
      Text('开发者：' + DEVELOPER_NAME).fontSize(13).fontColor(this.colors().secondary).width('100%')
      Text('Steam 查询会向 Steam 发送账号、游戏编号和 API 密钥；远程图片由 Steam 及其 CDN 提供。本地保存记录与外观，密钥使用设备安全存储。请先阅读隐私政策再选择。')
      .fontSize(14).fontColor(this.colors().body).lineHeight(23).width('100%')
      if (this.privacyMessage) { Text(this.privacyMessage).fontSize(13).fontColor(this.colors().dangerText).lineHeight(21).width('100%') }
      Button('阅读完整隐私政策').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
      .onClick(() => this.openInfo('privacy')).attributeModifier(this.theme().button)
      if (this.privacyStatus === 'blocked') {
        Button(this.privacyBusy ? '正在清除…' : '重试清除本地数据').width('100%').height(44).backgroundColor(this.colors().primary).fontColor(this.colors().primaryText)
        .enabled(this.canClearData()).onClick(() => this.clearAllLocalData()).attributeModifier(this.theme().primary)
      } else {
        Button('同意并启用 Steam 查询').width('100%').height(44).backgroundColor(this.colors().primary).fontColor(this.colors().primaryText)
        .enabled(!this.privacyBusy).onClick(() => this.acceptPrivacy()).attributeModifier(this.theme().primary)
        Button('不同意，离线使用').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
        .enabled(!this.privacyBusy).onClick(() => this.declinePrivacy()).attributeModifier(this.theme().button)
      }
      Button('关于与反馈').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
      .onClick(() => this.openInfo('about')).attributeModifier(this.theme().button)
    }.privacyPanel()
  }
  @Builder
  private privacyPage() {
    Column({ space: 16 }) {
      Column({ space: 14 }) {
        this.panelHeading('隐私政策', '版本 ' + POLICY_REVISION + ' · 2026年10月21日')
        Text('当前选择：' + (this.privacyStatus === 'granted' ? '已同意，Steam 查询已启用' : (this.privacyStatus === 'blocked' ? '删除待完成，联网关闭' : '尚未启用 Steam 查询')))
        .fontSize(13).fontColor(this.colors().accent).lineHeight(21).width('100%')
        if (this.privacyMessage) { Text(this.privacyMessage).fontSize(13).fontColor(this.colors().dangerText).lineHeight(21).width('100%') }
        if (this.privacyStatus === 'granted') {
          Button('撤回同意并清除本地数据').width('100%').height(44).backgroundColor(this.colors().dangerBackground).fontColor(this.colors().dangerText)
          .enabled(this.canClearData()).onClick(() => this.confirmClearData(true)).attributeModifier(this.theme().danger)
        } else if (this.privacyStatus === 'blocked') {
          Button(this.privacyBusy ? '正在清除…' : '重试清除本地数据').width('100%').height(44).backgroundColor(this.colors().primary).fontColor(this.colors().primaryText)
          .enabled(this.canClearData()).onClick(() => this.clearAllLocalData()).attributeModifier(this.theme().primary)
        } else {
          Button('同意并启用 Steam 查询').width('100%').height(44).backgroundColor(this.colors().primary).fontColor(this.colors().primaryText)
          .enabled(!this.privacyBusy).onClick(() => this.acceptPrivacy()).attributeModifier(this.theme().primary)
          Button('不同意，离线使用').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
          .enabled(!this.privacyBusy).onClick(() => this.declinePrivacy()).attributeModifier(this.theme().button)
        }
        Button('返回').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
        .onClick(() => this.switchPage(this.infoReturnPage)).attributeModifier(this.theme().button)
      }.privacyPanel()
      ForEach(PRIVACY_SECTIONS, (section: PrivacySection) => {
        Column({ space: 12 }) {
          Text(section.title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.colors().text).width('100%')
          Text(section.body).fontSize(14).fontColor(this.colors().body).lineHeight(24).width('100%')
        }.privacyPanel()
      }, (section: PrivacySection) => section.title)
    }.width('100%')
  }
  @Builder
  private aboutPage() {
    Column({ space: 16 }) {
      Column({ space: 14 }) {
        Image($r('app.media.app_icon')).width(72).height(72).borderRadius(22)
        this.panelHeading('游戏时光', '个人游戏记录与游玩时光')
        Text('版本 ' + APP_VERSION).fontSize(14).fontColor(this.colors().body).width('100%')
        Text('开发者：' + DEVELOPER_NAME).fontSize(14).fontColor(this.colors().body).width('100%')
        Text('© 2026 ' + DEVELOPER_NAME).fontSize(12).fontColor(this.colors().secondary).width('100%')
        Text('查询 Steam 个人游戏库、家庭共享清单、本人游玩时长与成就。启用家庭共享需单独登录本人 Steam；家人游戏的时长不计入本人统计。')
        .fontSize(14).fontColor(this.colors().body).lineHeight(23).width('100%')
        Text('独立应用，与 Valve/Steam 无官方隶属或背书关系。数据按接口现状提供，可能因账号隐私、网络或游戏支持而不可用。')
        .fontSize(13).fontColor(this.colors().secondary).lineHeight(22).width('100%')
        Button('阅读隐私政策').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
        .onClick(() => this.openInfo('privacy')).attributeModifier(this.theme().button)
        Button('问题反馈').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
        .onClick(() => this.openInfo('support')).attributeModifier(this.theme().button)
        Button('返回设置').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
        .onClick(() => this.switchPage('settings')).attributeModifier(this.theme().button)
      }.floatingPanel()
    }.width('100%')
  }
  @Builder
  private supportPage() {
    Column({ space: 16 }) {
      Column({ space: 14 }) {
        this.panelHeading('问题反馈', '使用问题、隐私咨询与数据请求')
        Text('开发者：' + DEVELOPER_NAME).fontSize(14).fontColor(this.colors().body).width('100%')
        Text(SUPPORT_URL).fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.colors().accent).width('100%')
        Text('请描述应用版本、系统版本、问题和复现步骤。请勿发送 API 密钥、密码、身份证或含凭据的截图。')
        .fontSize(14).fontColor(this.colors().body).lineHeight(23).width('100%')
        Button('复制反馈地址').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
        .onClick(() => this.copySupport()).attributeModifier(this.theme().button)
        Button('复制反馈模板').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
        .onClick(() => this.copySupport(true)).attributeModifier(this.theme().button)
        Button('打开 GitHub 反馈').width('100%').height(44).backgroundColor(this.colors().primary).fontColor(this.colors().primaryText)
        .onClick(() => this.openFeedback()).attributeModifier(this.theme().primary)
        if (this.supportMessage) { Text(this.supportMessage).fontSize(13).fontColor(this.colors().accent).lineHeight(21).width('100%') }
        Button('隐私政策与数据管理').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
        .onClick(() => this.openInfo('privacy')).attributeModifier(this.theme().button)
        Button('返回设置').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
        .onClick(() => this.switchPage('settings')).attributeModifier(this.theme().button)
      }.floatingPanel()
    }.width('100%')
  }

  @Builder
  private accounts() {
    Column({ space: 16 }) {
      if (!this.hasConsent()) {
        Text('当前为离线模式，账号查询、家庭登录与远程图片未启用。').fontSize(13).fontColor(this.colors().secondary).lineHeight(21).width('100%')
        Button('阅读隐私政策并启用查询').width('100%').height(44).backgroundColor(this.colors().control).fontColor(this.colors().body)
        .onClick(() => this.openInfo('privacy')).attributeModifier(this.theme().button)
      }
      Column({ space: 14 }) {
        Text('连接你的 Steam').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.colors().text).width('100%')
        Text('输入个人主页，查看游戏库与游玩时光').fontSize(12).fontColor(this.colors().secondary).width('100%')
        TextInput({ text: this.account, placeholder: 'SteamID64 或 Steam 个人主页链接' })
        .fontSize(13).fontColor(this.colors().text).placeholderColor(this.colors().placeholder).backgroundColor(this.colors().input)
        .onChange((value: string) => this.account = value).enabled(!this.busy() && this.hasConsent())
        .onFocus(() => this.editingInput = true).onBlur(() => this.editingInput = false)
        Row({ space: 10 }) {
          Button(this.loading ? '正在读取…' : '读取游戏库').layoutWeight(1).height(42)
          .backgroundColor(this.colors().primary).fontColor(this.colors().primaryText).fontWeight(FontWeight.Bold)
          .enabled(!this.busy()).onClick(() => this.loadLibrary())
          .attributeModifier(this.theme().primary)
          Button('查看演示').height(42).backgroundColor(this.colors().control).fontColor(this.colors().body).enabled(!this.busy())
          .onClick(() => { this.resetAchievements(); this.library = demoLibrary(); this.libraryMessage = ''; this.openLibrary(); this.errorText = ''; this.search = ''; this.sourceFilter = 0; this.selected = null; this.visibleLimit = 60; })
          .attributeModifier(this.theme().button)
        }.width('100%')
      }.floatingPanel()
      Column({ space: 14 }) {
        Text('Steam API 密钥').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.colors().text).width('100%')
        Text('无需服务器，使用自己的 Web API 密钥直连 Steam。').fontSize(12).fontColor(this.colors().secondary).lineHeight(19).width('100%')
        TextInput({ text: this.apiKey, placeholder: '32 位 Steam Web API 密钥' })
        .type(InputType.Password).fontColor(this.colors().text).placeholderColor(this.colors().placeholder).backgroundColor(this.colors().input)
        .onChange((value: string) => this.apiKey = value).enabled(!this.busy() && this.hasConsent())
        .onFocus(() => this.editingInput = true).onBlur(() => this.editingInput = false)
        Row({ space: 8 }) {
          Text('安全保存在此设备').fontSize(13).fontColor(this.colors().body).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.rememberKey }).selectedColor(this.colors().switchTrack).enabled(!this.busy())
          .onChange((value: boolean) => this.rememberKey = value)
          .attributeModifier(this.theme().toggle)
        }.width('100%')
        Text('密钥在设备解锁时可读取。关闭保存并点击“保存账号”后，将删除已保存密钥，仅在本次使用。')
        .fontSize(11).fontColor(this.colors().secondary).lineHeight(18).width('100%')
        Text('获取密钥：在浏览器打开 steamcommunity.com/dev/apikey。应用不需要 Steam 密码。')
        .fontSize(11).fontColor(this.colors().secondary).lineHeight(18).width('100%')
        Row({ space: 10 }) {
          Button(this.savingSettings ? '处理中…' : '保存账号').layoutWeight(1).backgroundColor(this.colors().secondaryButton).fontColor(this.colors().buttonText)
          .enabled(!this.busy()).onClick(() => this.saveSettings())
          .attributeModifier(this.theme().button)
          Button('清除密钥').backgroundColor(this.colors().dangerBackground).fontColor(this.colors().dangerText)
          .enabled(!this.busy()).onClick(() => this.clearKey())
          .attributeModifier(this.theme().danger)
        }.width('100%')
      }.floatingPanel()
      Column({ space: 14 }) {
        Text('家庭共享').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.colors().text).width('100%')
        Row() {
          Text('包含家庭共享').fontSize(14).fontColor(this.colors().body).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.includeFamily }).selectedColor(this.colors().switchTrack).enabled(!this.busy())
          .onChange((value: boolean) => { this.includeFamily = value; this.api.clearCache(); })
          .attributeModifier(this.theme().toggle)
        }.width('100%')
        Text(this.familyToken ? '家庭授权已就绪；授权过期时需要重新登录 Steam。' : '家庭清单需要额外登录本人 Steam 账号，API 密钥仍用于个人库查询。')
        .fontSize(11).fontColor(this.colors().secondary).lineHeight(18).width('100%')
        Row({ space: 10 }) {
          Button(this.familyToken ? '重新登录 Steam' : '登录 Steam').layoutWeight(1).backgroundColor(this.colors().secondaryButton).fontColor(this.colors().buttonText)
          .enabled(!this.busy() && this.hasConsent()).onClick(() => { if (this.requireConsent()) this.navigation.openFamily(); })
          .attributeModifier(this.theme().button)
          Button('移除家庭授权').backgroundColor(this.colors().dangerBackground).fontColor(this.colors().dangerText)
          .enabled(!this.busy()).onClick(() => this.clearFamily())
          .attributeModifier(this.theme().danger)
        }.width('100%')
        Text('登录信息仅发送给 Steam；授权令牌使用设备安全存储。关闭设备保存并保存账号后，仅在本次使用。')
        .fontSize(11).fontColor(this.colors().secondary).lineHeight(18).width('100%')
      }.floatingPanel()
      if (this.settingsMessage) {
        Text(this.settingsMessage).fontSize(12).fontColor(this.colors().softText).lineHeight(19).width('100%')
      }
      if (this.errorText) {
        Text(this.errorText).fontSize(13).fontColor(this.colors().dangerText).lineHeight(21)
        .padding(14).backgroundColor(this.colors().dangerBackground).borderRadius(12).width('100%')
      }
    }.width('100%')
  }

  @Builder
  private destination(name: string) {
    if (name === 'family' && this.hasConsent()) {
      NavDestination() {
        FamilyLogin({ colorMode: this.colorMode, themeColor: this.themeColor,
          onAuthorized: (token: string) => { this.authorizeFamily(token); }, onClosed: () => this.closeAccountPage() })
      }.hideTitleBar(true).onBackPressed(() => { this.closeAccountPage(); return true; })
    }
  }
  @Builder
  private gameArtwork(game: Game) {
    Stack() {
        Text(game.name.substring(0, 2).toUpperCase()).fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.colors().iconText)
        if (this.artworkUrl(game) && this.hasConsent()) {
          Image(this.artworkUrl(game)).width(56).height(84).sourceSize({ width: 300, height: 450 })
          .autoResize(false).interpolation(ImageInterpolation.High)
          .objectFit(/library_(600x900|capsule)/.test(this.artworkUrl(game)) ? ImageFit.Cover : ImageFit.Contain).borderRadius(12)
          .onError(this.artworkErrorHandler(game, this.artworkUrl(game)))
        }
      }.onAppear(() => this.refreshArtwork()).width(56).height(84).backgroundColor(this.colors().control).borderRadius(14)
      .border({ width: 1, color: this.colors().shine })
  }

  @Builder
  private gameRow(game: Game) {
    Row({ space: 12 }) {
      this.gameArtwork(game)
      Column({ space: 6 }) {
        if (game.source === 'family') {
          Text('家庭共享').fontSize(10).fontColor(this.colors().success)
          .padding({ left: 7, right: 7, top: 3, bottom: 3 }).backgroundColor(this.colors().control).borderRadius(6)
        }
        Text(game.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.colors().text).maxLines(2).width('100%')
        Text('两周 ' + this.timeLabel(game.recentMinutes)).fontSize(12).fontColor(this.colors().secondary).width('100%')
        if (this.sort === 3) {
          Text(this.lastPlayedLabel(game)).fontSize(11).fontColor(this.colors().accent).width('100%')
        }
        Progress({ value: this.share(game), total: 100, type: ProgressType.Linear })
        .color(this.colors().progress).backgroundColor(this.colors().progressTrack).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Column({ space: 4 }) {
        Text(formatHours(game.totalMinutes)).fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.colors().text)
        Text(game.totalMinutes === null ? '时长未返回' : '累计小时').fontSize(10).fontColor(this.colors().secondary)
      }.alignItems(HorizontalAlign.Center).width(84).padding({ left: 4, right: 4, top: 9, bottom: 9 })
      .backgroundColor(this.colors().control).borderRadius(14)
    }.padding(14).width('100%').backgroundColor(this.panelColor(this.selected !== null && this.selected.appId === game.appId ?
    this.colors().selectedSurface : this.colors().surface)).borderRadius(24)
    .border({ width: 1, color: this.panelColor(this.selected !== null && this.selected.appId === game.appId ? this.colors().progress : this.colors().edge) })
    .shadow({ radius: 10, color: this.panelColor(this.colors().rowShadow), offsetY: 3 })
    .hoverEffect(HoverEffect.Scale)
    .onClick(() => this.selectGame(game))
  }

  @Builder
  private detail(game: Game) {
    Column({ space: 12 }) {
      Row() {
        Text('游戏详情').fontSize(12).fontColor(this.colors().accent).layoutWeight(1)
        Button('收起').fontSize(12).height(30).backgroundColor(this.colors().secondaryButton).fontColor(this.colors().body).onClick(() => this.selected = null)
        .attributeModifier(this.theme().button)
      }.width('100%')
      Text(game.name).fontSize(21).fontWeight(FontWeight.Bold).fontColor(this.colors().text).width('100%')
      Text(game.source === 'family' ? '来源：Steam 家庭共享 · 时长属于当前账号' : '来源：个人游戏库').fontSize(12).fontColor(this.colors().success).width('100%')
      Text('累计游玩  ' + this.timeLabel(game.totalMinutes)).fontSize(15).fontColor(this.colors().text).width('100%')
      Text('最近两周  ' + this.timeLabel(game.recentMinutes)).fontSize(15).fontColor(this.colors().secondary).width('100%')
      Text(this.lastPlayedLabel(game)).fontSize(12).fontColor(this.colors().secondary).width('100%')
      Divider().color(this.colors().edge)
      Button(this.achievementAppId === game.appId && this.achievementLoading ? '正在读取成就…' : '查看 / 刷新成就')
      .fontSize(13).backgroundColor(this.colors().primary).fontColor(this.colors().primaryText).width('100%')
      .enabled(!this.achievementLoading && !this.loading).onClick(() => this.loadAchievements(game)).attributeModifier(this.theme().primary)
      if (this.achievementAppId === game.appId) {
        if (this.achievementError) { Text(this.achievementError).fontSize(12).fontColor(this.colors().dangerText).lineHeight(20).width('100%') }
        if (this.achievementData !== null) { this.achievementsPanel(this.achievementData as AchievementResponse) }
      }
    }.padding(20).backgroundColor(this.panelColor(this.colors().detail)).borderRadius(22).width('100%')
    .border({ width: 1, color: this.panelColor(this.colors().progress) })
    .shadow({ radius: 18, color: this.panelColor(this.colors().shadow), offsetY: 6 })
    .transition({ type: TransitionType.All, opacity: 0, translate: { y: 8 } })
  }

  @Builder
  private achievementsPanel(data: AchievementResponse) {
    Column({ space: 12 }) {
      Text(data.status === 'available' ? '成就 ' + data.unlocked.toString() + ' / ' + data.items.length.toString() : data.message)
      .fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.colors().text).width('100%')
      if (data.status === 'available') {
        Progress({ value: data.unlocked, total: Math.max(1, data.items.length), type: ProgressType.Linear })
        .color(this.colors().primary).backgroundColor(this.colors().progressTrack).width('100%')
        if (data.message) { Text(data.message).fontSize(11).fontColor(this.colors().secondary).width('100%') }
        ForEach(data.items.slice(0, this.achievementLimit), (item: Achievement) => {
          Row({ space: 10 }) {
            Stack() {
              Text(item.unlocked === true ? '✓' : '○').fontSize(20).fontColor(this.colors().accent)
              if (item.iconUrl && this.hasConsent()) { Image(item.iconUrl).width(40).height(40).objectFit(ImageFit.Contain).interpolation(ImageInterpolation.High).borderRadius(8) }
            }.width(40).height(40).backgroundColor(this.colors().control).borderRadius(8)
            Column({ space: 5 }) {
              Text(item.name).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.colors().text).width('100%')
              if (item.description) { Text(item.description).fontSize(11).fontColor(this.colors().secondary).lineHeight(17).width('100%') }
              Text(item.unlocked === true ? (item.unlockTime > 0 ? '已解锁 · ' + new Date(item.unlockTime * 1000).toLocaleString() : '已解锁 · 时间未返回') : (item.unlocked === false ? '未解锁' : '状态未返回'))
              .fontSize(10).fontColor(item.unlocked === true ? this.colors().success : this.colors().secondary).width('100%')
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%').padding({ top: 8, bottom: 8 })
        }, (item: Achievement) => item.id)
        if (data.items.length > this.achievementLimit) {
          Button('加载更多成就').fontSize(12).backgroundColor(this.colors().control).fontColor(this.colors().body)
          .onClick(() => this.achievementLimit += 30).attributeModifier(this.theme().button)
        }
      }
    }.width('100%')
  }

  @Builder
  private pageTitle() {
    Row({ space: 12 }) {
      Image($r('app.media.app_icon')).width(44).height(44).borderRadius(14)
      .border({ width: 1, color: this.colors().shine })
      .shadow({ radius: 10, color: this.colors().glowBlue, offsetY: 3 })
      Column({ space: 4 }) {
        Text(this.mainPage === 'privacy' ? '隐私与数据' : (this.mainPage === 'about' ? '关于应用' : (this.mainPage === 'support' ? '问题反馈' : (this.mainPage === 'settings' ? '外观设置' : (this.mainPage === 'accounts' ? '游戏账号' : '游戏时光')))))
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.colors().text)
        Text(this.mainPage === 'settings' ? '色彩 · 背景 · 光感' : (this.mainPage === 'accounts' ? '连接你的 Steam' : 'STEAM HOURS'))
        .fontSize(10).letterSpacing(1).fontColor(this.colors().accent)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 14, bottom: 14 })
  }

  @Builder
  private ambientBackground() {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.backgroundPath) {
        Image('file://' + this.backgroundPath).width('100%').height('100%').objectFit(ImageFit.Cover)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .opacity(this.backgroundOpacity).onError(() => { this.appearanceMessage = '背景暂时无法显示，请在设置中重新选择图片。'; })
      }
      Stack() {}.width(320).height(320)
      .radialGradient({ center: ['50%', '50%'], radius: 160, colors: [[this.colors().glowBlue, 0], ['#00000000', 1]] })
      .translate({ x: 90, y: -70 })
      Stack() {}.width(280).height(280).align(Alignment.Start)
      .radialGradient({ center: ['50%', '50%'], radius: 140, colors: [[this.colors().glowViolet, 0], ['#00000000', 1]] })
      .translate({ x: -110, y: 70 })
      Stack() {}.width(260).height(260).align(Alignment.BottomEnd)
      .radialGradient({ center: ['50%', '50%'], radius: 130, colors: [[this.colors().glowBlue, 0], ['#00000000', 1]] })
      .translate({ x: 70, y: 40 })
    }.width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // Only this decorative layer is blurred; the Scroll content and native bars remain clear.
    .foregroundBlurStyle(this.foregroundBlurStrength > 0 ? BlurStyle.Thin : BlurStyle.NONE, this.foregroundBlurOptions())
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private bottomActions() {
    Row({ space: 8 }) {
      Button(this.mainPage !== 'library' ? '游戏库' : (this.loading ? '读取中' : (this.library.demo ? '读取' : '刷新')))
      .accessibilityText(this.mainPage !== 'library' ? '切换到游戏库' : '读取或刷新游戏库')
      .height(44).layoutWeight(1).padding({ left: 8, right: 8 }).fontSize(13).fontWeight(FontWeight.Bold)
      .backgroundColor(this.mainPage === 'library' ? this.colors().primary : this.colors().control)
      .fontColor(this.mainPage === 'library' ? this.colors().primaryText : this.colors().body)
      .enabled(this.mainPage !== 'library' || !this.busy()).onClick(() => this.readOrOpenLibrary())
      .attributeModifier(this.mainPage === 'library' ? this.theme().bottomPrimary : this.theme().bottomButton)
      Button('游戏账号').height(44).layoutWeight(1).padding({ left: 8, right: 8 }).fontSize(12)
      .backgroundColor(this.mainPage === 'accounts' ? this.colors().primary : this.colors().control)
      .fontColor(this.mainPage === 'accounts' ? this.colors().primaryText : this.colors().body)
      .onClick(() => this.openAccounts())
      .attributeModifier(this.mainPage === 'accounts' ? this.theme().bottomPrimary : this.theme().bottomButton)
      Button('设置').height(44).layoutWeight(1).padding({ left: 8, right: 8 }).fontSize(12)
      .backgroundColor(this.isSettingsPage() ? this.colors().primary : this.colors().control)
      .fontColor(this.isSettingsPage() ? this.colors().primaryText : this.colors().body)
      .onClick(() => this.openSettings())
      .attributeModifier(this.isSettingsPage() ? this.theme().bottomPrimary : this.theme().bottomButton)
    }.width('100%').height('100%').padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
    .enabled(this.bottomBarVisible() && this.privacyStatus !== 'pending' && this.privacyStatus !== 'blocked')
    .hitTestBehavior(this.bottomBarVisible() ? HitTestMode.Default : HitTestMode.None)
  }
  build() {
    WithTheme({ theme: this.customTheme(), colorMode: this.colorMode === 'day' ? ThemeColorMode.LIGHT : ThemeColorMode.DARK }) {
      Stack() {
        // The full-page decoration is a sibling of Navigation, so it reaches both system bars.
        this.ambientBackground()
        Column() {
          Navigation(this.pageStack) {
            Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
              // Library, accounts and settings share the same persistent native floating bar.
              TabContent() {
                Stack() {
                  Scroll(this.scroller) {
                    Column({ space: 16 }) {
                      if ((this.privacyStatus === 'pending' || this.privacyStatus === 'blocked') && !this.isInfoPage()) {
                        this.privacyPrompt()
                      } else if (this.mainPage === 'privacy') { this.privacyPage()
                      } else if (this.mainPage === 'about') { this.aboutPage()
                      } else if (this.mainPage === 'support') { this.supportPage()
                      } else if (this.mainPage === 'settings') {
                        this.settings()
                      } else if (this.mainPage === 'accounts') {
                        this.accounts()
                      } else {
                        if (this.libraryMessage) {
                          Text(this.libraryMessage).fontSize(12).fontColor(this.colors().secondary).lineHeight(20).width('100%')
                        }
                        if (this.errorText) {
                          Text(this.errorText + ' 当前保留上次显示的数据。').fontSize(13).fontColor(this.colors().dangerText).lineHeight(21)
                          .padding(14).backgroundColor(this.colors().dangerBackground).borderRadius(12).width('100%')
                        }
                        Stack({ alignContent: Alignment.TopEnd }) {
                          Stack() {}.width(200).height(200)
                          .radialGradient({ center: ['50%', '50%'], radius: 100, colors: [[this.colors().glowBlue, 0], ['#00000000', 1]] })
                          .translate({ x: 45, y: -55 }).hitTestBehavior(HitTestMode.None)
                          Column({ space: 18 }) {
                            Row({ space: 12 }) {
                              Stack() {
                                Text(this.library.player.name.substring(0, 1).toUpperCase()).fontSize(22)
                                .fontWeight(FontWeight.Bold).fontColor(this.colors().iconText)
                                if (this.library.player.avatarUrl && this.hasConsent()) {
                                  Image(this.library.player.avatarUrl).width(52).height(52).objectFit(ImageFit.Cover)
                                  .autoResize(false).interpolation(ImageInterpolation.High).borderRadius(26)
                                }
                              }.width(52).height(52).backgroundColor(this.colors().control).borderRadius(26)
                              .border({ width: 1, color: this.colors().shine })
                              .shadow({ radius: 12, color: this.colors().glowBlue, offsetY: 3 })
                              Column({ space: 5 }) {
                                Text(this.library.player.name).fontSize(19).fontWeight(FontWeight.Bold).fontColor(this.colors().text).maxLines(2).width('100%')
                                Text(this.library.demo ? '演示模式 · 示例数据' : (this.library.player.steamId ? 'SteamID ' + this.library.player.steamId : '填写账号后同步昵称和头像'))
                                .fontSize(10).fontColor(this.colors().statsSubtitle).width('100%')
                              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                            }.width('100%')
                            Column({ space: 7 }) {
                              Text('累计游玩时光').fontSize(12).fontColor(this.colors().secondary).width('100%')
                              Row({ space: 8 }) {
                                Text(formatHours(this.library.totalMinutes)).fontSize(40).fontWeight(FontWeight.Bold)
                                .fontColor(this.colors().text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                                Text(this.library.totalMinutes === null ? '时长未返回' : '小时').fontSize(13).fontColor(this.colors().secondary).padding({ bottom: 5 })
                              }.width('100%').alignItems(VerticalAlign.Bottom)
                            }.width('100%')
                            Row({ space: 12 }) {
                              Column({ space: 7 }) {
                                Text(this.library.gameCount === null ? '不可用' : this.library.gameCount.toString())
                                .fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.colors().text).maxLines(1)
                                .textOverflow({ overflow: TextOverflow.Ellipsis })
                                Text('已返回游戏').fontSize(11).fontColor(this.colors().secondary)
                              }.padding(14).backgroundColor(this.panelColor(this.colors().surface)).borderRadius(18).alignItems(HorizontalAlign.Start).layoutWeight(1)
                              .border({ width: 1, color: this.panelColor(this.colors().edge) })
                              Column({ space: 7 }) {
                                Text(formatHours(this.library.recentMinutes)).fontSize(24).fontWeight(FontWeight.Bold)
                                .fontColor(this.colors().text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                                Text('最近两周小时').fontSize(11).fontColor(this.colors().secondary)
                              }.padding(14).backgroundColor(this.panelColor(this.colors().surface)).borderRadius(18).alignItems(HorizontalAlign.Start).layoutWeight(1)
                              .border({ width: 1, color: this.panelColor(this.colors().edge) })
                            }.width('100%')
                            if (!this.library.demo && this.library.fetchedAt) {
                              Text('更新于 ' + new Date(this.library.fetchedAt).toLocaleString()).fontSize(10).fontColor(this.colors().secondary).width('100%')
                            }
                          }.padding(22).width('100%')
                        }.width('100%').borderRadius(28).clip(true)
                        .linearGradient({ angle: 135, colors: [[this.panelColor(this.colors().stats), 0], [this.panelColor(this.colors().heroEnd), 1]] })
                        .border({ width: 1, color: this.panelColor(this.colors().shine) })
                        .shadow({ radius: 24, color: this.panelColor(this.colors().shadow), offsetY: 8 })
                        if (this.library.familyStatus === 'available') {
                          Text('个人 ' + this.library.games.filter((game: Game) => game.source !== 'family').length.toString() + ' 款 · 家庭共享 ' + this.library.games.filter((game: Game) => game.source === 'family').length.toString() + ' 款')
                          .fontSize(12).fontColor(this.colors().success).width('100%')
                        }
                        Row() {
                          Text('游戏库').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.colors().text).layoutWeight(1)
                          Text(this.visibleGames().length.toString() + ' 款').fontSize(12).fontColor(this.colors().softText)
                          .padding({ left: 11, right: 11, top: 5, bottom: 5 }).backgroundColor(this.colors().control).borderRadius(14)
                        }.width('100%')
                        Column({ space: 12 }) {
                          Select([{ value: '全部游戏' }, { value: '个人游戏' }, { value: '家庭共享' }])
                          .selected(this.sourceFilter).value(this.sourceFilter === 0 ? '全部游戏' : (this.sourceFilter === 1 ? '个人游戏' : '家庭共享'))
                          .fontColor(this.colors().body).backgroundColor(this.colors().control).font({ size: 12 }).width('100%')
                          .onSelect((index: number) => { this.sourceFilter = index; this.visibleLimit = 60; this.selected = null; })
                          .attributeModifier(this.theme().select)
                          TextInput({ text: this.search, placeholder: '搜索游戏名称' }).height(44).fontColor(this.colors().text)
                          .placeholderColor(this.colors().placeholder).backgroundColor(this.colors().input)
                          .onChange((value: string) => { this.search = value; this.visibleLimit = 60; })
                          .onFocus(() => this.editingInput = true).onBlur(() => this.editingInput = false)
                          Row({ space: 8 }) {
                            Select([{ value: '累计时长' }, { value: '两周时长' }, { value: '游戏名称' }, { value: '最近游玩' }])
                            .selected(this.sort).value(this.sort === 0 ? '累计时长' : (this.sort === 1 ? '两周时长' : (this.sort === 2 ? '游戏名称' : '最近游玩')))
                            .fontColor(this.colors().body).backgroundColor(this.colors().control).font({ size: 12 })
                            .onSelect((index: number) => this.changeSort(index)).layoutWeight(1)
                            .attributeModifier(this.theme().select)
                            Text('最近玩过').fontSize(12).fontColor(this.colors().secondary)
                            Toggle({ type: ToggleType.Switch, isOn: this.onlyRecent }).selectedColor(this.colors().switchTrack)
                            .onChange((value: boolean) => { this.onlyRecent = value; this.visibleLimit = 60; })
                            .attributeModifier(this.theme().toggle)
                          }.width('100%')
                        }.padding(16).width('100%').backgroundColor(this.panelColor(this.colors().surface)).borderRadius(22)
                        .border({ width: 1, color: this.panelColor(this.colors().edge) })
                        .shadow({ radius: 12, color: this.panelColor(this.colors().rowShadow), offsetY: 4 })
                        if (this.library.libraryStatus === 'unavailable' && this.library.games.length === 0) {
                          Text('游戏库暂不可用\n请检查 Steam 的游戏详情隐私设置。').fontSize(14).fontColor(this.colors().secondary)
                          .textAlign(TextAlign.Center).lineHeight(23).padding(24).width('100%')
                        } else if (this.visibleGames().length === 0) {
                          Text(this.library.games.length === 0 ? 'Steam 未返回任何游戏。' : '没有符合筛选条件的游戏。')
                          .fontSize(14).fontColor(this.colors().secondary).padding(24).width('100%')
                        }
                        ForEach(this.visibleGames().slice(0, this.visibleLimit), (game: Game) => {
                          this.gameRow(game)
                          if (this.selected !== null && (this.selected as Game).appId === game.appId) {
                            this.detail(game)
                          }
                        }, (game: Game) => this.library.player.steamId + ':' +
                        (this.library.demo ? 'demo' : this.library.fetchedAt) + ':' + game.appId.toString())
                        if (this.visibleGames().length > this.visibleLimit) {
                          Button('加载更多游戏').backgroundColor(this.colors().control).fontColor(this.colors().body).width('100%')
                          .onClick(() => this.visibleLimit += 60)
                          .attributeModifier(this.theme().button)
                        }
                        ForEach(this.library.notices, (notice: string) => {
                          Text(notice).fontSize(11).fontColor(this.colors().notice).lineHeight(18).width('100%')
                        }, (notice: string) => notice)
                        Text('基于 Steam 公开数据 · 非 Valve 官方应用').fontSize(10).fontColor(this.colors().muted).padding({ top: 8, bottom: 12 })
                      }
                    }.padding({ left: 20, right: 20, top: this.theme().enabled ? 92 : 12, bottom: 112 }).width('100%')
                  }.height('100%').width('100%').scrollBar(BarState.Off)
                  // Extend the viewport itself; expanding only decoration leaves a clipped strip above the home indicator.
                  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
                  .attributeModifier(this.statusBarScrollStyle)
                  .onDidScroll((_x: number, _y: number, state: ScrollState) => this.contentDidScroll(state))
                  .onScrollStop(() => this.contentDidScroll(ScrollState.Idle))
                }.width('100%').height('100%')
                .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

              }.tabBar(this.bottomActions).clip(false)
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
            }.width('100%').height('100%').backgroundColor('#00000000').vertical(false).scrollable(false).barMode(BarMode.Fixed)
            .barHeight(this.bottomBarLayoutVisible() ? 64 : 0).divider({ strokeWidth: 0, color: '#00000000', startMargin: 0, endMargin: 0 })
            .barOverlap(true)
            // Overlap must not add a full-width legacy blur behind the official floating capsule.
            .barBackgroundBlurStyle(BlurStyle.NONE)
            .barBackgroundColor(this.theme().enabled ? undefined : this.colors().settings)
            .attributeModifier(this.theme().tabsStyle(this.bottomBarLayoutVisible(), this.viewportWidth))
            .onAppear(() => { this.bottomBarMotion.reset(); this.bottomBarMounted = true; this.syncBottomBar(false); })
            .onDisAppear(() => { this.bottomBarMounted = false; this.bottomBarMotion.reset(); })
          }.width('100%').height('100%').backgroundColor('#00000000').mode(NavigationMode.Stack).hideBackButton(true)
          .titleMode(NavigationTitleMode.Mini)
          .title({ builder: this.pageTitle, height: 80 }, this.theme().titleOptions())
          .navDestination(this.destination)
          .onAppear(() => this.navigation.markReady())
        }.width('100%').height('100%').backgroundColor('#00000000')
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          const width: number = Number(newArea.width);
          if (Number.isFinite(width) && width > 0 && Math.abs(this.viewportWidth - width) > 0.5) this.viewportWidth = width;
        })
      }.width('100%').height('100%').backgroundColor(this.colors().background)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }
}
