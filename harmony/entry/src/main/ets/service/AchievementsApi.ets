import { privacyAccess } from '../model/PrivacyAccess';
import { http } from '@kit.NetworkKit';
import { validateApiKey } from '../model/SteamData';
import { AchievementResponse, SteamPlayerAchievements, SteamGameSchema, normalizeAchievements } from '../model/AchievementData';

export class AchievementsApi {
  private cachedIdentity: string = '';
  private cachedAt: number = 0;
  private cachedData: AchievementResponse | null = null;
  clearCache(): void { this.cachedIdentity = ''; this.cachedAt = 0; this.cachedData = null; }
  async load(steamId: string, appId: number, apiKey: string): Promise<AchievementResponse> {
    const privacyGeneration: number = privacyAccess.begin();
    const key: string = validateApiKey(apiKey);
    if (!/^\d{17}$/.test(steamId) || !Number.isSafeInteger(appId) || appId <= 0) throw new Error('账号或游戏编号无效，请重新读取游戏库。');
    const identity: string = steamId + ':' + appId.toString() + ':' + key;
    if (identity === this.cachedIdentity && this.cachedData !== null && Date.now() - this.cachedAt < 60000) return this.cachedData;
    const params: string = '&appid=' + appId.toString() + '&l=schinese';
    const statsTask = this.request<SteamPlayerAchievements>('GetPlayerAchievements/v1/', key, params + '&steamid=' + steamId, 'playerstats');
    const schemaTask = this.request<SteamGameSchema>('GetSchemaForGame/v2/', key, params, 'game').catch((): null => null);
    const stats: SteamPlayerAchievements = await statsTask;
    const schema: SteamGameSchema | null = await schemaTask;
    const result: AchievementResponse = normalizeAchievements(stats, schema, steamId);
    privacyAccess.check(privacyGeneration);
    this.cachedIdentity = identity; this.cachedData = result; this.cachedAt = Date.now();
    return result;
  }
  private async request<T>(path: string, key: string, params: string, root: string): Promise<T> {
    const requestGeneration: number = privacyAccess.begin();
    const request = http.createHttp();
    let destroyed: boolean = false;
    const close: () => void = (): void => { if (!destroyed) { destroyed = true; request.destroy(); } };
    const unregister: () => void = privacyAccess.register(close, requestGeneration);
    try {
      let response: http.HttpResponse;
      try {
        response = await request.request('https://api.steampowered.com/ISteamUserStats/' + path + '?format=json' + params,
          { method: http.RequestMethod.GET, header: { 'Accept': 'application/json', 'x-webapi-key': key }, expectDataType: http.HttpDataType.STRING,
            connectTimeout: 15000, readTimeout: 20000, usingCache: false });
      } catch (_) { throw new Error('暂时无法连接 Steam 成就服务，请检查网络后重试。'); }
      privacyAccess.check(requestGeneration);
      if (response.responseCode === 401 || response.responseCode === 403) throw new Error('Steam 拒绝读取成就，请检查 API 密钥或资料隐私。');
      if (response.responseCode === 429) throw new Error('Steam 请求过于频繁，请稍后重试。');
      if (response.responseCode !== 200) throw new Error('Steam 成就暂不可用，HTTP ' + response.responseCode.toString());
      let envelope: Record<string, T>;
      try { envelope = JSON.parse(response.result as string) as Record<string, T>; } catch (_) { throw new Error('Steam 成就数据无法读取。'); }
      if (!envelope || envelope[root] === undefined || envelope[root] === null) throw new Error('Steam 成就数据不完整，请稍后重试。');
      return envelope[root];
    } finally { unregister(); close(); }
  }
}
