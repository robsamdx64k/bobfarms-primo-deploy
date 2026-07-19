# BobFarms Primo One-Line Deployment

This repo deploys:

- prebuilt `primo-arm-miner`
- Verus mining through the BobFarms proxy
- `screen` session named `primo`
- BobFarms telemetry agent
- `screen` session named `primo-agent`

## GitHub setup

1. Create a public repo named `bobfarms-primo-deploy`.
2. Upload:
   - `install.sh`
   - `agent.sh`
   - `update.sh`
3. Edit `install.sh` and replace `YOUR_GITHUB_USERNAME`.
4. Create GitHub release tag `v1.0.9`.
5. Upload your already-built ARM64 miner binary to that release with the exact asset name:

`primo-arm-miner-arm64`

The binary is uploaded once. Phones do not compile anything.

## One-line phone install

```bash
NAME=Dream112 bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/bobfarms-primo-deploy/main/install.sh)
```

Optional rack and thread count:

```bash
NAME=Dream112 GROUP=Rack02 THREADS=8 bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/bobfarms-primo-deploy/main/install.sh)
```

## What the installer does

1. Installs dependencies.
2. Downloads the prebuilt miner from GitHub Releases.
3. Downloads the agent.
4. Starts the miner in `screen -S primo`.
5. Starts the agent in `screen -S primo-agent`.

## Commands

```bash
screen -ls
screen -r primo
screen -r primo-agent
~/bobfarms-primo/update.sh
```
