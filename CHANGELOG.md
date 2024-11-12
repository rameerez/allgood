## [0.3.0] - 2024-10-27

- Added rate limiting for expensive checks with the `run: "N times per day/hour"` option
- Added a cache mechanism to store check results and error states, which allows for rate limiting and avoiding redundant runs when checks fail
- Added automatic cache key expiration
- Added error handling and feedback for rate-limited checks

## [0.2.0] - 2024-10-26

- Improved the `allgood` DSL by adding optional conditionals on when individual checks are run
- Allow for environment-specific checks with `only` and `except` options (`check "Test Check", only: [:development, :test]`)
- Allow for conditional checks with `if` and `unless` options, which can be procs or any other condition (`check "Test Check", if: -> { condition }`)
- Added visual indication of skipped checks in the healthcheck page
- Improved developer experience by showing why checks were skipped (didn't meet conditions, environment-specific, etc.)
- New DSL changes are fully backward compatible with the previous version (new options are optional, and checks will run normally if they are not specified), so the new version won't break existing configurations
- Changed configuration loading to happen after Rails initialization so we fix the segfault that could occur when requiring gems in the `allgood.rb` configuration file before Rails was initialized

## [0.1.0] - 2024-08-22

- Initial release
