<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/gradepush/.github/main/profile/assets/gradepush-logo-on-dark.svg">
  <img src="https://raw.githubusercontent.com/gradepush/.github/main/profile/assets/gradepush-logo.svg" alt="GradePush" width="280">
</picture>

GradePush Classroom is an open-source, self-hosted alternative to GitHub Classroom. Create classrooms, distribute individual or team assignments, and follow student progress with GitHub repositories and automated tests.

## Requirements

- Docker with Compose v2.32 or newer (Linux containers on Windows).
- For trusted local HTTPS on macOS/Linux: `curl` and OpenSSL.
- For self-hosting: `curl`, OpenSSL, and a public domain pointing to the server, with ports **80** and **443** open.

## Self-host with Docker

For complete installation instructions, follow the [self-hosting installation guide](https://docs.gradepush.ca/self-hosting/installation/).

Uses the published image with PostgreSQL and Caddy. No repository clone or build is required.

1. Point your domain to the server's public IP and open ports **80** and **443**.

2. Download and run the installer on your Linux server or macOS:

   ```sh
   curl -fsSLO https://raw.githubusercontent.com/gradepush/gradepush/main/scripts/install.sh
   sh install.sh
   ```

   Enter your domain. The installer creates `gradepush/compose.yaml` and `.env`, generates secrets, and displays your private setup link.

3. Start GradePush:

   ```sh
   cd gradepush
   docker compose pull
   docker compose up -d --wait
   ```

   Caddy manages HTTPS automatically.

4. Open the private setup link printed by the installer. To retrieve it again:

   ```sh
   docker compose exec app gradepush-setup
   ```

5. Enter your institution name, create the GitHub App, and sign in with GitHub. Connect an organization in **Settings → Organizations** and create your first classroom.

For manual installation, use the [standalone Compose file](compose.self-host.yaml) with `PHX_HOST`, `DB_PASSWORD`, and `SETUP_TOKEN` in `.env`.

## Try the demo locally

1. Clone the repository:

   ```sh
   git clone https://github.com/gradepush/gradepush.git
   cd gradepush
   ```

2. Start with sample data:

   macOS / Linux:

   ```sh
   scripts/local-compose --env-file .env.example -p gradepush-demo -f compose.demo.yaml up -d --build --wait
   ```

   Windows:

   ```sh
   docker compose --env-file .env.example -p gradepush-demo -f compose.yaml -f compose.demo.yaml up -d --build --wait
   ```

3. Open [https://localhost:4000/demo](https://localhost:4000/demo) and choose a role.

On macOS/Linux, the launcher configures certificate trust and may request your OS password. On Windows, Docker generates the certificate; your browser may show a warning.

## Develop with Docker

1. From a clone of this repository, start the development environment:

   macOS / Linux:

   ```sh
   scripts/dev
   ```

   Windows:

   ```sh
   docker compose -p gradepush-development -f compose.development.yaml up --build --watch
   ```

2. Open [https://localhost:4000](https://localhost:4000). Edit the code locally; the app reloads automatically. GitHub setup requires a public HTTPS address, such as a tunnel.
3. Run checks:

   ```sh
   docker compose -p gradepush-development -f compose.development.yaml exec --user 1000 app mix precommit
   docker compose -p gradepush-development -f compose.development.yaml exec --user 1000 app sh scripts/test-release-env
   ```

4. Stop the development environment:

   ```sh
   docker compose -p gradepush-development -f compose.development.yaml down
   ```

[License](LICENSE) · [Contributing](CONTRIBUTING.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)
