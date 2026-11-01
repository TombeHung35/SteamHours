import { privacyAccess } from '../model/PrivacyAccess';
import { AppearanceMode, AppColors, colorsFor } from '../model/Appearance';
import { webview } from '@kit.ArkWeb';
import { ImmersiveTheme, immersiveFor } from './ImmersiveStyle';
import { STEAM_LOGIN_URL, STEAM_TOKEN_URL, extractFamilyToken, isSteamLoginUrl } from '../model/FamilyData';

@Component
export struct FamilyLogin {
  onAuthorized: (token: string) => void = () => {};
  onClosed: () => void = () => {};
  @State private message: string = '请在 Steam 官方页面登录本人账号。完成后点击“完成登录”。';
  @State private reading: boolean = false;
  @State private webReady: boolean = false;
  @Prop colorMode: AppearanceMode = 'night';
  @Prop themeColor: string = '';

  private colors(): AppColors { return colorsFor(this.colorMode, this.themeColor); }
  private theme(): ImmersiveTheme { return immersiveFor(this.colorMode, this.themeColor); }
  private active: boolean = true;
  private privacyGeneration: number = privacyAccess.begin();
  aboutToDisappear(): void { this.active = false; this.unregister(); try { this.controller.stop(); this.controller.removeCache(true); } catch (_) {} }
  private controller: webview.WebviewController = new webview.WebviewController();
  private unregister: () => void = privacyAccess.register((): void => {
    this.active = false; try { this.controller.stop(); } catch (_) {}
  }, this.privacyGeneration);

  private requestAuthorization(): void {
    if (!privacyAccess.current(this.privacyGeneration) || !this.webReady || this.reading) return;
    try {
      this.reading = true;
      this.message = '正在读取 Steam 登录授权…';
      this.controller.loadUrl(STEAM_TOKEN_URL);
    } catch (_) {
      this.reading = false;
      this.message = '登录页面暂不可用，请返回后重试。';
    }
  }

  private async pageEnded(url: string): Promise<void> {
    if (!this.reading || !this.active || !privacyAccess.current(this.privacyGeneration)) return;
    if (url !== STEAM_TOKEN_URL) {
      this.reading = false;
      this.message = '请先完成 Steam 官方页面登录，再点击“完成登录”。';
      return;
    }
    try {
      // Verify again inside JS to protect against a navigation racing this callback.
      const result: string = await this.controller.runJavaScript(
        "location.href === '" + STEAM_TOKEN_URL + "' ? document.body.innerText : ''");
      if (!this.active || !privacyAccess.current(this.privacyGeneration)) return;
      const token: string = extractFamilyToken(result);
      this.controller.removeCache(true);
      this.onAuthorized(token);
    } catch (_) {
      if (!this.active || !privacyAccess.current(this.privacyGeneration)) return;
      this.reading = false;
      this.message = '尚未取得授权，请完成 Steam 登录后重试。';
      try { this.controller.loadUrl(STEAM_LOGIN_URL); } catch (_) {}
    }
  }

  @Builder
  private loginTitle() {
      Row({ space: 10 }) {
        Text('Steam 家庭登录').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.colors().text).layoutWeight(1)
        Button('返回').height(38).fontSize(12).backgroundColor(this.colors().control).fontColor(this.colors().body).onClick(() => this.onClosed())
          .attributeModifier(this.theme().button)
      }.width('100%').height('100%').padding({ left: 16, right: 16 })
  }

  build() {
    Stack() {
      Navigation() {
      Column({ space: 12 }) {
        Text('store.steampowered.com · Steam 官方页面').fontSize(12).fontColor(this.colors().accent).width('100%')
        Text(this.message).fontSize(12).fontColor(this.colors().body).lineHeight(19).width('100%')
        Button(this.reading ? '正在授权…' : '完成登录').width('100%').backgroundColor(this.colors().primary).fontColor(this.colors().primaryText)
          .enabled(this.webReady && !this.reading).onClick(() => this.requestAuthorization())
          .attributeModifier(this.theme().primary)
        Stack() {
          Web({ src: STEAM_LOGIN_URL, controller: this.controller })
            .javaScriptAccess(true).domStorageAccess(true)
            .visibility(this.reading ? Visibility.Hidden : Visibility.Visible)
            .onControllerAttached(() => this.webReady = true)
            .onLoadIntercept((event) => {
              if (!privacyAccess.current(this.privacyGeneration)) return true;
              if (event && event.data.isMainFrame() && !isSteamLoginUrl(event.data.getRequestUrl())) {
                this.message = '登录仅允许打开 Steam 官方网站。';
                return true;
              }
              return false;
            })
            .onPageEnd((event) => { if (event) this.pageEnded(event.url); })
            .onErrorReceive((event) => {
              if (event && event.request.isMainFrame()) {
                this.reading = false;
                this.message = '无法加载 Steam 页面，请检查网络后重试。';
              }
            })
            .width('100%').height('100%')
          if (this.reading) {
            Text('正在获取授权，登录令牌不会显示在页面上。').fontSize(14).fontColor(this.colors().body)
          }
        }.layoutWeight(1).width('100%').backgroundColor(this.colors().surface).borderRadius(20)
          .border({ width: 1, color: this.colors().edge }).clip(true)
          .shadow({ radius: 16, color: this.colors().shadow, offsetY: 4 })
      }.padding({ left: 16, right: 16, top: this.theme().enabled ? 88 : 16, bottom: 16 })
        .width('100%').height('100%').backgroundColor(this.colors().background)
      }.width('100%').height('100%').backgroundColor(this.colors().background)
        .mode(NavigationMode.Stack).hideBackButton(true).titleMode(NavigationTitleMode.Mini)
        .title({ builder: () => this.loginTitle(), height: 72 }, this.theme().titleOptions())
    }.width('100%').height('100%').backgroundColor(this.colors().background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
