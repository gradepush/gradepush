# GradePush

## Requirements

- Docker with Compose v2.32 or newer (Linux containers on Windows).
- For trusted local HTTPS on macOS/Linux: `curl` and OpenSSL.
- For self-hosting: `curl`, OpenSSL, and a public domain pointing to the server, with ports **80** and **443** open.

## Self-host with Docker

Uses the published image with PostgreSQL and Caddy. No repository clone or build is required.

1. Download the [standalone Compose file](compose.self-host.yaml) into an empty directory:

   ```sh
   mkdir gradepush && cd gradepush
   curl -fsSL https://raw.githubusercontent.com/gradepush/gradepush/main/compose.self-host.yaml -o compose.yaml
   ```

2. Point your domain to the server's public IP and open ports **80** and **443**. Generate `.env`, replacing `grades.example.org` with your domain, without `https://`:

   ```sh
   (umask 077; cat > .env <<EOF
   PHX_HOST=grades.example.org
   DB_PASSWORD=$(openssl rand -hex 32)
   SETUP_TOKEN=$(openssl rand -hex 32)
   EOF
   )
   ```

3. Start GradePush:

   ```sh
   docker compose pull
   docker compose up -d --wait
   ```

   Caddy manages HTTPS automatically.

4. Open `https://your-domain/setup` and enter `SETUP_TOKEN` from `.env`, or retrieve your private setup link:

   ```sh
   docker compose exec app gradepush-setup
   ```

5. Enter your institution name, create the GitHub App, and sign in with GitHub. Connect an organization in **Settings → Organizations** and create your first classroom.

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
   docker compose --env-file .env.example -p gradepush-demo -f compose.yaml -f compose.local.yaml -f compose.demo.yaml up -d --build --wait
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
