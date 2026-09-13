# arcio-dist

Everything you need to run [Arcio](https://arcio.au) that is not the container
image itself. Public, because you cannot ask somebody to evaluate a product
whose install instructions are behind a credential.

```bash
curl -O https://raw.githubusercontent.com/Element-Digital/arcio-dist/main/compose.yaml
echo "ARCIO_VERSION=edge" > .env
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

**The source.** Arcio's source stays private to licensed customers. The image
is the product; the source is the evidence. Every published image is signed
with Cosign and carries an SBOM and build provenance, so you can verify what
you are running without reading it. See
[Verify what you pulled](https://arcio.au/docs/verify/).

**The images.** They are on `ghcr.io/element-digital/arcio`, public and needing
no credential.

## Why this repo exists

The install guide used to point at raw URLs on the product repo. That repo is
private, so every one of them returned 404 to anybody who was not us, and the
documented install path had never worked for a customer. This repo is the fix.

It is also where appliance images will be published, which is the other reason
it is a repository rather than a couple of files dropped on the website.

## Stability

`compose.yaml` and `arcioctl` on `main` track the current release and are what
the documentation refers to. Anything under `appliance/` is a work in progress
until the roadmap says otherwise.

If you need a fixed artefact rather than a moving one, use a tagged release
rather than `main`.
