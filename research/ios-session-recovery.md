# iOS session recovery — AF-732

Native audit follow-up: amux restored the saved driver slot without checking whether its WebDriver session still existed. Appium's installed base driver expires a session after 60 seconds without a command by default. Status could report not running while Go kept reusing the dead identifier.

An amux-owned native session now opts out of the idle timeout. Explicit Stop and ownership remain the lifecycle boundary. Individual WebDriver requests still have their existing bounded deadlines. On Go, amux first validates worker/device ownership and reads the saved driver's current URL. Only the explicit WebDriver `invalid session id` response releases that slot and its journal. Unknown/transport failures preserve both. The normal fresh-session path then opens the requested URL; no previous click, typing or command is replayed.

`go_releases_only_a_proven_expired_owned_session_without_replaying_actions` uses a real local HTTP mock and temporary journal. It checks the observed GET count, preserved/deleted file bytes and slot state for live, expired and unknown responses; other workers/devices are refused before any driver request. The focused iOS unit suite passed 8 tests. A recovery emits `expired_session_released` with `measured: true` and `n_considered: 1`; successful Go also reports `recovered_expired_session`.

Native tap calibration is being checked separately against the header audit. API dispatch acknowledgement alone is not a product-state assertion; the audit requires the requested dialog to open and close, and records failed screenshots rather than retrying command taps automatically.
