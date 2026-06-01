/// <reference types="vitest" />
import { defineConfig } from 'vitest/config'
import { resolve } from 'path'

export default defineConfig({
  esbuild: {
    jsx: 'automatic',
  },
  test: {
    // Test environment
    environment: 'happy-dom',
    
    // Setup files
    setupFiles: ['./vitest.setup.ts'],
    
    // Files to test
    include: [
      '**/__tests__/**/*.{js,jsx,ts,tsx}',
      '**/*.{test,spec}.{js,jsx,ts,tsx}'
    ],
    
    // Files to ignore
    exclude: [
      '**/node_modules/**',
      '**/dist/**',
      '**/.next/**',
      '**/coverage/**',
      '**/out/**'
    ],
    
    // Globals (optional - makes describe, it, expect available without imports)
    globals: true,
    
    // Coverage settings
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/',
        '.next/',
        'coverage/',
        'out/',
        '**/*.d.ts',
        '**/*.config.{js,ts}',
        'mocks/',
        'docs/',
        'app/docs/',
        'config/',
        'public/'
      ],
      thresholds: {
        global: {
          branches: 10,
          functions: 10,
          lines: 10,
          statements: 10
        }
      }
    }
  },
  resolve: {
    alias: {
      '@': resolve(__dirname, './')
    }
  }
})