import { webview } from '@kit.ArkWeb';
import { deviceInfo } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { KeyStore } from './KeyStore';
import { PrivacyStore } from './PrivacyStore';
import { privacyAccess } from '../model/PrivacyAccess';

// Traverse only this application's known private roots; never follow symbolic links.
async function clearDirectory(directory: string, depth: number = 0): Promise<void> {
  if (depth > 32) throw new Error('缓存目录层级过深。');
  if (!fs.accessSync(directory)) return;
  const rootStat: fs.Stat = fs.lstatSync(directory);
  if (rootStat.isSymbolicLink() || !rootStat.isDirectory()) throw new Error('缓存目录不可安全清理。');
  const names: string[] = fs.listFileSync(directory);
  for (const name of names) {
    if (!name || name === '.' || name === '..' || name.includes('/') || name.includes('\\')) throw new Error('缓存路径无效。');
    const target: string = directory + '/' + name;
    const stat: fs.Stat = fs.lstatSync(target);
    if (stat.isSymbolicLink() || !stat.isDirectory()) await fs.unlink(target);
    else { await clearDirectory(target, depth + 1); await fs.rmdir(target); }
  }
}

export class LocalDataCleaner {
  async clear(context: common.UIAbilityContext): Promise<void> {
    privacyAccess.setAllowed(false);
    const privacy: PrivacyStore = new PrivacyStore();
    await privacy.markCleanup(context);
    let failed: boolean = false;
    for (const alias of ['steam_hours_personal_api_key_v1', 'steam_hours_family_token_v1']) {
      try { await new KeyStore(alias).clear(); } catch (_) { failed = true; }
    }
    try { webview.WebCookieManager.clearAllCookiesSync(); webview.WebStorage.deleteAllData();
      if (deviceInfo.sdkApiVersion >= 18) webview.WebviewController.removeAllCache(true);
    } catch (_) { failed = true; }
    for (const name of ['steam_hours', 'steam_hours_library_v1']) {
      try {
        const store: preferences.Preferences = await preferences.getPreferences(context, { name: name });
        await store.clear(); await store.flush();
      } catch (_) { failed = true; }
    }
    if (!context.filesDir.startsWith('/') || !context.cacheDir.startsWith('/') || context.filesDir === '/' || context.cacheDir === '/' || context.cacheDir === context.filesDir) throw new Error('应用存储路径无效，未完成清理。');
    for (const directory of [context.filesDir + '/appearance', context.cacheDir]) {
      try { await clearDirectory(directory); } catch (_) { failed = true; }
    }
    if (failed) throw new Error('部分本地数据未能删除，联网已关闭。请重试清除；下次启动也会继续清理。');
    await privacy.finishCleanup(context);
  }
}
