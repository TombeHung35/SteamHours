import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

// Run the real ArkUI compiler output, including accounts(), bottomActions() and initialRender().
// Compile assembleHap first. Only platform rendering and service effects are mocked.
const compiledPath = process.env.STEAM_HOURS_COMPILED_INDEX ?? new URL(
  '../harmony/entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/Index.ts', import.meta.url);
const compiled = readFileSync(compiledPath, 'utf8').replace(/^import[^\n]*\n/gm, '');
const appearance = readFileSync(new URL('../harmony/entry/src/main/ets/model/Appearance.ets', import.meta.url), 'utf8').replace(/\bexport /g, '');
const scrollStyle = readFileSync(new URL('../harmony/entry/src/main/ets/components/StatusBarScrollStyle.ets', import.meta.url), 'utf8')
  .replace(/^import[^\n]*\n/gm, '').replace(/\bexport /g, '');
const librarySource = readFileSync(new URL('../harmony/entry/src/main/ets/model/Library.ets', import.meta.url), 'utf8').replace(/\bexport /g, '');
const libraryModel = runInNewContext(stripTypeScriptTypes(librarySource) + '\n;({ demoLibrary, emptyLibrary, formatHours })');
const compiledFamily = readFileSync(new URL('../harmony/entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/components/FamilyLogin.ts', import.meta.url), 'utf8')
  .replace(/^import[^\n]*\n/gm, '').replace(/\bexport /g, '');
const paletteModel = runInNewContext(stripTypeScriptTypes(appearance) + '\n;({ colorsFor })');
const readEts = path => readFileSync(new URL('../harmony/entry/src/main/ets/' + path, import.meta.url), 'utf8').replace(/^import[^\n]*\n/gm, '').replace(/\bexport /g, '');
const steamDataModel = runInNewContext(stripTypeScriptTypes(readEts('model/SteamData.ets')) + '\n;({ parseAccount, validateApiKey })');
const extras = readEts('model/PrivacyAccess.ets') + '\n' + readEts('model/PrivacyPolicy.ets') + '\n' + readEts('model/BottomBarAutoHide.ets') + '\n' + readEts('components/BottomBarMotion.ets') + '\n' + readEts('model/SteamImages.ets') + '\n' + readEts('service/LibraryStore.ets');
const code = stripTypeScriptTypes(appearance + '\n' + scrollStyle + '\n' + extras + '\n' + compiledFamily + '\n' + compiled) + '\n;({ Index, FamilyLogin, StatusBarScrollStyle, LibraryStore, BottomBarAutoHide, BottomBarMotion, privacyAccess })';

function mount(overrides = {}) {
  const rows = { inputs: [], buttons: [], toggles: [], sliders: [], texts: [], images: [] };
  const calls = [];
  const native = { tabBars: 0, tabBackground: 'unset', foregroundBlurs: [], backToTopCalls: [], imageErrors: [], safeAreas: [], tabClips: [], trace: [], navigationColors: [], webCreates: [], barHeights: [], overlaps: [], tabBlurStyles: [], tabDividers: [], panelBackgrounds: [], panelBorders: [], panelShadows: [], panelGradients: [], panelOpacities: [], tabsAppear: null, tabsDisappear: null, scrollCallback: null, stopCallback: null, animations: [], translations: [], opacities: [], rowHitTests: [], dialogs: [], copied: [], links: [], defaultThemes: [] };
  function control(collection, createName) {
    let current;
    return new Proxy({}, { get(_, method) {
      return (...args) => {
        if (method === createName || (createName === 'createWithLabel' && method === 'createWithChild')) {
          current = { value: args[0] }; collection.push(current);
        } else if (['onChange', 'onFocus', 'onBlur', 'onClick', 'enabled', 'backgroundColor', 'fontColor', 'attributeModifier'].includes(method)) {
          current[method] = args[0];
        }
      };
    } });
  }
  const passive = new Proxy({}, { get: () => () => {} });
  const tabContent = new Proxy({}, { get(_, method) {
    if (method === 'create') return callback => callback();
    if (method === 'tabBar') return () => { native.tabBars++; };
    if (method === 'expandSafeArea') return (...args) => native.safeAreas.push(['TabContent', ...args]);
    if (method === 'clip') return value => native.tabClips.push(value);
    return () => {};
  } });
  const tabs = new Proxy({}, { get(_, method) {
    if (method === 'divider') return value => native.tabDividers.push(value);
    if (method === 'barHeight') return value => native.barHeights.push(value);
    if (method === 'barBackgroundBlurStyle') return value => native.tabBlurStyles.push(value);
    if (method === 'barOverlap') return value => native.overlaps.push(value);
    if (method === 'onAppear') return callback => native.tabsAppear = callback;
    if (method === 'onDisAppear') return callback => native.tabsDisappear = callback;
    if (method === 'barBackgroundColor') return value => { native.tabBackground = value; };
    return () => {};
  } });
  class ViewPU { static create() {} }
  const scroll = new Proxy({}, { get(_, method) { return (...args) => {
    if (method === 'onDidScroll') native.scrollCallback = args[0];
    if (method === 'onScrollStop') native.stopCallback = args[0];
    if (method === 'attributeModifier') args[0].applyNormalAttribute(scroll);
    if (method === 'backToTop') native.backToTopCalls.push(args[0]);
    if (method === 'expandSafeArea') native.safeAreas.push(['Scroll', ...args]);
  }; } });
  const navigation = new Proxy({}, { get(_, method) { return (...args) => {
    if (method === 'create') native.trace.push('navigation');
    if (method === 'backgroundColor') native.navigationColors.push(args[0]);
    if (method === 'expandSafeArea') native.safeAreas.push(['Navigation', ...args]);
  }; } });
  const { Index, FamilyLogin, StatusBarScrollStyle, LibraryStore, BottomBarAutoHide, BottomBarMotion, privacyAccess } = runInNewContext(code, {
    parseAccount: steamDataModel.parseAccount, validateApiKey: steamDataModel.validateApiKey, TransitionType: { All: 0 },
    SafeAreaType: { SYSTEM: 1, KEYBOARD: 2 }, SafeAreaEdge: { TOP: 0, BOTTOM: 1 },
    STEAM_TOKEN_URL:'https://store.steampowered.com/pointssummary/ajaxgetasyncconfig',
    Visibility: { Visible: 0, Hidden: 1 }, STEAM_LOGIN_URL: 'https://store.steampowered.com/login/',
    Web: new Proxy({}, { get(_, method) { return (...args) => {
      if (method === 'create') native.webCreates.push(args[0]);
      if (method === 'expandSafeArea') native.safeAreas.push(['Web', ...args]);
    }; } }),
    deviceInfo: { sdkApiVersion: overrides.platformSdk ?? 26 }, $r: value => value,
    HorizontalAlign: { Start: 0, Center: 1, End: 2 }, Divider: passive,
    TextOverflow: { Ellipsis: 1 }, TextAlign: { Center: 1 }, Progress: passive, ProgressType: { Linear: 1 }, HoverEffect: { Scale: 1 },
    formatHours: libraryModel.formatHours,
    curves: { springMotion: (response, damping, overlap) => ({response, damping, overlap}) }, Curve: { EaseInOut: 'ease-in-out' }, ScrollState: { Idle: 0, Scroll: 1, Fling: 2 }, TabsController: class {},
    pasteboard:{MIMETYPE_TEXT_PLAIN:'text/plain',createData:(_,text)=>text,getSystemPasteboard:()=>({setData:async data=>native.copied.push(data)})},
    ThemeControl:{setDefaultTheme:theme=>native.defaultThemes.push(theme)},applyAppearance:async()=>{},
    ViewPU, NavPathStack: class {}, registerNamedRoute: () => {},
    Column: new Proxy({}, {get(_,method){return value=>{
      if(method==='backgroundColor')native.panelBackgrounds.push(value);
      if(method==='border')native.panelBorders.push(value);
      if(method==='shadow')native.panelShadows.push(value);
      if(method==='opacity')native.panelOpacities.push(value);
    };}}), Row: new Proxy({}, { get(_, method) { return value => { if(method === 'hitTestBehavior') native.rowHitTests.push(value); }; } }), Text: control(rows.texts, 'create'), If: passive,
    WithTheme: passive, Navigation: navigation, Tabs: tabs, TabContent: tabContent, Stack: new Proxy({}, { get(_, method) { return (...args) => {
      if (method === 'linearGradient') native.panelGradients.push(args[0]);
      if (method === 'foregroundBlurStyle') { native.foregroundBlurs.push(args); native.trace.push('decoration'); }
      if (method === 'expandSafeArea') native.safeAreas.push(['Stack', ...args]);
    }; } }), Scroll: scroll, Image: new Proxy({}, { get(_, method) { return (...args) => {
      if (method === 'create') rows.images.push(args[0]);
      if (method === 'onError') native.imageErrors.push(args[0]);
      if (method === 'expandSafeArea') native.safeAreas.push(['Image', ...args]);
    }; } }), Select: passive, ForEach: passive,
    Slider: control(rows.sliders, 'create'), SliderChangeMode: { Begin: 0, Moving: 1, End: 2, Click: 3 },
    emptyLibrary: () => libraryModel.emptyLibrary(), preferences: overrides.preferences,
    ImageInterpolation: { Medium: 2, High: 3 }, ImageFit: { Cover: 1, Contain: 2 }, Alignment: { TopEnd: 1, Start: 2 }, HitTestMode: { None: 0, Default: 1 },
    BlurStyle: { Thin: 0, NONE: 6 },
    ThemeColorMode: { LIGHT: 0, DARK: 1 }, BarPosition: { End: 1 }, BarState: { Off: 0 },
    BarMode: { Fixed: 0 }, NavigationMode: { Stack: 0 }, NavigationTitleMode: { Mini: 0 },
    VerticalAlign: { Center: 0 },
    TextInput: control(rows.inputs, 'create'), Button: control(rows.buttons, 'createWithLabel'),
    Toggle: control(rows.toggles, 'create'), FontWeight: { Bold: 700 },
    InputType: { Password: 1 }, ToggleType: { Switch: 1 },
    demoLibrary: () => ({ ...libraryModel.demoLibrary(), marker: 'demo' })
  });
  privacyAccess.setAllowed((overrides.privacyStatus ?? 'granted') === 'granted');
  const owner = Object.create(Index.prototype);
  const values = {
    privacyStatus:'granted', privacyMessage:'',privacyBusy:false,librarySaving:false,infoReturnPage:'settings',supportMessage:'',dataGeneration:0,privacyStore:{choose:async()=>{}},localDataCleaner:{clear:async()=>{}},
    artworkUrls:{},artworkAttempted:new Set(),artworkLoading:false,artworkApi:{load:async()=>({}),clearCache(){}},
    prefs: null, account: 'parent-account', apiKey: 'test-only-key', familyToken: '',
    includeFamily: false, rememberKey: true, loading: false, settingsReady: true,
    savingSettings: false, settingsMessage: '', errorText: '', editingInput: false,
    colorMode: 'night', themeColor: '', themeColorDraft: '', imageThemePalette: [], imageThemeMessage: '', appearanceMessage: '', personalizationBusy: false, appearanceSaving: false, backgroundPath: '', backgroundOpacity: 0.22, panelTransparency: 0.25, foregroundBlurStrength: 0.4, library: { demo: true }, mainPage: 'accounts',
    bottomBarScrollHidden: false, bottomBarMotionSupported: (overrides.platformSdk ?? 26) >= 13, bottomBarMounted: false, bottomBarTracker: new BottomBarAutoHide(), bottomBarMotion: new BottomBarMotion(),
    tabsController: { setTabBarTranslate: value => native.translations.push(value), setTabBarOpacity: value => native.opacities.push(value) },
    keyboardObserved: false, keyboardVisible: false, viewportWidth: 360, pageStack: {}, scroller: {}, statusBarScrollStyle: new StatusBarScrollStyle(),
    search: '', onlyRecent: false, sourceFilter: 0, selected: null, visibleLimit: 60, sort: 0,
    libraryMessage: '', artworkFailures: {}, achievementAppId: 0, achievementData: null, achievementError: '', achievementLoading: false, achievementLimit: 30, achievementRequest: 0, sortWrites: Promise.resolve(),
    libraryStore: { save: async () => {}, readSort: async () => 0, read: async () => null, clear: async () => {}, saveSort: async () => {} },
    achievementsApi: { clearCache: () => {} },
    observeComponentCreation2: callback => callback(1, true),
    forEachUpdateFunction: (_, items, callback) => items.forEach(callback),
    getUIContext: () => ({ getHostContext: () => ({startAbility:async want=>native.links.push(want)}), showAlertDialog: options=>native.dialogs.push(options), animateTo: (options, callback) => { native.animations.push(options); callback(); } }),
    ifElseBranchUpdateFunction: (_, callback) => callback(),
    colors: () => ({ primary: '#4963C9', control: '#EDF2FA', primaryText: '#FFFFFF', body: '#1D2942', settings: '#E9F0FA' }),
    theme: () => ({ primary: 'primary-material', button: 'neutral-material', bottomPrimary: 'primary-material', bottomButton: 'neutral-material', enabled: false, tabsStyle: () => ({}), titleOptions: () => ({}) }),
    ambientBackground: () => {},
    api: { clearCache: () => calls.push('clearCache') },
    navigation: { openFamily: () => calls.push('openFamily'), returnLibrary: () => calls.push('returnLibrary'), back: () => false },
    returnToTop: () => calls.push('returnToTop'),
    ...overrides
  };
  for (const action of ['loadLibrary', 'saveSettings', 'clearKey', 'clearFamily']) {
    values[action] = () => calls.push(action);
  }
  for (const [key, value] of Object.entries(values)) {
    Object.defineProperty(owner, key, { value, writable: true, configurable: true });
  }
  owner.accounts();
  function family(mode) {
    const login = Object.create(FamilyLogin.prototype);
    const familyValues = { privacyGeneration:privacyAccess.begin(), active:true,colorMode: mode, themeColor: '', message: 'test-login-message', reading: false,
      webReady: false, controller: {},unregister:()=>{}, colors: () => paletteModel.colorsFor(mode), theme: values.theme,
      observeComponentCreation2: values.observeComponentCreation2, ifElseBranchUpdateFunction: values.ifElseBranchUpdateFunction };
    for (const [key, value] of Object.entries(familyValues)) Object.defineProperty(login, key, { value, writable: true, configurable: true });
    return login;
  }
  return { owner, rows, calls, native, family, privacyAccess, createLibraryStore: () => new LibraryStore() };
}

test('Compiled account form renders on its main-page owner', () => {
  const { rows, owner } = mount();
  assert.equal(owner.mainPage, 'accounts');
  assert.equal(rows.inputs.length, 2);
  assert.equal(rows.buttons.length, 6);
  assert.equal(rows.inputs[0].value.text, 'parent-account');
  assert.equal(rows.inputs[1].value.text, 'test-only-key');
});

test('Compiled account input, focus and toggles update the parent state and services', () => {
  const { owner, rows, calls } = mount();
  rows.inputs[0].onChange('new-account'); rows.inputs[1].onChange('new-test-key');
  rows.inputs[0].onFocus(); assert.equal(owner.editingInput, true);
  rows.inputs[0].onBlur(); assert.equal(owner.editingInput, false);
  rows.toggles[0].onChange(false); rows.toggles[1].onChange(true);
  assert.equal(owner.account, 'new-account'); assert.equal(owner.apiKey, 'new-test-key');
  assert.equal(owner.rememberKey, false); assert.equal(owner.includeFamily, true);
  assert.deepEqual(calls, ['clearCache']);
});

test('Compiled account buttons invoke parent actions; demo returns to the sibling library page', () => {
  const { owner, screen, rows, calls } = mount();
  const click = label => rows.buttons.find(button => button.value === label).onClick();
  click('读取游戏库'); click('保存账号'); click('清除密钥');
  click('登录 Steam'); click('移除家庭授权'); click('查看演示');
  assert.deepEqual(calls, ['loadLibrary', 'saveSettings', 'clearKey', 'openFamily', 'clearFamily', 'returnLibrary', 'returnToTop']);
  assert.equal(owner.library.marker, 'demo'); assert.equal(owner.visibleLimit, 60);
});

test('Compiled account controls use current parent loading/saving/readiness on each render', () => {
  for (const state of [{ settingsReady: false }, { loading: true }, { savingSettings: true }, {}]) {
    const { owner, rows } = mount(state);
    const ready = !(owner.loading || owner.savingSettings || !owner.settingsReady);
    assert.ok([...rows.inputs, ...rows.buttons, ...rows.toggles].every(row => row.enabled === ready));
    owner.loading = !ready; owner.settingsReady = true; owner.savingSettings = false;
    for (const collection of Object.values(rows)) collection.length = 0;
    owner.accounts();
    assert.ok([...rows.inputs, ...rows.buttons, ...rows.toggles].every(row => row.enabled === !owner.loading));
  }
});
test('Each main page emphasizes exactly one bottom button in both paint and system material', () => {
  for (const page of ['library', 'accounts', 'settings']) {
    const { owner, rows } = mount({ mainPage: page }); rows.buttons.length = 0;
    owner.bottomActions();
    assert.equal(rows.buttons.length, 3);
    const selected = ['library', 'accounts', 'settings'].indexOf(page);
    for (let i = 0; i < 3; i++) {
      assert.equal(rows.buttons[i].backgroundColor, i === selected ? owner.colors().primary : owner.colors().control);
      assert.equal(rows.buttons[i].attributeModifier, i === selected ? 'primary-material' : 'neutral-material');
    }
  }
});

test('Bottom accounts/settings buttons switch sibling pages without pushing or popping history', () => {
  const { owner, rows, calls } = mount({ mainPage: 'library', selected: { marker: 'game' } });
  rows.buttons.length = 0; owner.bottomActions();
  rows.buttons[1].onClick(); assert.equal(owner.mainPage, 'accounts'); assert.equal(owner.selected, null);
  rows.buttons[2].onClick(); assert.equal(owner.mainPage, 'settings');
  rows.buttons[2].onClick(); assert.equal(owner.mainPage, 'settings');
  assert.deepEqual(calls, ['returnToTop', 'returnToTop']);
});

test('Library button switches from accounts/settings without querying and reads only on the library page', () => {
  for (const page of ['accounts', 'settings']) {
    const { owner, rows, calls } = mount({ mainPage: page }); rows.buttons.length = 0; owner.bottomActions();
    assert.equal(rows.buttons[0].value, '游戏库'); rows.buttons[0].onClick();
    assert.equal(owner.mainPage, 'library'); assert.deepEqual(calls, ['returnLibrary', 'returnToTop']);
    rows.buttons.length = 0; owner.bottomActions(); rows.buttons[0].onClick(); assert.equal(calls.at(-1), 'loadLibrary');
  }
});

test('Root rendering chooses only the selected main page and keeps native Tabs on accounts/settings', () => {
  for (const page of ['accounts', 'settings']) {
    const { owner, calls, native } = mount({ mainPage: page });
    owner.accounts = () => calls.push('accounts-page'); owner.settings = () => calls.push('settings-page');
    owner.initialRender();
    assert.deepEqual(calls, [page + '-page']); assert.equal(native.tabBars, 1);
  }
});

test('System back and missing-key navigation select root pages without an account destination', () => {
  const { owner, calls } = mount({ mainPage: 'settings' });
  assert.equal(owner.onBackPress(), true); assert.equal(owner.mainPage, 'library');
  owner.requireAccounts(); assert.equal(owner.mainPage, 'accounts');
  owner.requireAccounts(); assert.equal(owner.mainPage, 'accounts');
  assert.deepEqual(calls, ['returnLibrary', 'returnToTop', 'returnToTop']);
});

test('Root native Tabs clears its extra background under official material and preserves the fallback color', () => {
  for (const enabled of [true, false]) {
    const { owner, native } = mount({
      theme: () => ({ enabled, primary: 'primary-material', button: 'neutral-material', bottomPrimary: 'primary-material', bottomButton: 'neutral-material', tabsStyle: () => ({}), titleOptions: () => ({}) })
    });
    owner.initialRender();
    assert.equal(native.tabBackground, enabled ? undefined : owner.colors().settings);
    assert.equal(native.tabBars, 1);
  }
});


test('Compiled settings offers system image extraction and palette actions with the existing theme save path', () => {
  const { owner, rows, calls } = mount({ imageThemePalette: ['#123456', '#FFFFFF', '#000000'] });
  rows.buttons.length = 0;
  owner.chooseImageTheme = () => calls.push('chooseImageTheme');
  owner.saveThemeColor = color => calls.push(color);
  owner.settings();
  const pick = rows.buttons.find(button => button.value === '从图片取主题色');
  assert.equal(pick.enabled, true); pick.onClick();
  for (const color of owner.imageThemePalette) {
    const button = rows.buttons.find(button => button.value === color);
    assert.equal(button.backgroundColor, color); assert.equal(button.enabled, true); button.onClick();
  }
  assert.deepEqual(calls, ['chooseImageTheme', '#123456', '#FFFFFF', '#000000']);
});

test('Compiled image extraction keeps the active theme/background until a palette color is explicitly applied', async () => {
  const { owner } = mount({ themeColor: '#123456', backgroundPath: '/existing-background',
    imageThemePicker: { chooseColors: async () => ['#FFFFFF', '#000000'] } });
  await owner.chooseImageTheme();
  assert.equal(owner.themeColor, '#123456'); assert.equal(owner.backgroundPath, '/existing-background');
  assert.deepEqual(Array.from(owner.imageThemePalette), ['#FFFFFF', '#000000']);
  assert.equal(owner.personalizationBusy, false);
  owner.personalizationStore = { saveColor: async (_, color) => color };
  await owner.saveThemeColor(owner.imageThemePalette[0]);
  assert.equal(owner.themeColor, '#FFFFFF'); assert.equal(owner.themeColorDraft, '#FFFFFF');
  assert.equal(owner.backgroundPath, '/existing-background');
});

test('Compiled extraction cancellation, errors and busy guards retain the current theme and previous palette', async () => {
  for (const behavior of [async () => null, async () => { throw new Error('bad image'); }]) {
    const { owner } = mount({ themeColor: '#123456', imageThemePalette: ['#ABCDEF'], imageThemePicker: { chooseColors: behavior } });
    await owner.chooseImageTheme(); assert.equal(owner.themeColor, '#123456');
    assert.deepEqual(Array.from(owner.imageThemePalette), ['#ABCDEF']); assert.equal(owner.personalizationBusy, false);
    assert.match(owner.imageThemeMessage, /当前主题色保留/);
  }
  for (const state of [{ personalizationBusy: true }, { settingsReady: false }]) {
    const { owner } = mount({ ...state, imageThemePicker: { chooseColors: () => { throw new Error('should not select'); } } });
    await owner.chooseImageTheme(); assert.equal(owner.imageThemeMessage, '');
  }
});

test('Compiled blur slider previews bounded strength and persists only at end/click', () => {
  const { owner, rows, calls } = mount();
  owner.saveForegroundBlur = value => calls.push(value); owner.settings();
  const slider = rows.sliders.find(row => row.value.step === 5);
  assert.equal(slider.value.min, 0); assert.equal(slider.enabled, true);
  slider.onChange(70, 1); assert.equal(owner.foregroundBlurStrength, 0.7); assert.deepEqual(calls, []);
  slider.onChange(70, 2); slider.onChange(0, 3);
  assert.deepEqual(calls, [70, 0]); assert.equal(owner.foregroundBlurStrength, 0);
});

test('Actual compiled decorative background uses one foreground material blur and clears it at zero in both modes', () => {
  for (const mode of ['day', 'night']) for (const strength of [0, 0.4, 1]) {
    const { owner, native } = mount({ colorMode: mode, foregroundBlurStrength: strength });
    delete owner.ambientBackground; owner.ambientBackground();
    assert.equal(native.foregroundBlurs.length, 1);
    const [style, options] = native.foregroundBlurs[0];
    assert.equal(style, strength === 0 ? 6 : 0); assert.equal(options.scale, strength);
    assert.equal(options.colorMode, mode === 'day' ? 0 : 1);
  }
});

test('A failed compiled palette save preserves the active color and releases the processing state', async () => {
  const { owner } = mount({ themeColor: '#123456', themeColorDraft: '#123456',
    personalizationStore: { saveColor: async () => { throw new Error('flush failed'); } } });
  await owner.saveThemeColor('#FFFFFF');
  assert.equal(owner.themeColor, '#123456'); assert.equal(owner.themeColorDraft, '#123456');
  assert.equal(owner.personalizationBusy, false); assert.match(owner.appearanceMessage, /未能保存/);
});


test('All compiled main pages attach official status-bar back-to-top to their shared Scroll with API 12 fallback', () => {
  for (const page of ['library', 'accounts', 'settings']) for (const platformSdk of [12, 15, 26]) {
    const { owner, native, calls } = mount({ mainPage: page, platformSdk, library: libraryModel.demoLibrary(), sort: 0, onlyRecent: false });
    owner.initialRender();
    assert.deepEqual(native.backToTopCalls, platformSdk >= 15 ? [true] : []);
    assert.equal(calls.includes('loadLibrary'), false); assert.equal(owner.mainPage, page);
  }
});

test('Compiled title for every main page renders without a back-to-top button', () => {
  for (const page of ['library', 'accounts', 'settings']) {
    const { owner, rows } = mount({ mainPage: page }); rows.buttons.length = 0;
    owner.pageTitle(); assert.equal(rows.buttons.length, 0);
  }
});


test('Compiled main pages extend the entire scroll drawing chain to the home indicator while keeping decoration outside Navigation', () => {
  for (const page of ['library', 'accounts', 'settings']) for (const mode of ['day', 'night']) {
    const { owner, native } = mount({ mainPage: page, colorMode: mode, library: libraryModel.demoLibrary(), sort: 0, onlyRecent: false,
      colors: () => paletteModel.colorsFor(mode) });
    delete owner.ambientBackground; owner.initialRender();
    assert.ok(native.trace.indexOf('decoration') < native.trace.indexOf('navigation'));
    assert.deepEqual(native.navigationColors, ['#00000000']);
    assert.equal(native.foregroundBlurs.length, 1);
    assert.equal(native.safeAreas.filter(([, , edges]) => Array.from(edges).join(',') === '0,1').length, 2);
    const content = native.safeAreas.filter(([, , edges]) => Array.from(edges).join(',') === '1');
    assert.deepEqual(content.map(event => event[0]).sort(), ['Scroll', 'Stack', 'TabContent']);
    assert.ok(native.safeAreas.every(([, types]) => Array.from(types).join(',') === '1'));
    assert.deepEqual(native.tabClips, [false]);
    assert.equal(native.backToTopCalls.length, 1);
  }
});

test('Custom background and scroll extend system drawing without expanding controls or the keyboard area', () => {
  for (const keyboardVisible of [false, true]) {
    const { owner, native } = mount({ backgroundPath: '/test-background.jpg', keyboardObserved: true, keyboardVisible,
      library: libraryModel.demoLibrary(), mainPage: 'settings' });
    delete owner.ambientBackground; owner.initialRender();
    assert.equal(native.safeAreas.filter(event => event[0] === 'Image').length, 1);
    assert.equal(native.safeAreas.filter(event => event[0] === 'Scroll').length, 1);
    assert.equal(native.safeAreas.filter(event => event[0] === 'TabContent').length, 1);
    assert.equal(native.safeAreas.length, 6);
    assert.ok(native.safeAreas.every(event => Array.from(event[1]).join(',') === '1'));
    assert.equal(owner.bottomBarVisible(), !keyboardVisible);
    assert.equal(owner.backgroundPath, '/test-background.jpg');
  }
});

test('Compiled family login extends its themed backdrop to system bars without extending the Web view', () => {
  for (const mode of ['day', 'night']) {
    const { native, family } = mount(); const login = family(mode); login.initialRender();
    assert.deepEqual(native.safeAreas.map(event => event[0]), ['Stack']);
    assert.deepEqual(Array.from(native.safeAreas[0][1]), [1]); assert.deepEqual(Array.from(native.safeAreas[0][2]), [0, 1]);
    assert.equal(native.webCreates.length, 1); assert.equal(login.reading, false); assert.equal(login.webReady, false);
  }
});

function savedPreferences() {
  const files = new Map();
  return { getPreferences: async (_, options) => {
    if (!files.has(options.name)) files.set(options.name, new Map()); const values = files.get(options.name);
    return { get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
      put: async (key, value) => values.set(key, value), delete: async key => values.delete(key), flush: async () => {} };
  } };
}
function realLibrary() { const value = libraryModel.demoLibrary(); value.demo = false; value.player.name = '同步昵称';
  value.player.avatarUrl = 'https://avatars.steamstatic.com/avatar_full.jpg'; value.fetchedAt = '2026-10-03T08:00:00.000Z'; value.notices = []; return value; }
function enableRealActions(owner) {
  delete owner.loadLibrary; delete owner.saveSettings;
  owner.keyStore = { save: async () => {}, clear: async () => {}, read: async () => 'a'.repeat(32) };
  owner.familyStore = { save: async () => {}, clear: async () => {}, read: async () => '' };
}
test('Two compiled page instances restore the last successful library/profile and sort without a network read', async () => {
  const preferences = savedPreferences(); const prefs = await preferences.getPreferences({}, {name:'steam_hours'});
  await prefs.put('account', '76561198000000000'); await prefs.put('rememberKey', false);
  const first = mount({ preferences, account:'76561198000000000', mainPage:'library', library: realLibrary() });
  first.owner.libraryStore = first.createLibraryStore(); await first.owner.libraryStore.save({}, first.owner.account, false, first.owner.library);
  first.owner.changeSort(3); await first.owner.sortWrites;
  const second = mount({preferences, apiKey:'', mainPage:'library', library: libraryModel.emptyLibrary(), settingsReady:false});
  second.owner.libraryStore = second.createLibraryStore(); await second.owner.restoreSettings();
  assert.equal(second.owner.settingsReady,true); assert.equal(second.owner.sort,3);
  assert.equal(second.owner.library.demo,false); assert.equal(second.owner.library.player.name,'同步昵称');
  assert.equal(second.owner.library.games.length,6); assert.equal(second.calls.includes('loadLibrary'),false);
  second.owner.initialRender(); assert.ok(second.rows.images.includes(second.owner.library.player.avatarUrl));
  assert.equal(second.rows.texts.some(row => String(row.value).includes('演示模式') || String(row.value).includes('示例数据')),false);
  enableRealActions(second.owner); second.owner.apiKey='a'.repeat(32); second.owner.api.load=async()=>{throw Error('offline');};
  await second.owner.loadLibrary(); assert.equal(second.owner.library.player.name,'同步昵称'); assert.equal(second.owner.sort,3);
});
test('Saving complete credentials and completing family login read real data and persist it without changing sort',async()=>{
  for (const family of [false,true]) {
    const preferences=savedPreferences(); const m=mount({preferences,account:'76561198000000000',apiKey:'a'.repeat(32),rememberKey:false,sort:3,library:libraryModel.emptyLibrary()});
    enableRealActions(m.owner); m.owner.libraryStore=m.createLibraryStore(); m.owner.prefs=await preferences.getPreferences({}, {name:'steam_hours'});
    const requests=[]; m.owner.api.load=async(...args)=>{requests.push(args);return realLibrary();};
    if(family) await m.owner.authorizeFamily('test-session-token-only'); else await m.owner.saveSettings();
    assert.equal(requests.length,1); assert.equal(requests[0][0],m.owner.account); assert.equal(requests[0][2],family?'test-session-token-only':'');
    assert.equal(m.owner.library.demo,false); assert.equal(m.owner.library.player.name,'同步昵称'); assert.equal(m.owner.mainPage,'library'); assert.equal(m.owner.sort,3);
    const saved=await m.owner.libraryStore.read({},m.owner.account,family); assert.equal(saved.player.name,'同步昵称');
  }
});
test('An older installation with saved credentials but no snapshot automatically reads once; no credentials stays non-demo',async()=>{
  for(const rememberKey of [false,true]){
    const preferences=savedPreferences();const prefs=await preferences.getPreferences({}, {name:'steam_hours'});await prefs.put('account','76561198000000000');await prefs.put('rememberKey',rememberKey);
    const m=mount({preferences,apiKey:'',settingsReady:false,library:libraryModel.emptyLibrary(),mainPage:'library'});m.owner.libraryStore=m.createLibraryStore();
    m.owner.keyStore={read:async()=> 'a'.repeat(32)};m.owner.familyStore={read:async()=>''};await m.owner.restoreSettings();
    assert.equal(m.calls.filter(call=>call==='loadLibrary').length,rememberKey?1:0);assert.equal(m.owner.library.demo,false);
    assert.equal(m.owner.mainPage,rememberKey?'library':'accounts');
  }
});
test('A failed disk cache write keeps newly fetched data and shows a persistence message; sorting is retained',async()=>{
  const m=mount({account:'76561198000000000',apiKey:'a'.repeat(32),rememberKey:false,sort:2});enableRealActions(m.owner);
  m.owner.api.load=async()=>realLibrary();m.owner.libraryStore.save=async()=>{throw Error('disk');};await m.owner.loadLibrary();
  assert.equal(m.owner.library.demo,false);assert.equal(m.owner.library.player.name,'同步昵称');assert.equal(m.owner.mainPage,'library');assert.equal(m.owner.sort,2);assert.match(m.owner.libraryMessage,/缓存/);
});
test('Queued sort changes persist in selection order and a failure never discards the visible choice',async()=>{
  const m=mount();const saved=[];m.owner.libraryStore.saveSort=async(_,value)=>{saved.push(value);};m.owner.changeSort(1);m.owner.changeSort(3);await m.owner.sortWrites;
  assert.deepEqual(saved,[1,3]);assert.equal(m.owner.sort,3);m.owner.libraryStore.saveSort=async()=>{throw Error('disk');};m.owner.changeSort(2);await m.owner.sortWrites;assert.equal(m.owner.sort,2);assert.match(m.owner.libraryMessage,/排序/);
});
test('Compiled artwork exhausts known CDNs before icon and ignores stale errors',()=>{const m=mount(),game={appId:400,name:'Portal',iconUrl:'https://media.steampowered.com/icon.jpg'};m.owner.gameArtwork(game,m.owner.artworkUrl(game));const first=m.native.imageErrors.at(-1);first();const next=m.owner.artworkUrl(game);first();assert.equal(m.owner.artworkUrl(game),next);let count=0;while(m.owner.artworkUrl(game)&&count++<20){m.owner.gameArtwork(game,m.owner.artworkUrl(game));m.native.imageErrors.at(-1)();}assert.equal(m.owner.artworkUrl(game),'');assert.ok(m.rows.images.includes(game.iconUrl));});test('Compiled background concentration slider reaches 100 percent and saves 1.0',async()=>{
  const m=mount({backgroundPath:'/test-background.jpg'});m.owner.settings();const slider=m.rows.sliders.find(row=>row.value.min===8);
  assert.equal(slider.value.max,100);const saved=[];m.owner.personalizationStore={saveOpacity:async(_,value)=>{saved.push(value);return value;}};
  slider.onChange(100,1);assert.equal(m.owner.backgroundOpacity,1);slider.onChange(100,2);await new Promise(resolve=>setImmediate(resolve));assert.deepEqual(saved,[1]);
});
test('Compiled achievement requests stay tied to selected game/account and stale completions cannot replace a newer selection',async()=>{
  const m=mount({library:realLibrary(),selected:{appId:400},apiKey:'a'.repeat(32)});let finish;const requested=[];
  m.owner.achievementsApi.load=(...args)=>{requested.push(args);return new Promise(resolve=>finish=resolve);};const pending=m.owner.loadAchievements({appId:400});
  assert.equal(m.owner.achievementLoading,true);m.owner.resetAchievements();m.owner.selected={appId:500};finish({status:'available',items:[],unlocked:0,message:''});await pending;
  assert.equal(m.owner.achievementData,null);assert.equal(m.owner.achievementLoading,false);assert.equal(requested[0][0],m.owner.library.player.steamId);
  m.owner.achievementsApi.load=async()=>({status:'available',items:[],unlocked:0,message:''});await m.owner.loadAchievements({appId:500});assert.equal(m.owner.achievementAppId,500);assert.equal(m.owner.achievementData.status,'available');
});
test('Demo achievement lookup never makes a request; compiled real details expose an actionable achievement button',()=>{
  const m=mount({library:libraryModel.demoLibrary()});m.owner.achievementsApi.load=()=>{throw Error('unexpected request');};m.owner.loadAchievements({appId:400});assert.match(m.owner.achievementError,/本人/);
  m.owner.detail(m.owner.library.games[0]);assert.ok(m.rows.buttons.some(row=>row.value==='查看 / 刷新成就'));
});

test('Real compiled scroll callbacks hide native material actions without changing viewport height and upward motion restores them',()=>{
 let offset=120,atEnd=false;const m=mount({mainPage:'library',library:realLibrary(),scroller:{currentOffset:()=>({yOffset:offset}),isAtEnd:()=>atEnd}});m.owner.bottomBarTracker.reset(offset);m.owner.initialRender();m.native.tabsAppear();
 assert.equal(m.native.barHeights.at(-1),64);assert.equal(m.native.overlaps.at(-1),true);offset=165;m.native.scrollCallback(0,45,1);assert.equal(m.owner.bottomBarScrollHidden,true);assert.equal(m.owner.bottomBarVisible(),false);assert.equal(m.owner.bottomBarLayoutVisible(),true);assert.equal(m.native.translations.at(-1).y,112);assert.equal(m.native.opacities.at(-1),0);assert.equal(m.native.animations.at(-1).curve.damping,1);assert.equal(m.native.animations.at(-1).curve.response,0.26);
 m.owner.initialRender();assert.equal(m.native.barHeights.at(-1),64);m.owner.bottomActions();assert.equal(m.native.rowHitTests.at(-1),0);offset=152;m.native.scrollCallback(0,-13,1);assert.equal(m.owner.bottomBarScrollHidden,false);assert.equal(m.native.opacities.at(-1),1);
 offset=210;m.native.scrollCallback(0,58,2);assert.equal(m.owner.bottomBarScrollHidden,true);atEnd=true;m.native.stopCallback();assert.equal(m.owner.bottomBarScrollHidden,false);
});
test('Real compiled API12 layout fallback hides only the bar with overlap preserving the content viewport',()=>{
 let offset=120;const m=mount({platformSdk:12,mainPage:'library',library:realLibrary(),scroller:{currentOffset:()=>({yOffset:offset}),isAtEnd:()=>false}});m.owner.bottomBarTracker.reset(offset);m.owner.initialRender();m.native.tabsAppear();offset=165;m.native.scrollCallback(0,45,1);m.owner.initialRender();
 assert.equal(m.owner.bottomBarScrollHidden,true);assert.equal(m.native.barHeights.at(-1),0);assert.equal(m.native.overlaps.at(-1),true);assert.equal(m.native.translations.length,0);offset=150;m.native.scrollCallback(0,-15,1);m.owner.initialRender();assert.equal(m.native.barHeights.at(-1),64);
});
test('Actual compiled page switches and return-to-top restore a hidden bar before resetting scroll',()=>{
 let offset=150;const m=mount({scroller:{currentOffset:()=>({yOffset:offset}),isAtEnd:()=>false,scrollTo:()=>offset=0},mainPage:'library'});delete m.owner.returnToTop;
 m.owner.bottomBarTracker.reset(100);m.owner.contentDidScroll(1);assert.equal(m.owner.bottomBarScrollHidden,true);m.owner.openSettings();assert.equal(m.owner.mainPage,'settings');assert.equal(m.owner.bottomBarVisible(),true);assert.equal(offset,0);
 m.owner.contentDidScroll(0);offset=160;m.owner.contentDidScroll(1);assert.equal(m.owner.bottomBarScrollHidden,true);m.owner.openAccounts();assert.equal(m.owner.bottomBarVisible(),true);assert.equal(offset,0);m.owner.returnToTop();assert.equal(m.owner.bottomBarVisible(),true);
});
test('Compiled keyboard/focus handling immediately hides and restores both painted actions and scrolling state',()=>{
 const m=mount({keyboardObserved:true,bottomBarMounted:true,scroller:{currentOffset:()=>({yOffset:300}),isAtEnd:()=>false}});m.owner.bottomBarScrollHidden=true;m.owner.keyboardVisible=true;m.owner.inputVisibilityChanged();assert.equal(m.owner.bottomBarScrollHidden,false);assert.equal(m.owner.bottomBarVisible(),false);assert.equal(m.owner.bottomBarLayoutVisible(),false);assert.equal(m.native.opacities.at(-1),0);
 m.owner.keyboardVisible=false;m.owner.inputVisibilityChanged();assert.equal(m.owner.bottomBarVisible(),true);assert.equal(m.native.opacities.at(-1),1);m.owner.keyboardObserved=false;m.owner.editingInput=true;m.owner.inputVisibilityChanged();assert.equal(m.owner.bottomBarVisible(),false);m.owner.editingInput=false;m.owner.inputVisibilityChanged();assert.equal(m.owner.bottomBarVisible(),true);
});
test('Compiled native animation failure switches to functional layout hiding without a crash or invisible click targets',()=>{
 let offset=120;const m=mount({mainPage:'library',library:realLibrary(),scroller:{currentOffset:()=>({yOffset:offset}),isAtEnd:()=>false},tabsController:{setTabBarTranslate:()=>{throw Error('unsupported');},setTabBarOpacity:()=>{}}});m.owner.bottomBarTracker.reset(offset);m.owner.initialRender();m.native.tabsAppear();assert.equal(m.owner.bottomBarMotionSupported,false);
 offset=165;m.native.scrollCallback(0,45,1);m.owner.initialRender();assert.equal(m.owner.bottomBarVisible(),false);assert.equal(m.native.barHeights.at(-1),0);m.owner.bottomActions();assert.equal(m.native.rowHitTests.at(-1),0);offset=150;m.native.scrollCallback(0,-15,1);assert.equal(m.owner.bottomBarVisible(),true);
});

 test('All compiled root pages disable the full-width overlap blur while retaining the native capsule and stable bar height',()=>{for(const mode of ['day','night'])for(const page of ['library','accounts','settings'])for(const hidden of [false,true]){const m=mount({mainPage:page,colorMode:mode,bottomBarScrollHidden:hidden,library:realLibrary()});m.owner.initialRender();assert.equal(m.native.tabBlurStyles.at(-1),6);assert.equal(m.native.overlaps.at(-1),true);assert.equal(m.native.barHeights.at(-1),64);assert.equal(m.native.tabBars,1);}});

 test('Actual root uses a transparent zero-width divider instead of the native null/reset path',()=>{for(const page of ['library','accounts','settings']){const m=mount({mainPage:page,library:realLibrary()});m.owner.initialRender();const divider=m.native.tabDividers.at(-1);assert.equal(divider.strokeWidth,0);assert.equal(divider.color,'#00000000');assert.equal(divider.startMargin,0);assert.equal(divider.endMargin,0);}});


test('Compiled transparency slider previews the full range and commits only end/click, even without an image', async () => {
  const m=mount();m.owner.settings();const slider=m.rows.sliders.find(row=>row.value.step===1&&row.value.min===0);
  assert.equal(slider.value.value,25);assert.equal(slider.value.max,100);assert.equal(slider.enabled,true);
  const saved=[];m.owner.personalizationStore={savePanelTransparency:async(_,value)=>{saved.push(value);return value;}};
  slider.onChange(70,1);assert.equal(m.owner.panelTransparency,0.7);assert.deepEqual(saved,[]);
  slider.onChange(70,2);await new Promise(resolve=>setImmediate(resolve));assert.deepEqual(saved,[0.7]);
  assert.match(m.owner.appearanceMessage,/已保存/);
  slider.onChange(100,3);await new Promise(resolve=>setImmediate(resolve));assert.equal(m.owner.panelTransparency,1);
  slider.onChange(0,3);await new Promise(resolve=>setImmediate(resolve));assert.equal(m.owner.panelTransparency,0);
  assert.deepEqual(saved,[0.7,1,0]);
});

test('Compiled card surfaces and hero gradient change alpha while text, inputs and buttons remain opaque', () => {
  for(const mode of ['day','night'])for(const transparency of [0,0.5,1]) {
    const palette=paletteModel.colorsFor(mode);const m=mount({colorMode:mode,panelTransparency:transparency,colors:()=>palette,library:realLibrary()});
    m.owner.settings();m.owner.gameRow(m.owner.library.games[0]);m.owner.detail(m.owner.library.games[0]);m.owner.mainPage='library';m.owner.initialRender();
    const alpha=transparency===0?'FF':transparency===0.5?'80':'00';
    assert.ok(m.native.panelBackgrounds.includes('#'+alpha+palette.surface.slice(1)));
    assert.ok(m.native.panelBackgrounds.includes('#'+alpha+palette.detail.slice(1)));
    assert.ok(m.native.panelGradients.some(g=>g.colors[0][0]==='#'+alpha+palette.stats.slice(1)&&g.colors[1][0]==='#'+alpha+palette.heroEnd.slice(1)));
    assert.deepEqual(m.native.panelOpacities,[]);
    assert.equal(m.rows.inputs.find(row=>row.value.placeholder==='SteamID64 或 Steam 个人主页链接').backgroundColor,palette.input);
    assert.equal(m.rows.buttons.find(row=>row.value==='读取游戏库').backgroundColor,palette.primary);
    assert.equal(m.rows.texts.find(row=>row.value==='连接你的 Steam').fontColor,palette.text);
    if(transparency===1)for(const border of m.native.panelBorders)assert.equal(border.color.slice(0,3),'#00');
  }
});

test('Compiled transparency save guards and failures keep the preview with an accurate message', async () => {
  const m=mount({panelTransparency:0.8,personalizationStore:{savePanelTransparency:async()=>{throw Error('disk');}}});
  await m.owner.savePanelTransparency(80);assert.equal(m.owner.panelTransparency,0.8);assert.equal(m.owner.personalizationBusy,false);
  assert.match(m.owner.appearanceMessage,/本次使用有效.*未能保存/);
  for(const guard of [{personalizationBusy:true},{settingsReady:false}]) {
    const blocked=mount({...guard,personalizationStore:{savePanelTransparency:async()=>{throw Error('must not save');}}});
    blocked.owner.settings();assert.equal(blocked.rows.sliders.find(row=>row.value.step===1&&row.value.min===0).enabled,false);
    await blocked.owner.savePanelTransparency(100);assert.equal(blocked.owner.panelTransparency,0.25);assert.equal(blocked.owner.appearanceMessage,'');
  }
});

test('Pending/declined compiled UI exposes readable policy and offline choice without restoring keys or remote images',async()=>{
 const m=mount({privacyStatus:'pending',apiKey:'',account:''});let choices=[];m.owner.privacyStore={choose:async(_,value)=>choices.push(value)};
 m.owner.initialRender();assert.ok(m.rows.buttons.some(b=>b.value==='阅读完整隐私政策'));assert.ok(m.rows.buttons.some(b=>b.value==='不同意，离线使用'));
 await m.owner.declinePrivacy();assert.deepEqual(choices,[false]);assert.equal(m.owner.privacyStatus,'declined');assert.equal(m.owner.library.demo,true);assert.equal(m.owner.artworkUrl(m.owner.library.games[0]),'');
 let reads=0;m.owner.keyStore={read:async()=>{reads++;return 'must not read';}};await m.owner.restoreSettings();assert.equal(reads,0);
 m.owner.mainPage='library';m.owner.initialRender();assert.ok(m.rows.images.every(url=>!String(url).startsWith('https://')));assert.throws(()=>m.privacyAccess.begin());
});

test('Compiled consent is granted only after persistence, supports configured restore and stays closed on failure',async()=>{
 const m=mount({privacyStatus:'pending'});let restores=0;m.owner.restoreSettings=async()=>{assert.equal(m.owner.privacyStatus,'granted');m.privacyAccess.begin();assert.equal(m.owner.hasConsent(),true);restores++;m.owner.settingsReady=true;};
 await m.owner.acceptPrivacy();assert.equal(restores,1);assert.equal(m.owner.privacyBusy,false);assert.equal(m.owner.privacyStatus,'granted');
 const failed=mount({privacyStatus:'pending',privacyStore:{choose:async()=>{throw Error('disk');}}});await failed.owner.acceptPrivacy();assert.equal(failed.owner.privacyStatus,'pending');assert.match(failed.owner.privacyMessage,/未启用/);assert.throws(()=>failed.privacyAccess.begin());
});

test('Compiled privacy, about and support pages identify the developer and retain one Settings highlight',()=>{
 const m=mount();m.owner.privacyPage();m.owner.aboutPage();m.owner.supportPage();
 assert.ok(m.rows.texts.some(t=>String(t.value).includes('TombeHung')));assert.ok(m.rows.texts.some(t=>t.value==='https://github.com/TombeHung35/SteamHours/issues'));
 assert.ok(m.rows.texts.some(t=>String(t.value).includes('不要求、收集或保存 Steam 密码')));
 for(const page of ['privacy','about','support']){m.owner.mainPage=page;const before=m.rows.buttons.length;m.owner.bottomActions();const buttons=m.rows.buttons.slice(before);assert.equal(buttons.filter(b=>b.backgroundColor==='#4963C9').length,1);assert.equal(buttons.find(b=>b.backgroundColor==='#4963C9').value,'设置');}
});

test('Compiled clear action requires confirmation, cancel preserves data and accept resets complete UI state',async()=>{
 const m=mount({account:'saved',apiKey:'secret',themeColor:'#123456',backgroundPath:'/old.jpg',sort:3,manualGameInput:'400',library:realLibrary()});let cleared=0;m.owner.localDataCleaner={clear:async()=>cleared++};
 m.owner.confirmClearData();assert.equal(cleared,0);assert.equal(m.native.dialogs.length,1);m.native.dialogs[0].primaryButton.action();assert.equal(m.owner.account,'saved');assert.equal(cleared,0);
 m.native.dialogs[0].secondaryButton.action();await new Promise(resolve=>setImmediate(resolve));assert.equal(cleared,1);
 assert.equal(m.owner.account,'');assert.equal(m.owner.apiKey,'');assert.equal(m.owner.library.games.length,0);assert.equal(m.owner.sort,0);assert.equal(m.owner.themeColor,'');assert.equal(m.owner.backgroundPath,'');assert.equal(m.owner.privacyStatus,'pending');assert.equal(m.owner.panelTransparency,0.25);assert.equal(m.owner.privacyBusy,false);
});

test('Compiled clear during pending query rejects its later result before display, persistence or credential restoration',async()=>{
 let finish;let writes=0;const m=mount({api:{load:()=>new Promise(resolve=>finish=resolve),clearCache:()=>{}},account:'76561198000000000',apiKey:'a'.repeat(32),library:realLibrary(),localDataCleaner:{clear:async()=>{}},libraryStore:{save:async()=>writes++,readByPlayer:async()=>null}});
 delete m.owner.loadLibrary;const request=m.owner.loadLibrary();await new Promise(resolve=>setImmediate(resolve));assert.equal(m.owner.loading,true);
 await m.owner.clearAllLocalData();finish(realLibrary());await request;assert.equal(writes,0);assert.equal(m.owner.library.games.length,0);assert.equal(m.owner.apiKey,'');assert.equal(m.owner.privacyStatus,'pending');assert.equal(m.owner.loading,false);
});

test('Compiled cleanup failure stays blocked and cannot re-enable Steam until cleanup is retried',async()=>{
 const m=mount({localDataCleaner:{clear:async()=>{throw Error('部分本地数据未能删除，请重试');}}});await m.owner.clearAllLocalData();assert.equal(m.owner.privacyStatus,'blocked');assert.match(m.owner.privacyMessage,/重试/);assert.throws(()=>m.privacyAccess.begin());
 await m.owner.acceptPrivacy();assert.equal(m.owner.privacyStatus,'blocked');m.owner.localDataCleaner={clear:async()=>{}};await m.owner.clearAllLocalData();assert.equal(m.owner.privacyStatus,'pending');
 for(const guard of [{savingSettings:true},{personalizationBusy:true},{appearanceSaving:true},{librarySaving:true}]){const busy=mount(guard);busy.owner.confirmClearData();assert.equal(busy.native.dialogs.length,0);}
});

test('Compiled feedback actions use only public issue URL/template and never copy key, password or player identity',async()=>{
 const m=mount({apiKey:'sensitive-secret',account:'76561198000000000'});await m.owner.copySupport();await m.owner.copySupport(true);await m.owner.openFeedback();
 assert.equal(m.native.copied[0],'https://github.com/TombeHung35/SteamHours/issues');assert.ok(m.native.copied[1].includes('0.3.24'));assert.ok(!m.native.copied[1].includes('sensitive-secret'));assert.ok(!m.native.copied[1].includes('76561198000000000'));assert.equal(m.native.links[0].uri,'https://github.com/TombeHung35/SteamHours/issues');assert.equal(m.native.links[0].action,'ohos.want.action.viewData');assert.ok(!m.native.links[0].uri.includes('sensitive-secret'));
});

test('Compiled privacy text surfaces stay opaque at 100 percent card transparency and decline restores offline demo',async()=>{
 const palette=paletteModel.colorsFor('night');const m=mount({privacyStatus:'declined',panelTransparency:1,colors:()=>palette});m.owner.privacyPage();assert.ok(m.native.panelBackgrounds.includes(palette.surface));
 await m.owner.restoreSettings();assert.equal(m.owner.library.demo,true);assert.equal(m.owner.artworkUrl(m.owner.library.games[0]),'');
});

test('Native deletion confirmation applies readable default fonts and explicit action colors for both app modes',()=>{
 for(const mode of ['day','night']){const palette=paletteModel.colorsFor(mode);const m=mount({colorMode:mode,colors:()=>palette});m.owner.confirmClearData(true);const theme=m.native.defaultThemes.at(-1);assert.equal(theme.colors.fontPrimary,palette.text);assert.equal(theme.colors.fontSecondary,palette.body);const dialog=m.native.dialogs.at(-1);assert.equal(dialog.backgroundColor,palette.surface);assert.equal(dialog.backgroundBlurStyle,6);assert.equal(dialog.primaryButton.fontColor,palette.accent);assert.equal(dialog.secondaryButton.fontColor,palette.dangerText);}
});

test('Artwork metadata refresh is batched per visible library and rejects a response after local cleanup',async()=>{let finish;const m=mount({mainPage:'library',library:realLibrary(),artworkApi:{load:()=>new Promise(resolve=>finish=resolve),clearCache(){}}});const pending=m.owner.refreshArtwork();assert.equal(m.owner.artworkLoading,true);await m.owner.clearAllLocalData();finish({'400':['https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/400/hash/library_capsule.jpg']});await pending;assert.equal(Object.keys(m.owner.artworkUrls).length,0);assert.equal(m.owner.familyToken,'');assert.equal(m.owner.includeFamily,false);});
test('Declined account cannot open family login or accept an old authorization callback',async()=>{const m=mount({privacyStatus:'declined',familyToken:'',includeFamily:false});const button=m.rows.buttons.find(b=>b.value==='登录 Steam');assert.equal(button.enabled,false);button.onClick();assert.ok(!m.calls.includes('openFamily'));await m.owner.authorizeFamily('late-token');assert.equal(m.owner.familyToken,'');assert.equal(m.owner.includeFamily,false);});
test('Family page discards JavaScript authorization result after consent is revoked',async()=>{let finish;const m=mount();const login=m.family('night');login.reading=true;login.controller={runJavaScript:()=>new Promise(resolve=>finish=resolve),loadUrl:()=>{throw Error('must not reload');}};let authorized=0;login.onAuthorized=()=>authorized++;const pending=login.pageEnded('https://store.steampowered.com/pointssummary/ajaxgetasyncconfig');await new Promise(resolve=>setImmediate(resolve));assert.equal(typeof finish,'function');m.privacyAccess.setAllowed(false);finish('secret');await pending;assert.equal(authorized,0);});
test('Compiled image update reads new metadata directly and keeps the URL captured by older error callbacks',()=>{const m=mount({mainPage:'library',library:realLibrary()}),game={appId:400,name:'Portal',iconUrl:''};let updateImage;m.owner.observeComponentCreation2=callback=>{const count=m.rows.images.length;callback(1,true);if(m.rows.images.length>count)updateImage=callback;};m.owner.gameArtwork(game);const oldError=m.native.imageErrors.at(-1);const changed='https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/400/abc/library_capsule.jpg';m.owner.artworkUrls={'400':[changed]};assert.equal(typeof updateImage,'function');updateImage(1,false);assert.equal(m.rows.images.at(-1),changed);oldError();assert.equal(m.owner.artworkFailures['400'],undefined);m.native.imageErrors.at(-1)();assert.equal(m.owner.artworkFailures['400'],1);});
