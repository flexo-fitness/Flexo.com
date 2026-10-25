/* FLEXO · service worker
   Qué hace:
   - Guarda en caché lo mínimo para abrir la app sin conexión: la interfaz (HTML, iconos, manifest),
     la librería de Supabase (CDN) y las fuentes de Google.
   - Pide siempre primero a la red el HTML (así recibes la última versión) y solo usa la copia
     guardada si no hay conexión o la red tarda demasiado.
   - NUNCA intercepta ni guarda las llamadas a Supabase (datos, autenticación, API): lo personal
     siempre va directo a la red.
   Para publicar cambios de esta política, cambia el número de VERSION. */
const VERSION = 'v1';
const CACHE = 'flexo-shell-' + VERSION;
const SHELL = ['./', 'index.html', 'app.html', 'manifest.webmanifest',
               'icons/icon.svg', 'icons/apple-touch-icon.png', 'icons/icon-192.png', 'icons/icon-512.png'];
const SUPABASE_JS = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';
const FONT_HOSTS = ['fonts.googleapis.com', 'fonts.gstatic.com'];
const NAV_TIMEOUT_MS = 4000;

const abs = u => new URL(u, self.registration.scope).href;

self.addEventListener('install', e => e.waitUntil((async () => {
  const cache = await caches.open(CACHE);
  await Promise.allSettled(SHELL.map(u => cache.add(new Request(abs(u), { cache: 'reload' }))));
  try { const req = new Request(SUPABASE_JS); await cache.put(req, await fetch(req)); } catch (_) {}
  await self.skipWaiting();
})()));

self.addEventListener('activate', e => e.waitUntil((async () => {
  for (const k of await caches.keys()) {
    if (k !== CACHE && k.startsWith('flexo-')) await caches.delete(k);
  }
  await self.clients.claim();
})()));

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin === new URL(self.registration.scope).origin) {
    if (req.mode === 'navigate') return e.respondWith(networkFirst(e, req));
    return e.respondWith(staleWhileRevalidate(e, req));
  }
  if (req.url === SUPABASE_JS || FONT_HOSTS.includes(url.hostname)) {
    return e.respondWith(staleWhileRevalidate(e, req));
  }
  // Todo lo demás (API y autenticación de Supabase, etc.) no se intercepta.
});

function withTimeout(promise, ms) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout')), ms);
    promise.then(v => { clearTimeout(t); resolve(v); }, err => { clearTimeout(t); reject(err); });
  });
}

async function networkFirst(e, req) {
  const cache = await caches.open(CACHE);
  const net = fetch(req);
  try {
    const res = await withTimeout(net, NAV_TIMEOUT_MS);
    if (res && res.ok) cache.put(req, res.clone());
    return res;
  } catch (_) {
    net.then(res => { if (res && res.ok) cache.put(req, res.clone()); }).catch(() => {});
    const isRoot = new URL(req.url).pathname === new URL(self.registration.scope).pathname;
    const hit = (await cache.match(req, { ignoreVary: true }))
             || (await cache.match(req, { ignoreSearch: true, ignoreVary: true }))
             || (isRoot ? await cache.match(abs('./'), { ignoreVary: true }) : null);
    return hit || new Response('Sin conexión. Vuelve a intentarlo cuando tengas internet.', {
      status: 503, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
  }
}

async function staleWhileRevalidate(e, req) {
  const cache = await caches.open(CACHE);
  const hit = await cache.match(req, { ignoreVary: true });
  const update = fetch(req).then(res => {
    if (res && (res.ok || res.type === 'opaque')) cache.put(req, res.clone());
    return res;
  }).catch(() => null);
  if (hit) { e.waitUntil(update); return hit; }
  return (await update) || new Response('', { status: 504, statusText: 'Sin conexión' });
}
