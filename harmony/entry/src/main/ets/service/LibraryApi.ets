import { privacyAccess } from '../model/PrivacyAccess';
import { SteamFamilyGroup, SteamSharedResponse, mergeFamilyLibrary } from '../model/FamilyData';
import { http } from '@kit.NetworkKit';
import { LibraryResponse } from '../model/Library';
import { SteamAccount, SteamEnvelope, SteamOwnedResponse, SteamPlayersResponse,
  SteamRecentResponse, SteamVanityResponse, normalizeLibrary, parseAccount, validateApiKey } from '../model/SteamData';

export class LibraryApi {
  private cachedAccount: string = '';
  private cachedApiKey: string = '';
  private cachedFamilyToken: string = '';
  private cachedAt: number = 0;
  private cachedData: LibraryResponse | null = null;

  clearCache(): void {
    this.cachedAccount = '';
    this.cachedApiKey = '';
    this.cachedFamilyToken = '';
    this.cachedAt = 0;
    this.cachedData = null;
  }

  async load(account: string, apiKey: string, familyToken: string = ''): Promise<LibraryResponse> {
    const privacyGeneration: number = privacyAccess.begin();
    const key: string = validateApiKey(apiKey);
    const parsed: SteamAccount = parseAccount(account);
    const normalizedAccount: string = parsed.steamId || parsed.vanity;
    if (this.cachedData !== null && this.cachedAccount === normalizedAccount && this.cachedApiKey === key && this.cachedFamilyToken === familyToken && Date.now() - this.cachedAt < 60000) {
      return this.cachedData;
    }
    let steamId: string = parsed.steamId;
    if (!steamId) {
      const resolved = await this.request<SteamVanityResponse>('ISteamUser/ResolveVanityURL/v1/', key,
        { 'vanityurl': parsed.vanity, 'url_type': '1' });
      if (resolved.success !== 1 || !resolved.steamid || !/^\d{17}$/.test(resolved.steamid)) {
        throw new Error('没有找到这个自定义 Steam 主页。');
      }
      steamId = resolved.steamid;
    }
    const players = await this.request<SteamPlayersResponse>('ISteamUser/GetPlayerSummaries/v2/', key, { 'steamids': steamId });
    if (!Array.isArray(players.players) || !players.players || players.players.length === 0) {
      throw new Error('没有找到这个 Steam 用户。');
    }
    const player = players.players.find((item) => item.steamid === steamId);
    if (!player) throw new Error('Steam 返回的玩家资料与查询账号不一致。');
    const ownedTask = this.request<SteamOwnedResponse>('IPlayerService/GetOwnedGames/v1/', key,
      { 'steamid': steamId, 'include_appinfo': 'true', 'include_played_free_games': 'true' });
    const recentTask = this.request<SteamRecentResponse>('IPlayerService/GetRecentlyPlayedGames/v1/', key,
      { 'steamid': steamId, 'count': '0' }).catch((): SteamRecentResponse => {
        const unavailable: SteamRecentResponse = {};
        return unavailable;
      });
    const owned: SteamOwnedResponse = await ownedTask;
    const recent: SteamRecentResponse = await recentTask;
    const result = normalizeLibrary(player, owned, recent, new Date().toISOString());
    if (familyToken) {
      try {
        const group = await this.request<SteamFamilyGroup>('IFamilyGroupsService/GetFamilyGroupForUser/v1/', familyToken,
          { 'steamid': steamId }, true);
        if (group.is_not_member_of_any_group || group.family_groupid === '0') {
          result.familyStatus = 'none';
          result.notices.push('该账号未加入 Steam 家庭，当前显示个人游戏。');
        } else if (!group.family_groupid || !/^\d+$/.test(group.family_groupid)) {
          throw new Error('Steam 未返回家庭信息，请重新登录后重试。');
        } else {
          const shared = await this.request<SteamSharedResponse>('IFamilyGroupsService/GetSharedLibraryApps/v1/', familyToken,
            { 'family_groupid': group.family_groupid, 'steamid': steamId, 'include_own': 'true',
              'include_excluded': 'false', 'include_non_games': 'false', 'language': 'schinese' }, true);
          mergeFamilyLibrary(result, shared, recent);
        }
      } catch (error) {
        result.familyStatus = 'unavailable';
        result.notices.push('家庭共享读取失败：' + (error as Error).message + ' 当前只显示个人游戏。');
      }
    }
    privacyAccess.check(privacyGeneration);
    this.cachedFamilyToken = familyToken;
    this.cachedAccount = normalizedAccount;
    this.cachedApiKey = key;
    this.cachedAt = Date.now();
    this.cachedData = result;
    return result;
  }

  private async request<T>(path: string, key: string, params: Record<string, string>, useToken: boolean = false): Promise<T> {
    const query: string[] = ['format=json'];
    if (useToken) query.push('access_token=' + encodeURIComponent(key));
    Object.keys(params).forEach((name: string) => {
      query.push(encodeURIComponent(name) + '=' + encodeURIComponent(params[name]));
    });
    const headers: Record<string, string> = { 'Accept': 'application/json' };
    if (!useToken) headers['x-webapi-key'] = key;
    const requestGeneration: number = privacyAccess.begin();
    const request = http.createHttp();
    let destroyed: boolean = false;
    const close: () => void = (): void => { if (!destroyed) { destroyed = true; request.destroy(); } };
    const unregister: () => void = privacyAccess.register(close, requestGeneration);
    try {
      let response: http.HttpResponse;
      try {
        response = await request.request('https://api.steampowered.com/' + path + '?' + query.join('&'), {
          method: http.RequestMethod.GET,
          header: headers,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 15000,
          readTimeout: 20000,
          usingCache: false
        });
      } catch (_) {
        // Never surface an upstream exception containing a credential-bearing URL.
        throw new Error('暂时无法连接 Steam，请检查网络后重试。');
      }
      privacyAccess.check(requestGeneration);
      if (response.responseCode === 401 || response.responseCode === 403) throw new Error(useToken ? 'Steam 登录授权已过期或无权访问，请重新登录。' : 'Steam 拒绝访问，请检查 API 密钥是否正确或已被撤销。');
      if (response.responseCode === 429) throw new Error('Steam 请求过于频繁，请稍后重试。');
      if (response.responseCode !== 200) throw new Error('Steam 服务暂不可用，HTTP ' + response.responseCode.toString());
      let envelope: SteamEnvelope<T>;
      try {
        envelope = JSON.parse(response.result as string) as SteamEnvelope<T>;
      } catch (_) {
        throw new Error('Steam 返回了无法读取的数据。');
      }
      if (!envelope || envelope.response === undefined || envelope.response === null) {
        throw new Error('Steam 返回的数据缺少 response 字段。');
      }
      return envelope.response;
    } finally {
      unregister(); close();
    }
  }
}
