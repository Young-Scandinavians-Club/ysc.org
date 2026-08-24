# blurhash (vendored)

Vendored copy of hex package [`blurhash` 2.0.0](https://hex.pm/packages/blurhash)
(upstream: https://github.com/perzanko/blurhash-elixir), MIT licensed — see
`LICENSE.md`.

`encode_base83/2` builds a descending range with `Enum.reduce((length - 1)..0, ...)`,
which triggers an Elixir compiler deprecation warning on every compile
(`Range.new/2` and `first..last` default to a step of -1 when `last < first`).
2.0.0 is the latest published release and doesn't include a fix. This vendored
copy adds the explicit `//-1` step and is otherwise byte-for-byte identical to
upstream.

If a future `blurhash` release fixes this upstream, switch `mix.exs` back to
the hex dependency and delete this directory.
