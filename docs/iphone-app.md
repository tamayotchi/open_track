# OpenTrack on iPhone

OpenTrack can be installed from Safari as a Home Screen web app. This reuses the
Phoenix/Ash application; it is not a native iOS app and cannot request HealthKit
permissions. An internet connection is still required. There is no service worker,
offline editing, push notification registration, or private-data caching in this version.

## Install

After deploying these changes to the HTTPS site:

1. Open **https://track.tamayotchi.com** in **Safari** on your iPhone.
2. Choose **Share → Add to Home Screen** (Share may be inside Safari's page menu).
3. If shown, enable **Open as Web App**, then tap **Add**.
4. Launch **OpenTrack** from the new Home Screen icon. Sign in there if needed.

Installation does not require the App Store or an Apple developer account.
Safari and the installed app may have separate browser storage. Installing the
app does not bypass login or change logout/revocation behavior. New logins use a
365-day token and persistent cookie, so closing the app should not itself require
another login. After deploying the persistence fix, log out and log in once
inside the installed app; existing tokens keep their previous expiry.
If an older Home Screen shortcut still shows the old icon or browser controls,
remove that shortcut and add it again after deployment.

## iPhone test checklist

- **Installation:** Check the icon and name, then launch without Safari's toolbar.
  A signed-out launch should show login; signing in should open Home (`/app`).
- **Navigation:** Use Home, Add food, Account, Settings, and Security. Login and
  registration must stay inside the app (the manifest scope includes `/users/`).
- **Safe areas:** Check portrait and landscape on a notched iPhone. The header,
  content, notifications, and bottom tabs must not sit under the notch or home indicator.
- **Keyboard:** Edit email/password and settings fields. Inputs should not auto-zoom;
  the bottom dock should disappear on narrow screens while the software keyboard
  is open, and return when dismissed. Buttons and errors must remain reachable.
  Pinch zoom and hardware-keyboard focus should not hide navigation.
- **Photos:** Choose a library photo and try Safari's camera option. Preview, save,
  and remove a selection. The picker is not forced to camera-only. Existing support
  remains JPG/JPEG, PNG, or WebP, one file under 8 MB; HEIC is not newly supported.
  Confirm the filename/type Safari supplies, especially for camera photos.
- **Sessions:** Close and reopen the app while its session is valid, switch to
  another app, and lock/unlock the phone. Check login and reconnection. Phoenix's
  existing socket lifecycle handles resume; no custom forced reload discards forms.
  iOS can discard browser storage; sign in again if needed.
- **Logout:** Log out and reopen. Private pages must remain protected; a copied or
  revoked session must not restore access.
- **Connection:** Toggle airplane mode while open, then reconnect. The existing
  connection notice should appear. A cold launch offline is not supported.
- **Accessibility:** Try larger text, pinch zoom, and small screen widths. Tap
  targets (including notification close buttons) should remain comfortable.

## Implementation and checks

- `priv/static/manifest.webmanifest`: stable app ID, `/app` launch, root scope,
  standalone display, colors, and 192/512-pixel icons.
- `lib/open_track_web/components/layouts/root.html.heex`: shared manifest link,
  Apple metadata, 180-pixel touch icon, and the existing `viewport-fit=cover`.
- `assets/css/app.css`: top/bottom/landscape safe areas and keyboard-aware dock.
- `assets/js/mobile.js`: progressive VisualViewport enhancement; no auth changes.
- `assets/images/app-icon.svg`: editable icon source. To regenerate PNGs with librsvg:

  ```sh
  rsvg-convert -w 180 -h 180 assets/images/app-icon.svg -o priv/static/images/icons/apple-touch-icon.png
  rsvg-convert -w 192 -h 192 assets/images/app-icon.svg -o priv/static/images/icons/icon-192.png
  rsvg-convert -w 512 -h 512 assets/images/app-icon.svg -o priv/static/images/icons/icon-512.png
  ```

Automated checks:

```sh
mix precommit
MIX_ENV=test mix assets.build
node --test test/js/mobile_test.mjs
```

Endpoint tests check public metadata/icon serving, PNG dimensions, and protected
launch behavior. JavaScript tests cover software-keyboard detection, zoom, focus,
and resume. Actual Safari installation, camera behavior, and iOS session storage
still require the real-device checklist above.

Deploy using the existing [Kamal instructions](production.md). These files are
served by Phoenix and included in the regular asset/release build; no additional
external scripts, CDN, or native-app build is required.
