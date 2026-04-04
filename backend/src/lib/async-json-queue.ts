const encoder = new TextEncoder();

export class AsyncJsonQueue
  implements AsyncIterable<{ chunk: { bytes: Uint8Array } }>
{
  private readonly pending: Array<Uint8Array | null> = [];
  private readonly waiters: Array<(value: Uint8Array | null) => void> = [];
  private closed = false;

  enqueue(payload: Record<string, unknown>): void {
    this.enqueueBytes(encoder.encode(JSON.stringify(payload)));
  }

  enqueueBytes(bytes: Uint8Array): void {
    if (this.closed) {
      throw new Error('Cannot enqueue into a closed queue.');
    }
    const waiter = this.waiters.shift();
    if (waiter) {
      waiter(bytes);
      return;
    }
    this.pending.push(bytes);
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    const waiter = this.waiters.shift();
    if (waiter) {
      waiter(null);
      return;
    }
    this.pending.push(null);
  }

  async *[Symbol.asyncIterator](): AsyncIterator<{ chunk: { bytes: Uint8Array } }> {
    while (true) {
      const next = await this.next();
      if (next === null) {
        return;
      }
      yield {
        chunk: {
          bytes: next,
        },
      };
    }
  }

  private next(): Promise<Uint8Array | null> {
    if (this.pending.length > 0) {
      return Promise.resolve(this.pending.shift() ?? null);
    }

    return new Promise((resolve) => {
      this.waiters.push(resolve);
    });
  }
}
