/*! coi-serviceworker v0.1.7 - MIT License */
if (typeof window === 'undefined') {
    self.addEventListener("install", () => self.skipWaiting());
    self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

    self.addEventListener("fetch", (event) => {
        if (event.request.cache === "only-if-cached" && event.request.mode !== "same-origin") {
            return;
        }

        event.respondWith(
            fetch(event.request)
                .then((response) => {
                    if (response.status === 0) {
                        return response;
                    }

                    const newHeaders = new Headers(response.headers);
                    newHeaders.set("Cross-Origin-Embedder-Policy", "require-corp");
                    newHeaders.set("Cross-Origin-Opener-Policy", "same-origin");

                    return new Response(response.body, {
                        status: response.status,
                        statusText: response.statusText,
                        headers: newHeaders,
                    });
                })
                .catch((e) => console.error(e))
        );
    });
} else {
    const script = document.currentScript;
    script.parentNode.removeChild(script);

    const coep = script.hasAttribute("coep");
    const coop = script.hasAttribute("coop");

    if (coep || coop) {
        if ("serviceWorker" in navigator) {
            navigator.serviceWorker.register(window.location.pathname + (window.location.pathname.endsWith("/") ? "" : "/") + "coi-serviceworker.js");
        }
    }
}
