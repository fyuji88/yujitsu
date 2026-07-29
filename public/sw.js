// Service worker mínimo: cachea el esqueleto para que la app abra sin red.
// Los datos NO se cachean aquí — de eso se encarga IndexedDB (ver src/lib/db.ts).
// Subir el número al cambiar el esqueleto o el manifest: `activate` borra las
// cachés que no coincidan, y sin eso quien ya tenga la app instalada se queda
// con el manifest viejo — y con los iconos viejos — hasta que la reinstale.
const CACHE = 'bjj-v2';
const ESQUELETO = ['/', '/entreno', '/practicantes', '/manifest.webmanifest'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ESQUELETO)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;
  if (url.origin !== self.location.origin) return;   // nunca la API de Supabase

  e.respondWith(
    fetch(e.request)
      .then((r) => {
        const copia = r.clone();
        caches.open(CACHE).then((c) => c.put(e.request, copia)).catch(() => {});
        return r;
      })
      .catch(() => caches.match(e.request).then((r) => r || caches.match('/entreno'))),
  );
});
