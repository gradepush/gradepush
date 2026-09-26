# GradePush

GradePush is an open-source, self-hosted application for managing GitHub-based classrooms and assignments.

**Status: early development.**

## Run locally

With Docker and Docker Compose installed:

```sh
docker compose up --build
```

Open <http://localhost:4000>. The application listens on localhost by default.

The baseline includes an English/French page, PostgreSQL, Oban, and automatic database migrations. Authentication and classroom workflows are not implemented yet.

## Development

Runtime versions are pinned in `.tool-versions`; dependencies are locked in `mix.lock`.

```sh
docker compose -p gradepush-dev -f compose.yaml -f compose.dev.yaml up -d db
mix setup
mix phx.server
```

Run `mix precommit` to check compilation, formatting, code quality, and tests.

## Contributions

Bug reports and suggestions are welcome. External pull requests and code contributions are not accepted. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Copyright (c) 2026 Aevia Studio. Licensed under [AGPL-3.0-only](LICENSE).

Third-party licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
