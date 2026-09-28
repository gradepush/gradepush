# GradePush

## Requirements

- Docker with Compose v2.
- For local development and the demo: macOS or Linux, `curl`, and OpenSSL.
- For self-hosting: a public domain pointing to the server, with ports **80** and **443** open.

Download or clone [this repository](https://github.com/gradepush/gradepush), then run the commands from its directory.

## Try the demo

1. Start with sample data:

   ```sh
   DEMO_MODE=true HOST_PORT=4001 PHX_URL_PORT=4001 scripts/local-compose --env-file .env.example -p gradepush-demo up -d --build --wait
   ```

2. Open [https://localhost:4001/demo](https://localhost:4001/demo) and choose a role.

Local HTTPS is automatic. Your OS may ask for your password to trust the certificate.

## Self-host with Docker

1. Prepare the configuration:

   ```sh
   cp .env.example .env
   chmod 600 .env
   openssl rand -hex 32
   ```

2. Edit `.env`: set `PHX_HOST` to your domain, choose a unique `DB_PASSWORD`, paste the generated value into `SETUP_TOKEN`, and set `GRADEPUSH_IMAGE=ghcr.io/gradepush/gradepush:0.1.0`.
3. Start GradePush with automatic HTTPS:

   ```sh
   docker compose -f compose.yaml -f compose.https.yaml pull
   docker compose -f compose.yaml -f compose.https.yaml up -d --no-build --wait
   ```

4. Open `https://your-domain/setup`. Enter your token and institution name, create the GitHub App, then sign in with GitHub.

   If you left `SETUP_TOKEN` empty, retrieve your private setup link:

   ```sh
   docker compose -f compose.yaml -f compose.https.yaml exec app gradepush-setup
   ```

5. Connect a GitHub organization in **Settings → Organizations** and create your first classroom.

## Develop with Docker

1. Start the development environment:

   ```sh
   scripts/dev
   ```

2. Open [https://localhost:4000](https://localhost:4000). Edit the code locally; the app reloads automatically. `DEMO_MODE=true` is optional and enables sample data. GitHub setup requires a public HTTPS address, such as a tunnel.
3. Run checks:

   ```sh
   scripts/dev exec -e DEMO_MODE=false app mix precommit
   scripts/dev exec app scripts/test-release-env
   ```

4. Stop the development environment:

   ```sh
   scripts/dev down
   ```

[License](LICENSE) · [Contributing](CONTRIBUTING.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)
