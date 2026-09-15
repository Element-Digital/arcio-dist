<p align="center">
  <a href="https://arcio.au">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="brand/arcio-lockup-dark-bg.png">
      <img src="brand/arcio-lockup-light-bg.png" alt="Arcio" width="264">
    </picture>
  </a>
</p>

# arcio-dist

Everything you need to run [Arcio](https://arcio.au) is here.

```bash
curl -O https://raw.githubusercontent.com/Element-Digital/arcio-dist/main/compose.yaml
docker compose up -d
```

Full instructions: **<https://arcio.au/docs/install/docker/>**

## What is in here

| | |
|---|---|
| `compose.yaml` | The stack: Arcio, PostgreSQL, and an optional Caddy for TLS |
| `bin/arcioctl` | The supervisor. Backup, restore, update with rollback, diagnostics |
| `appliance/` | Arcio OS build inputs. Not released yet, see the [roadmap](https://arcio.au/docs/roadmap/) |

## What is not

**The source.** Arcio is not open source. Licensed customers can read it, so it
can be reviewed and scanned before it goes near production, but it is not
published here.

Every published image is signed with Cosign and carries an SBOM and build
provenance, so you can verify what you are running without reading it. See
[Verify what you pulled](https://arcio.au/docs/verify/).

**The images.** They are on `ghcr.io/element-digital/arcio`, public and needs
no credentials.

## Why a repository

Install files belong somewhere you can pin, diff and verify, rather than on a
page that can change. Everything here is versioned: install from a
specific version and you know exactly what you ran.

It is also where appliance images are published, which a couple of files on a
website could not do.

## Brand

The assets in `brand/` are generated from the Arcio website. They are raster
rather than vector on purpose.

## Stability

`compose.yaml` and `arcioctl` on `main` track the current release and are what
the documentation refers to. Anything under `appliance/` is a work in progress
until the roadmap says otherwise.

If you need a fixed artefact rather than a moving one, use a tagged release
rather than `main`.
