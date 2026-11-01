// Only the temporary Steam authorization page uses Navigation history.
// Main library/accounts/settings are sibling pages selected by Index.mainPage.
export class AccountNavigation {
  private paths: NavPathStack;
  private ready: boolean = false;

  constructor(paths: NavPathStack) { this.paths = paths; }
  markReady(): void { this.ready = true; }

  openFamily(): void {
    if (!this.ready) return;
    const names: string[] = this.paths.getAllPathName();
    if (names[names.length - 1] !== 'family') this.paths.pushPathByName('family', undefined);
  }

  back(): boolean {
    if (this.paths.size() === 0) return false;
    this.paths.pop();
    return true;
  }

  returnLibrary(): void { this.paths.clear(); }
}
