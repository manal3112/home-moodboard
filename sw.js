// Lets the board be installed to the home screen (and so appear in Android's share menu).
// It deliberately caches nothing, so every visit loads the latest board.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));
