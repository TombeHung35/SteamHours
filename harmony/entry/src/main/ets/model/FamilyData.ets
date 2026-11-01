import { Game, LibraryResponse } from './Library';
import { SteamRecentResponse, SteamGame } from './SteamData';

export const STEAM_LOGIN_URL: string = 'https://store.steampowered.com/login/?redir=%2Fabout%2F';
export const STEAM_TOKEN_URL: string = 'https://store.steampowered.com/pointssummary/ajaxgetasyncconfig';
export interface SteamLoginData { webapi_token?: string; }
export interface SteamLoginResponse { data?: SteamLoginData; }
export interface SteamFamilyGroup { family_groupid?: string; is_not_member_of_any_group?: boolean; }
export interface SteamSharedApp {
  appid: number;
  name?: string;
  owner_steamids?: string[];
  img_icon_hash?: string;
  exclude_reason?: number;
  app_type?: number;
  rt_playtime?: number;
  rt_last_played?: number;
}
export interface SteamSharedResponse { apps?: SteamSharedApp[]; owner_steamid?: string; }

export function isSteamLoginUrl(url: string): boolean {
  return /^https:\/\/(?:[a-z0-9-]+\.)*(?:steampowered\.com|steamcommunity\.com)(?:[/?#]|$)/i.test(url);
}

export function extractFamilyToken(result: string): string {
  // ArkWeb serializes JavaScript string results as JSON. Accept raw endpoint JSON too.
  let text: string = result;
  if (text.length > 262144) throw new Error('Steam 登录返回数据过大，请重试。');
  try {
    if (text.trim().startsWith('"')) text = JSON.parse(text) as string;
    const response: SteamLoginResponse = JSON.parse(text) as SteamLoginResponse;
    const token: string = response.data?.webapi_token || '';
    if (token.length < 20 || token.length > 8192 || !/^[A-Za-z0-9_.-]+$/.test(token)) throw new Error('invalid');
    return token;
  } catch (_) {
    throw new Error('尚未取得 Steam 登录授权。请完成官方页面登录，再点击“完成登录”。');
  }
}

function knownMinutes(value: number | undefined): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? Math.floor(value) : null;
}

export function mergeFamilyLibrary(library: LibraryResponse, shared: SteamSharedResponse,
  recent: SteamRecentResponse): LibraryResponse {
  if (shared.owner_steamid && shared.owner_steamid !== library.player.steamId) {
    throw new Error('Steam 登录账号与查询账号不一致，请登录该账号或修改 SteamID。');
  }
  if (!Array.isArray(shared.apps)) throw new Error('Steam 未返回家庭游戏清单，请重新登录后重试。');
  if ((shared.apps as SteamSharedApp[]).some((app: SteamSharedApp) => app === null || typeof app !== 'object')) {
    throw new Error('Steam 家庭清单格式异常，请稍后重试。');
  }
  const verifiedOwner: boolean = shared.owner_steamid === library.player.steamId;
  const recentAvailable: boolean = Array.isArray(recent.games) || recent.total_count === 0;
  const recentMap: Map<number, SteamGame> = new Map<number, SteamGame>();
  (recent.games || []).forEach((game: SteamGame) => recentMap.set(game.appid, game));
  const existing: Map<number, Game> = new Map<number, Game>();
  library.games.forEach((game: Game) => existing.set(game.appId, game));
  (shared.apps as SteamSharedApp[]).forEach((app: SteamSharedApp) => {
    if (!Number.isInteger(app.appid) || app.appid <= 0 || (app.exclude_reason !== undefined && app.exclude_reason !== 0) ||
      (app.app_type !== undefined && app.app_type !== 1)) return;
    const old: Game | undefined = existing.get(app.appid);
    if (old !== undefined) {
      if (old.totalMinutes === null && verifiedOwner) old.totalMinutes = knownMinutes(app.rt_playtime);
      return;
    }
    const recentGame: SteamGame | undefined = recentMap.get(app.appid);
    const personallyOwned: boolean = Array.isArray(app.owner_steamids) && (app.owner_steamids as string[]).includes(library.player.steamId);
    const game: Game = {
      appId: app.appid,
      name: app.name || '游戏 #' + app.appid.toString(),
      iconUrl: app.img_icon_hash ? 'https://media.steampowered.com/steamcommunity/public/images/apps/' + app.appid.toString() + '/' + app.img_icon_hash + '.jpg' : '',
      totalMinutes: verifiedOwner ? knownMinutes(app.rt_playtime) : knownMinutes(recentGame?.playtime_forever),
      recentMinutes: recentGame === undefined ? (recentAvailable ? 0 : null) : knownMinutes(recentGame.playtime_2weeks),
      lastPlayed: verifiedOwner ? (knownMinutes(app.rt_last_played) || 0) : (knownMinutes(recentGame?.rtime_last_played) || 0),
      source: personallyOwned ? 'owned' : 'family'
    };
    library.games.push(game);
    existing.set(app.appid, game);
  });
  library.games.sort((a: Game, b: Game) => (b.totalMinutes === null ? -1 : b.totalMinutes) - (a.totalMinutes === null ? -1 : a.totalMinutes));
  // An unavailable personal library cannot become a complete library merely because the family request succeeded.
  if (library.libraryStatus === 'available') library.gameCount = library.games.length;
  else library.notices.push('家庭清单已显示，但个人游戏库暂不可用，游戏总数和累计时长不完整。');
  const allKnown: boolean = library.libraryStatus === 'available' && library.games.every((game: Game) => game.totalMinutes !== null);
  library.totalMinutes = allKnown ? library.games.reduce((sum: number, game: Game) => sum + (game.totalMinutes || 0), 0) : null;
  library.notices = library.notices.filter((notice: string) =>
    !(allKnown && notice === '部分游戏时长未返回，累计时长暂不可用。') &&
    !(library.totalMinutes !== 0 && notice === '所有已返回时长均为 0，可能尚未游玩或受时长隐私设置影响。'));
  library.familyStatus = 'available';
  library.notices.push('已合并可共享的家庭游戏并去重；时长属于当前查询账号，不累计家庭成员的时长。');
  if (!allKnown) library.notices.push('部分游戏未返回个人时长，累计时长暂不可用。');
  return library;
}
