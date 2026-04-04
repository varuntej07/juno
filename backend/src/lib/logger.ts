type Metadata = Record<string, unknown> | undefined;

const print = (level: string, message: string, metadata?: Metadata): void => {
  const timestamp = new Date().toISOString();
  if (metadata && Object.keys(metadata).length > 0) {
    console.log(`${timestamp} [${level}] ${message}`, metadata);
    return;
  }
  console.log(`${timestamp} [${level}] ${message}`);
};

export const logger = {
  info(message: string, metadata?: Metadata): void {
    print('INFO', message, metadata);
  },
  warn(message: string, metadata?: Metadata): void {
    print('WARN', message, metadata);
  },
  error(message: string, metadata?: Metadata): void {
    print('ERROR', message, metadata);
  },
};
