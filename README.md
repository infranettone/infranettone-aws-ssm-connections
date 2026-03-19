# Base Template

Minimal template for projects that need:

- Execution inside Docker.
- Bash scripts organized by `entrypoints` and `lib`.
- Interactive selection of `AWS profile`, `AWS region`, `AWS secret`, and connection target.
  For `RDS`, it also prompts for the EC2 bastion instance to use via SSM.
- Local persistence of the AWS context in `config.txt` without storing secret values.

## Structure

- `run.sh`: host entry point.
- `main/`: Dockerfile, compose, and container wrapper.
- `scripts/entrypoints/`: host/container flow.
- `scripts/lib/core/`: core utilities.
- `scripts/lib/features/`: reusable features.

## Usage

```bash
./run.sh
```

On the first run:

1. Starts the container.
2. Prompts for the AWS profile, region, secret, and connection target.
3. Saves only the AWS profile, region, secret name, connection target, and any target-specific settings to `config.txt`.

## Requirements

- Docker with `docker compose`.
- AWS credentials configured in `~/.aws`.

## Customization

- Replace the placeholders in `scripts/entrypoints/container.sh`.
- If your secret contains JSON, you can read keys with `get_secret_json_field`; the value is fetched from Secrets Manager when needed.
- If you need more tooling, extend it in `main/Dockerfile`.
