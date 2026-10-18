/* FLEXO PWA shell: network-first so the installed app can receive new GitHub Pages releases. */
const CACHE_NAME = 'flexo-shell-20261018-2';
const APP_SHELL = ['./', './index.html', './manifest.webmanifest'];
self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(APP_SHELL.map(path => new Request(path, {cache: 'reload'})).map(req => req.url));
    await self.skipWaiting();
  })());
});
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(key => key.startsWith('flexo-shell-') && key !== CACHE_NAME).map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});
self.addEventListener('fetch', event => {
  const req = event.request;
  const url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== self.location.origin) return;
  if (req.mode === 'navigate') {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE_NAME);
      try {
        const fresh = await fetch(req, {cache: 'no-store'});
        if (fresh && fresh.ok) await cache.put('./index.html', fresh.clone());
        return fresh;
      } catch (err) {
        return (await cache.match('./index.html')) || (await cache.match('./')) || Response.error();
      }
    })());
  }
});
