export interface Player {
  steamId: string;
  name: string;
  avatarUrl: string;
  profileUrl: string;
}

export interface Game {
  appId: number;
  name: string;
  iconUrl: string;
  totalMinutes: number | null;
  recentMinutes: number | null;
  lastPlayed: number;
  source?: string;
}

export interface LibraryResponse {
  player: Player;
  games: Game[];
  gameCount: number | null;
  totalMinutes: number | null;
  recentMinutes: number | null;
  libraryStatus: string;
  recentStatus: string;
  notices: string[];
  fetchedAt: string;
  demo: boolean;
  familyStatus?: string;
}

export function formatHours(value: number | null): string {
  if (value === null) return '不可用';
  if (value === 0) return '0';
  if (value < 6) return '< 0.1';
  return (value / 60).toFixed(1);
}

export function emptyLibrary(): LibraryResponse {
  return { player: { steamId: '', name: '连接你的 Steam', avatarUrl: '', profileUrl: '' },
    games: [], gameCount: null, totalMinutes: null, recentMinutes: null,
    libraryStatus: 'unavailable', recentStatus: 'unavailable', notices: [], fetchedAt: '', demo: false };
}

export function demoLibrary(): LibraryResponse {
  const games: Game[] = [
    { appId: 730, name: 'Counter-Strike 2', iconUrl: '', totalMinutes: 48216, recentMinutes: 746, lastPlayed: 0 },
    { appId: 570, name: 'Dota 2', iconUrl: '', totalMinutes: 25740, recentMinutes: 320, lastPlayed: 0 },
    { appId: 1245620, name: 'ELDEN RING', iconUrl: '', totalMinutes: 9540, recentMinutes: 185, lastPlayed: 0 },
    { appId: 1091500, name: 'Cyberpunk 2077', iconUrl: '', totalMinutes: 6810, recentMinutes: 96, lastPlayed: 0 },
    { appId: 413150, name: 'Stardew Valley', iconUrl: '', totalMinutes: 4530, recentMinutes: 180, lastPlayed: 0 },
    { appId: 400, name: 'Portal', iconUrl: '', totalMinutes: 0, recentMinutes: 0, lastPlayed: 0 }
  ];
  return {
    player: { steamId: '76561198000000000', name: '我的游戏时光 · 演示', avatarUrl: '', profileUrl: '' },
    games: games,
    gameCount: 6,
    totalMinutes: 94836,
    recentMinutes: 1527,
    libraryStatus: 'available',
    recentStatus: 'available',
    notices: ['当前为演示数据，不属于任何真实账号。'],
    fetchedAt: '',
    demo: true
  };
}
