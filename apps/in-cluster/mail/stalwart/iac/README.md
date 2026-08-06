# Stalwart declarative configuration

Stalwart 0.16 removed the REST API. Domains, directories and every other setting
now live as JMAP objects inside the data store, and the supported way to manage
them as code is a plan applied with `stalwart-cli apply`, which idempotently
reconciles live state to the plan.

## Why there are two formats

`plan.yaml` is the source of truth and the only file to edit.

The CLI parses its input strictly line by line — `parse_ndjson_plan` in
`src/commands/apply.rs` splits on newlines and hands each trimmed line to
`serde_json::from_str`. One JSON object per line, so the wire format can hold
neither comments nor indentation. Authoring that by hand gives you 400-character
lines nobody can review.

So the plan is written as multi-document YAML and converted at launch by an
initContainer:

```
yq -o=json -I=0 '(.. | select(tag == "!!str")) |= envsubst' /src/plan.yaml \
  > /plan/plan.ndjson
```

`-I=0` emits compact JSON, and each YAML document becomes one line — which is
exactly NDJSON. Comments are stripped by the conversion. Blank lines would be
fine either way; the parser skips them.

The `envsubst` pass expands `${VAR}` inside string values. That exists for one
reason: `BlobStore.accessKey` is typed as a plain string in the schema, so
unlike `secretKey` it cannot hold a secret reference, and hardcoding it would
put an S3 credential in git. The Job takes it from the `stalwart-s3` Secret
instead. The initContainer runs `set -u` with an explicit guard, because an
unset variable would otherwise expand to empty and quietly write a broken blob
store config.

To see what the server will actually receive:

```bash
STALWART_S3_ACCESS_KEY=dummy \
  yq -o=json -I=0 '(.. | select(tag == "!!str")) |= envsubst' plan.yaml
```

## Sets are maps, not arrays

The trap in this schema: fields typed `set` serialise as `{"value": true}`, not
as a JSON array. Passing `[]` gets rejected with
`invalidPatch | Invalid value for object property`. Both `Domain.aliases` and
`OidcDirectory.requireScopes` are sets — the server's own default for the latter
is `{"openid": true, "email": true}`.

## Validating against the live schema

The server publishes its full schema, which is the authority on property names,
types and mutability. Every field in this plan was checked against it:

```bash
kubectl port-forward -n stalwart svc/stalwart-stalwart-mail-ha-http 18080:8080 &
curl -sL -u admin:<from vault> http://127.0.0.1:18080/api/schema | gunzip > schema.json
```

`fields["x:Domain"].properties`, `fields["x:OidcDirectory"].properties` etc. give
each property's type and `update` mode (`mutable` / `serverSet` / `immutable`),
and `fields[...].defaults` shows the wire format for defaulted fields.
`lists["x:Directory"].labelProperty` is the key `matchOn` falls back to.

## Values to confirm

- **`usernameDomain: lab.com`.** Appended when `preferred_username` has no `@`.
  Correct only if Keycloak usernames are bare (`abdo`, not `abdo@lab.com`).
- **`requireAudience: stalwart`.** Must match the audience injected by the
  `stalwart-audience` protocol mapper on the Keycloak `bulwark` client. It is
  also the server default.

Dry-run validates without writing:

```bash
yq -o=json -I=0 '.' plan.yaml | kubectl run stalwart-plan-check \
  --rm -i --restart=Never --image=ghcr.io/stalwartlabs/cli:v1.0.12 \
  --env STALWART_URL=http://stalwart-stalwart-mail-ha-http.stalwart.svc:8080 \
  --env STALWART_USER=admin --env STALWART_PASSWORD=<from vault> \
  -- apply --stdin --dry-run
```

## Not covered here

- **DNS records.** `dnsManagement` is `Manual`, so MX, SPF, DMARC and the DKIM
  record Stalwart generates have to be published by hand. The generated zone
  file is readable from the admin UI once the domain exists.
- **Accounts.** With an external directory, users come from Keycloak on first
  login rather than being declared here.
- **Desktop/mobile IMAP clients.** They do not do browser redirect flows. Once
  SSO owns authentication those clients need app passwords, issued per user at
  runtime — not something this plan can pre-create.
