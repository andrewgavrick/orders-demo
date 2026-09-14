import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
    watch: { usePolling: true },
    proxy: {
      '/v1': 'http://backend:3000',
      '/up': 'http://backend:3000',
    },
  },
})
