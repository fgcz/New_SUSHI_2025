// Jest polyfills file - runs before test environment setup
// Required for MSW v2 compatibility with jsdom
// Based on MSW documentation: https://mswjs.io/docs/migrations/1.x-to-2.x

// Set test environment variables before any modules are loaded
process.env.NEXT_PUBLIC_API_URL = 'http://localhost:4000';

const { TextDecoder, TextEncoder } = require('util');
const { ReadableStream, TransformStream } = require('stream/web');
const { MessageChannel, MessagePort, BroadcastChannel } = require('worker_threads');

// Polyfill TextEncoder/TextDecoder
Object.defineProperties(globalThis, {
  TextDecoder: { value: TextDecoder },
  TextEncoder: { value: TextEncoder },
});

// Polyfill Web Streams API
Object.defineProperties(globalThis, {
  ReadableStream: { value: ReadableStream },
  TransformStream: { value: TransformStream },
});

// Polyfill MessageChannel/MessagePort/BroadcastChannel
Object.defineProperties(globalThis, {
  MessageChannel: { value: MessageChannel },
  MessagePort: { value: MessagePort },
  BroadcastChannel: { value: BroadcastChannel },
});

// Polyfill Fetch API from undici
const { fetch, Headers, Request, Response, FormData } = require('undici');

Object.defineProperties(globalThis, {
  fetch: { value: fetch, writable: true, configurable: true },
  Headers: { value: Headers, configurable: true },
  Request: { value: Request, configurable: true },
  Response: { value: Response, configurable: true },
  FormData: { value: FormData, configurable: true },
});

