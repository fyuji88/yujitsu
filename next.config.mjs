import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.dirname(fileURLToPath(import.meta.url));

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,

  // El alias "@/..." se declara aquí ademas de en tsconfig: TypeScript lo
  // resuelve por `paths`, pero el bundler necesita el suyo propio.
  turbopack: {
    resolveAlias: { '@': path.join(raiz, 'src') },
  },

  // La PWA la servimos con un service worker propio en /public/sw.js:
  // sin plugin, y así se ve exactamente qué se cachea.
  async headers() {
    return [{
      source: '/sw.js',
      headers: [
        { key: 'Cache-Control', value: 'public, max-age=0, must-revalidate' },
        { key: 'Service-Worker-Allowed', value: '/' },
      ],
    }];
  },
};

export default nextConfig;
