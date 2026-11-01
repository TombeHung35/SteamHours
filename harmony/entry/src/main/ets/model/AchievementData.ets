export interface SteamAchievement { apiname: string; achieved?: number; unlocktime?: number; name?: string; description?: string; }
export interface SteamPlayerAchievements { steamID?: string; success?: boolean; achievements?: SteamAchievement[]; }
export interface SteamAchievementSchema { name: string; displayName?: string; description?: string; hidden?: number; icon?: string; icongray?: string; }
export interface SteamSchemaStats { achievements?: SteamAchievementSchema[]; }
export interface SteamGameSchema { availableGameStats?: SteamSchemaStats; }
export interface Achievement { id: string; name: string; description: string; iconUrl: string; unlocked: boolean | null; unlockTime: number; }
export interface AchievementResponse { status: string; unlocked: number; items: Achievement[]; message: string; }

export function normalizeAchievements(stats: SteamPlayerAchievements, schema: SteamGameSchema | null, steamId: string): AchievementResponse {
  const unavailable: AchievementResponse = { status: 'unavailable', unlocked: 0, items: [], message: 'Steam 未返回成就。请检查游戏详情隐私；尚未游玩或没有成就的游戏也可能无法读取。' };
  if (!stats || stats.success !== true || (stats.steamID && stats.steamID !== steamId) || !Array.isArray(stats.achievements)) return unavailable;
  if (stats.achievements.length > 10000 || stats.achievements.some((item: SteamAchievement) => !item || typeof item.apiname !== 'string' || !item.apiname)) return unavailable;
  const definitions: SteamAchievementSchema[] = Array.isArray(schema?.availableGameStats?.achievements) ? schema?.availableGameStats?.achievements as SteamAchievementSchema[] : [];
  const known: Map<string, SteamAchievement> = new Map<string, SteamAchievement>();
  stats.achievements.forEach((item: SteamAchievement) => known.set(item.apiname, item));
  const metadata: Map<string, SteamAchievementSchema> = new Map<string, SteamAchievementSchema>();
  definitions.slice(0, 10000).forEach((item: SteamAchievementSchema) => { if (item && typeof item.name === 'string' && item.name) metadata.set(item.name, item); });
  const ids: Set<string> = new Set<string>();
  metadata.forEach((_value, id: string) => ids.add(id)); known.forEach((_value, id: string) => ids.add(id));
  const items: Achievement[] = [];
  ids.forEach((id: string) => {
    const owned: SteamAchievement | undefined = known.get(id);
    const definition: SteamAchievementSchema | undefined = metadata.get(id);
    const unlocked: boolean | null = owned?.achieved === 1 ? true : (owned?.achieved === 0 ? false : null);
    const hidden: boolean = definition?.hidden === 1 && unlocked !== true;
    const icon: string = (unlocked === true ? definition?.icon : definition?.icongray) || '';
    items.push({ id: id, name: hidden ? '隐藏成就' : (definition?.displayName || owned?.name || id),
      description: hidden ? '解锁后显示详情' : (definition?.description || owned?.description || ''),
      iconUrl: /^https:\/\//.test(icon) ? icon : '', unlocked: unlocked,
      unlockTime: unlocked === true && Number.isSafeInteger(owned?.unlocktime) && (owned?.unlocktime || 0) > 0 ? owned?.unlocktime as number : 0 });
  });
  items.sort((a: Achievement, b: Achievement) => Number(b.unlocked === true) - Number(a.unlocked === true) || b.unlockTime - a.unlockTime || a.name.localeCompare(b.name));
  if (items.length === 0) return { status: 'none', unlocked: 0, items: [], message: '该游戏没有返回任何 Steam 成就。' };
  return { status: 'available', unlocked: items.filter((item: Achievement) => item.unlocked === true).length, items: items,
    message: items.some((item: Achievement) => item.unlocked === null) ? '部分成就状态未返回，保留为未知。' : (schema === null ? '成就图标和说明暂不可用，解锁记录仍可查看。' : '') };
}
