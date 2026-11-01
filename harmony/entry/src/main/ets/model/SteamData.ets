import { Game, LibraryResponse } from './Library';

export interface SteamAccount {
  steamId: string;
  vanity: string;
}
export interface SteamPlayer {
  steamid: string;
  personaname?: string;
  avatarfull?: string;
  avatarmedium?: string;
  avatar?: string;
}
export interface SteamGame {
  appid: number;
  name?: string;
  img_icon_url?: string;
  playtime_forever?: number;
  playtime_2weeks?: number;
  rtime_last_played?: number;
}
export interface SteamPlayersResponse { players?: SteamPlayer[]; }
export interface SteamOwnedResponse { game_count?: number; games?: SteamGame[]; }
export interface SteamRecentResponse { total_count?: number; games?: SteamGame[]; }
export interface SteamVanityResponse { success?: number; steamid?: string; }
export interface SteamEnvelope<T> { response: T; }

export function validateApiKey(value: string): string {
  const key: string = value.trim();
  if (!/^[A-Fa-f0-9]{32}$/.test(key)) {
    throw new Error('请输入完整的 32 位 Steam Web API 密钥。');
  }
  return key;
}

export function parseAccount(value: string): SteamAccount {
  const input: string = value.trim();
  if (!input || input.length > 256) throw new Error('请输入 SteamID64 或 Steam 个人主页链接。');
  if (/^\d{17}$/.test(input)) return { steamId: input, vanity: '' };
  // Parse only the known Steam profile URL shape. User input never becomes a request host.
  const link: RegExpMatchArray | null = input.match(/^(?:https?:\/\/)?(?:www\.)?steamcommunity\.com\/(profiles|id)\/([A-Za-z0-9_-]+)\/?(?:\?[^#\s]*)?(?:#[^\s]*)?$/i);
  if (link !== null) {
    if (link[1] === 'profiles') {
      if (!/^\d{17}$/.test(link[2])) throw new Error('SteamID64 应为 17 位数字。');
      return { steamId: link[2], vanity: '' };
    }
    return { steamId: '', vanity: link[2] };
  }
  if (/^[A-Za-z][A-Za-z0-9_-]{1,63}$/.test(input)) return { steamId: '', vanity: input };
  throw new Error('请输入 17 位 SteamID64、个人主页链接或自定义主页名称。');
}

function minutes(value: number | undefined): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) return null;
  return Math.floor(value);
}

export function normalizeLibrary(player: SteamPlayer, owned: SteamOwnedResponse,
  recent: SteamRecentResponse, fetchedAt: string): LibraryResponse {
  if (!player || !/^\d{17}$/.test(player.steamid)) throw new Error('没有找到这个 Steam 用户。');
  const libraryAvailable: boolean = Array.isArray(owned.games) || owned.game_count === 0;
  const recentAvailable: boolean = Array.isArray(recent.games) || recent.total_count === 0;
  const ownedGames: SteamGame[] = Array.isArray(owned.games) ? owned.games as SteamGame[] : [];
  const recentGames: SteamGame[] = Array.isArray(recent.games) ? recent.games as SteamGame[] : [];
  const recentMap: Map<number, SteamGame> = new Map<number, SteamGame>();
  recentGames.forEach((game: SteamGame) => recentMap.set(game.appid, game));
  const games: Game[] = ownedGames.map((game: SteamGame): Game => {
    const recentGame: SteamGame | undefined = recentMap.get(game.appid);
    let recentMinutes: number | null = minutes(game.playtime_2weeks);
    if (recentMinutes === null && recentAvailable) {
      recentMinutes = recentGame === undefined ? 0 : minutes(recentGame.playtime_2weeks);
    }
    return {
      appId: game.appid,
      name: game.name || '游戏 #' + game.appid.toString(),
      iconUrl: game.img_icon_url ? 'https://media.steampowered.com/steamcommunity/public/images/apps/' + game.appid.toString() + '/' + game.img_icon_url + '.jpg' : '',
      totalMinutes: minutes(game.playtime_forever),
      recentMinutes: recentMinutes,
      lastPlayed: minutes(game.rtime_last_played) || 0,
      source: 'owned'
    };
  });
  games.sort((a: Game, b: Game) => (b.totalMinutes === null ? -1 : b.totalMinutes) - (a.totalMinutes === null ? -1 : a.totalMinutes));
  const totalKnown: boolean = libraryAvailable && games.every((game: Game) => game.totalMinutes !== null);
  const recentKnown: boolean = recentAvailable && recentGames.every((game: SteamGame) => minutes(game.playtime_2weeks) !== null);
  let totalMinutes: number | null = null;
  if (totalKnown) totalMinutes = games.reduce((sum: number, game: Game) => sum + (game.totalMinutes === null ? 0 : game.totalMinutes), 0);
  let recentMinutes: number | null = null;
  if (recentKnown) recentMinutes = recentGames.reduce((sum: number, game: SteamGame) => sum + (minutes(game.playtime_2weeks) || 0), 0);
  const notices: string[] = [];
  if (!libraryAvailable) notices.push('Steam 未返回游戏库。请检查游戏详情隐私设置；空响应也可能表示资料暂不可用。');
  if (!totalKnown && libraryAvailable) notices.push('部分游戏时长未返回，累计时长暂不可用。');
  if (games.length > 0 && totalKnown && totalMinutes === 0) notices.push('所有已返回时长均为 0，可能尚未游玩或受时长隐私设置影响。');
  if (!recentAvailable) notices.push('最近两周数据暂不可用，已获取的累计时长仍可查看。');
  if (libraryAvailable) notices.push('统计以 Steam 接口返回的数据为准，未返回的游戏不计入。');
  return {
    player: { steamId: player.steamid, name: player.personaname || 'Steam 玩家', avatarUrl: player.avatarfull || player.avatarmedium || player.avatar || '', profileUrl: 'https://steamcommunity.com/profiles/' + player.steamid + '/' },
    games: games,
    gameCount: libraryAvailable ? games.length : null,
    totalMinutes: totalMinutes,
    recentMinutes: recentMinutes,
    libraryStatus: libraryAvailable ? 'available' : 'unavailable',
    recentStatus: recentAvailable ? 'available' : 'unavailable',
    notices: notices,
    fetchedAt: fetchedAt,
    demo: false
  };
}
