# GradePush

## Requirements

- Docker with Compose v2.24.4 or newer, `curl`, and OpenSSL.
- For local development and the demo: macOS or Linux.
- For self-hosting: a public domain pointing to the server, with ports **80** and **443** open.

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

   Caddy obtains and renews the HTTPS certificate automatically. No Certbot or manual certificate setup is needed. Keep the Docker volumes to preserve your database, application keys, and certificates.

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

   ```sh
   DEMO_MODE=true HOST_PORT=4001 PHX_URL_PORT=4001 scripts/local-compose --env-file .env.example -p gradepush-demo up -d --build --wait
   ```

3. Open [https://localhost:4001/demo](https://localhost:4001/demo) and choose a role.

Local HTTPS is automatic. Your OS may ask for your password to trust the certificate.

## Develop with Docker

1. From a clone of this repository, start the development environment:

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
