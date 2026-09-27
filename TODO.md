# TODO

- [ ] Restore [`ash_authentication_phoenix`](https://hexdocs.pm/ash_authentication_phoenix/)
  after the manual authentication learning exercise. Keep the custom UI and
  controller-based login/registration, replace the application-owned session
  adapters with the official integration, and retain the authentication security tests. See
  [the current flow](docs/authentication.md).
- [ ] Reintroduce daily measurements and nutrition storage when its data source is ready.
  Keep the existing chart components and range controls; they currently receive no data.
  Photo-based AI analysis is not implemented yet.
- [ ] Review resource-level upload validation before adding upload entry points
  outside LiveView. Currently only LiveView enforces one JPG/PNG/WebP file up to
  8 MB; resource actions do not repeat these restrictions or explicitly reject
  empty files. Also review error handling for missing/unreadable files, which
  the current AshStorage implementation raises for.
- [ ] Review whether uploads need content inspection and pixel-dimension limits.
  Contents are not verified. Consider restoring
  [`ex_image_info`](https://hex.pm/packages/ex_image_info) for header-based checks
  or using full decoding if stronger verification is needed. Header inspection
  alone does not prove that an entire image is valid or safe.
