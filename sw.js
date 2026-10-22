// Service worker de Flota MSMIN: permite abrir la app y hacer el check sin internet.
// La página se pide primero a la red (para recibir actualizaciones) y si no hay conexión se usa la copia guardada.
// Las librerías y fuentes se guardan la primera vez y luego se sirven desde el teléfono.
const VERSION = "flota-v5";
const PROPIOS = ["./", "./index.html", "./manifest.webmanifest", "./icon-192.png", "./icon-512.png", "./apple-touch-icon.png"];
const LIBRERIAS = [
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.min.js",
  "https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js",
  "https://cdn.jsdelivr.net/npm/exceljs@4.4.0/dist/exceljs.min.js"
];

self.addEventListener("install", ev => {
  ev.waitUntil(caches.open(VERSION).then(async c => {
    await c.addAll(PROPIOS);
    // Si alguna librería falla no se bloquea la instalación; se guardará al usarla
    await Promise.all(LIBRERIAS.map(u => c.add(u).catch(() => {})));
  }).then(() => self.skipWaiting()));
});

self.addEventListener("activate", ev => {
  ev.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

self.addEventListener("fetch", ev => {
  const req = ev.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.hostname.endsWith("supabase.co")) return; // datos: siempre en vivo, la app maneja el modo sin conexión

  if (req.mode === "navigate" || (url.origin === location.origin && url.pathname.endsWith(".html"))) {
    // no-cache: siempre se pregunta al servidor si hay versión nueva antes de usar la copia del navegador
    ev.respondWith(fetch(req.url, { cache: "no-cache", credentials: "same-origin" }).then(r => {
      const copia = r.clone(); caches.open(VERSION).then(c => c.put("./index.html", copia)); return r;
    }).catch(() => caches.match("./index.html")));
    return;
  }
  const estatico = url.origin === location.origin || url.hostname === "cdn.jsdelivr.net" || url.hostname === "fonts.googleapis.com" || url.hostname === "fonts.gstatic.com";
  if (!estatico) return;
  ev.respondWith(caches.match(req).then(hit => hit || fetch(req).then(r => {
    if (r.ok || r.type === "opaque") { const copia = r.clone(); caches.open(VERSION).then(c => c.put(req, copia)); }
    return r;
  })));
});
