import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Game, LibraryResponse } from '../model/Library';
import { parseAccount } from '../model/SteamData';

interface LibrarySnapshot { version: number; account: string; includeFamily: boolean; library: LibraryResponse; }
export function normalizeLibrarySort(value: number): number {
  return Number.isInteger(value) && value >= 0 && value <= 3 ? value : 0;
}
function accountReference(account: string): string {
  const parsed = parseAccount(account);
  return parsed.steamId || parsed.vanity.toLowerCase();
}
function count(value: number | null): number | null {
  if (value === null) return null;
  if (!Number.isSafeInteger(value) || value < 0) throw new Error('invalid cache');
  return value;
}
function text(value: string, maximum: number = 2048): string {
  if (typeof value !== 'string' || value.length > maximum) throw new Error('invalid cache');
  return value;
}
// Explicit fields keep credentials and unknown upstream properties out of ordinary storage.
function snapshotCopy(value: LibraryResponse): LibraryResponse {
  if (!value || value.demo !== false || !value.player || !/^\d{17}$/.test(value.player.steamId) ||
    !Array.isArray(value.games) || value.games.length > 20000 || !Array.isArray(value.notices) || value.notices.length > 100 ||
    !Number.isFinite(Date.parse(value.fetchedAt)) || !['available', 'unavailable'].includes(value.libraryStatus) ||
    !['available', 'unavailable'].includes(value.recentStatus)) throw new Error('invalid cache');
  const ids: Set<number> = new Set<number>();
  const games: Game[] = value.games.map((game: Game): Game => {
    if (!game || !Number.isSafeInteger(game.appId) || game.appId <= 0 || ids.has(game.appId) ||
      !Number.isSafeInteger(game.lastPlayed) || game.lastPlayed < 0) throw new Error('invalid cache');
    ids.add(game.appId);
    return { appId: game.appId, name: text(game.name, 512), iconUrl: text(game.iconUrl),
      totalMinutes: count(game.totalMinutes), recentMinutes: count(game.recentMinutes), lastPlayed: game.lastPlayed,
      source: game.source === 'family' ? 'family' : 'owned' };
  });
  const result: LibraryResponse = {
    player: { steamId: value.player.steamId, name: text(value.player.name, 512), avatarUrl: text(value.player.avatarUrl), profileUrl: text(value.player.profileUrl) },
    games: games, gameCount: count(value.gameCount), totalMinutes: count(value.totalMinutes), recentMinutes: count(value.recentMinutes),
    libraryStatus: value.libraryStatus, recentStatus: value.recentStatus,
    notices: value.notices.map((notice: string): string => text(notice)), fetchedAt: value.fetchedAt, demo: false
  };
  if (value.libraryStatus === 'available' && result.gameCount !== games.length) throw new Error('invalid cache');
  if (['available', 'unavailable', 'none'].includes(value.familyStatus || '')) result.familyStatus = value.familyStatus;
  return result;
}

export class LibraryStore {
  private async store(context: common.UIAbilityContext): Promise<preferences.Preferences> {
    return preferences.getPreferences(context, { name: 'steam_hours_library_v1' });
  }
  async read(context: common.UIAbilityContext, account: string, includeFamily: boolean): Promise<LibraryResponse | null> {
    try {
      const store = await this.store(context);
      const raw: string = await store.get('snapshot', '') as string;
      if (typeof raw !== 'string' || !raw || raw.length > 2000000) return null;
      const saved: LibrarySnapshot = JSON.parse(raw) as LibrarySnapshot;
      if (!saved || saved.version !== 1 || saved.account !== accountReference(account) || saved.includeFamily !== includeFamily) return null;
      const library = snapshotCopy(saved.library);
      const parsed = parseAccount(account);
      if (parsed.steamId && parsed.steamId !== library.player.steamId) return null;
      return library;
    } catch (_) { return null; }
  }
  async readSort(context: common.UIAbilityContext): Promise<number> {
    try { return normalizeLibrarySort(await (await this.store(context)).get('sort', 0) as number); } catch (_) { return 0; }
  }
  private async put(context: common.UIAbilityContext, key: string, value: string | number): Promise<void> {
    const store = await this.store(context);
    const previous: preferences.ValueType = await store.get(key, key === 'sort' ? 0 : '');
    try { await store.put(key, value); await store.flush(); }
    catch (_) { try { await store.put(key, previous); } catch (_) {} throw new Error('游戏库本地保存失败，请重试。'); }
  }
  async save(context: common.UIAbilityContext, account: string, includeFamily: boolean, library: LibraryResponse): Promise<void> {
    const saved: LibrarySnapshot = { version: 1, account: accountReference(account), includeFamily: includeFamily, library: snapshotCopy(library) };
    const raw: string = JSON.stringify(saved);
    if (raw.length > 2000000) throw new Error('游戏库较大，未能完整保存到本地。');
    await this.put(context, 'snapshot', raw);
  }
  async saveSort(context: common.UIAbilityContext, value: number): Promise<void> { await this.put(context, 'sort', normalizeLibrarySort(value)); }
  async clear(context: common.UIAbilityContext): Promise<void> { await this.put(context, 'snapshot', ''); }
}
