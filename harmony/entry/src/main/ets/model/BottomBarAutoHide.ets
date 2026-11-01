// Track actual content offsets, rather than confusing per-frame deltas with an absolute position.
export class BottomBarAutoHide {
  private hidden: boolean = false;
  private lastOffset: number = 0;
  private direction: number = 0;
  private distance: number = 0;
  reset(offset: number = 0): void {
    this.hidden = false; this.lastOffset = Number.isFinite(offset) ? Math.max(0, offset) : 0;
    this.direction = 0; this.distance = 0;
  }
  update(offset: number, active: boolean, scrolling: boolean, atEnd: boolean): boolean {
    if (!Number.isFinite(offset)) return this.hidden;
    const current: number = Math.max(0, offset);
    const delta: number = current - this.lastOffset; this.lastOffset = current;
    if (!active || current <= 8 || atEnd) { this.reset(current); return false; }
    // Controller/layout events do not hide the actions, or contribute to the gesture threshold.
    if (!scrolling) { this.direction = 0; this.distance = 0; return this.hidden; }
    if (Math.abs(delta) < 0.5) return this.hidden;
    const direction: number = delta > 0 ? 1 : -1;
    if (direction !== this.direction) { this.direction = direction; this.distance = 0; }
    this.distance += Math.abs(delta);
    if (direction > 0 && current >= 96 && this.distance >= 40) { this.hidden = true; this.distance = 0; }
    else if (direction < 0 && this.distance >= 12) { this.hidden = false; this.distance = 0; }
    return this.hidden;
  }
}
