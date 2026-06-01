## 0.7.0-wip

- Fix manifest generation for function options declared with named factories,
  including `Memory.fromInt` in `CallableOptions`.
- Fix normalize function names by lowercasing only, not camelCase-to-kebab

## 0.6.0

- Add `runFunctions` as the primary API.
- Deprecate `fireUp` in favor of `runFunctions`.
- Split `README.md` into multiple pages:
  - `docs/config.md`
  - `docs/triggers.md`
  - `test/README.md`

## 0.5.2

- Add a comment to the generated manifest (`functions.yaml`) to indicate that
  it is managed by this package.
- Add "Learn more" and "Usage" sections to README.md.

## 0.5.1

- Update constraint: `meta: ^1.17.0`
- Remove the use of footnotes in README.md, since they are not supported by
  `package:markdown`.
- Add a landing page for the package examples.

## 0.5.0

- Initial release.
