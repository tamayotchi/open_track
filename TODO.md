# TODO

## Production follow-ups

See [the deployment checklist](docs/production.md). Passing tests is not a production certification.

- [x] Revalidate mounted sessions before background messages. Food PubSub/polling has
  been removed; `LiveUserAuth` now guards `handle_info` as well as events/navigation.
  A regression test verifies revocation blocks a background message.
- [ ] Configure and verify login/registration/upload abuse controls at the trusted ingress.
  The application has no account/IP rate limiter; concurrency limits are not rate limits.
- [ ] Implement Oban if every upload must eventually receive analysis. The current
  two-slot supervisor has no waiting queue, job retry, or restart recovery.
  HTTP retries follow ReqLLM's defaults.
## Other follow-ups

- [ ] Restore [`ash_authentication_phoenix`](https://hexdocs.pm/ash_authentication_phoenix/)
  after the manual authentication learning exercise. Keep the custom UI and
  controller-based login/registration, replace the application-owned session
  adapters with the official integration, and retain the authentication security tests. See
  [the current flow](docs/authentication.md).
- [ ] Reintroduce daily measurements when their data source is ready.
  Keep the existing chart components and range controls. Calories and protein now use
  saved AI photo estimates by UTC upload date; weight, steps, and body-fat charts remain
  empty. Keep measured values distinct from photo estimates and personal targets.
- [ ] Review whether uploads need content inspection and pixel-dimension limits.
  LiveView checks extensions and upload size, not full image validity or dimensions.
  Analysis uses stored bytes and MIME metadata without revalidating the upload.
  Any additional validation belongs in the upload flow. Consider restoring
  [`ex_image_info`](https://hex.pm/packages/ex_image_info) for header-based checks
  or using full decoding if stronger verification is needed. Header inspection
  alone does not prove that an entire image is valid or safe.
