import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

// The coverage floor is raise-only (CLAUDE.md): the unattended runner refuses a change that lowers it.
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    // Local development: the API of the service this UI belongs to.
    proxy: { '/api': { target: 'http://localhost:8080', rewrite: (path) => path.replace(/^\/api/, '') } },
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['src/test/setup.ts'],
    coverage: {
      provider: 'v8',
      include: ['src/**/*.{ts,tsx}'],
      exclude: ['src/main.tsx', 'src/test/**', 'src/**/*.test.{ts,tsx}'],
      thresholds: { lines: 80, branches: 70 },
    },
  },
});
