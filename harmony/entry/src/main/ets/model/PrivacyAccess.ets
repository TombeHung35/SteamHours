// Revocation invalidates old completions even after a later re-consent.
export class PrivacyAccess {
  private allowed: boolean = false;
  private generation: number = 0;
  private cancellations: Array<() => void> = [];
  setAllowed(allowed: boolean): void {
    this.generation++; this.allowed = allowed;
    const pending: Array<() => void> = this.cancellations; this.cancellations = [];
    pending.forEach((cancel: () => void) => { try { cancel(); } catch (_) {} });
  }
  current(generation: number): boolean { return this.allowed && generation === this.generation; }
  begin(): number {
    if (!this.allowed) throw new Error('请先阅读并同意隐私政策后启用 Steam 查询。');
    return this.generation;
  }
  check(generation: number): void {
    if (!this.current(generation)) throw new Error('查询已因隐私选择变更而停止。');
  }
  register(cancel: () => void, generation: number): () => void {
    this.check(generation); this.cancellations.push(cancel);
    return (): void => { this.cancellations = this.cancellations.filter((item: () => void) => item !== cancel); };
  }
}
export const privacyAccess: PrivacyAccess = new PrivacyAccess();
