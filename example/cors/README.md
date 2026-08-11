# CORS demo

Ten functions, one per CORS mode, plus a browser page and a curl script for
checking what each one actually returns.

| Function | Configuration | What you should see |
| --- | --- | --- |
| `corsoff` | none (the `onRequest` default) | no CORS headers |
| `corsoptout` | `corsDisabled` | no CORS headers, even under the emulator |
| `corsreflectany` | `corsAllowAnyOrigin` | the request's origin echoed back, plus `Vary: Origin` |
| `corswildcard` | `corsAnyOriginWildcard` | a literal `*`, and no `Vary: Origin` |
| `corssingleorigin` | `Cors([trusted])` | the trusted origin, sent even to other callers |
| `corsallowlist` | `Cors([trusted, ...])` | the origin echoed when listed, header absent otherwise |
| `corspattern` | `Cors([CorsPattern(...)])` | same, matched by regex |
| `corsthrows401` | `corsAllowAnyOrigin` | a 401 that still carries CORS headers |
| `corsthrows500` | `corsAllowAnyOrigin` | a 500 that still carries CORS headers |
| `corscallable` | callable default | `Access-Control-Allow-Methods: POST` only |

Note that deployed names are lowercased, so `corsSingleOrigin` in Dart is
`/corssingleorigin` in the URL.

## Run it locally

The emulator sets the `enableCors` debug feature, which widens every function to
"allow any origin". That is deliberate and matches the Node.js SDK, but it means
the emulator is the wrong place to see the per-mode differences: only
`corsoptout` will look different from the rest.

To see real behaviour without deploying, run the server directly, which skips
the debug feature entirely:

```sh
cd example/cors
dart run build_runner build --delete-conflicting-outputs
FIREBASE_PROJECT=demo-test PORT=8080 dart run bin/server.dart
```

Then in another shell:

```sh
./check-headers.sh http://127.0.0.1:8080
```

For the emulator instead:

```sh
firebase emulators:start --only functions --project demo-test
./check-headers.sh http://127.0.0.1:5001/demo-test/us-central1
```

## Check a deployment

```sh
firebase deploy --only functions --project YOUR_PROJECT
./check-headers.sh https://us-central1-YOUR_PROJECT.cloudfunctions.net
```

`check-headers.sh` prints the CORS headers for a preflight and a plain request,
from both a trusted and an untrusted origin. It takes the trusted origin as an
optional second argument, defaulting to `http://localhost:8000`.

## Check it from a real browser

`check-headers.sh` shows the header bytes; the browser decides what to do with
them. To see the enforcement, serve the page from an origin the functions trust:

```sh
cd example/cors/public
python3 -m http.server 8000
```

Open <http://localhost:8000>, paste your base URL, and hit **Run all**. Each row
reports whether the browser allowed or blocked the request.

The browser hides CORS response headers from JavaScript, so the page can only
report allowed vs blocked, never the header values. Use the script or the
Network tab for those.

If you serve the page from somewhere other than `http://localhost:8000`, edit
`trustedOrigin` at the top of `bin/server.dart` and redeploy, otherwise the
three allow-list rows will report `CHECK`.

## What to look for

- `Access-Control-Allow-Headers` echoes `authorization` on preflights. A literal
  `*` does not authorise that header, which is what used to break authenticated
  callables in the browser.
- `Vary: Origin` is present whenever the origin is reflected, and absent for the
  wildcard, which does not depend on the origin.
- The 401 and 500 still carry CORS headers. Without that the browser reports an
  opaque CORS failure and hides the real status.
- `corssingleorigin` returns its origin even to an untrusted caller, leaving the
  browser to reject it. `corsallowlist` omits the header instead. Both match the
  Node.js SDK, which collapses a one-element allow-list to a static value.
