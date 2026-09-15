# AGENTS.md

Avro vs JSON encode/decode benchmark lab (Rails 8, no database).

## Local Ruby

Use **mise** for Ruby (`mise exec` / `mise install`). Ruby 4.0.5 is pinned in
`mise.toml` + `.ruby-version`. Do not use Homebrew Ruby.

## Rails conventions

Load `rails-dev` (see `.agents/skills/rails-dev/SKILL.md`) **before** writing or
reviewing any Rails code: models, controllers, routes, views, Stimulus,
Minitest tests, style rules.

## Scope of this app

- No Active Record, no jobs, no Action Cable: pure request/response encoding.
- Server encodes with the Apache `avro` gem; client decodes Avro object
  container files back to JSON and logs decode time.
- One route surface: the editor page (GET) and the encode-and-download POST.

## Agents do not commit or push unless the human asks
