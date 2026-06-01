# CloudKit Schema Deployment

The iOS app cannot deploy CloudKit schema changes at runtime. Production schema is a server-side CloudKit configuration and must be deployed with CloudKit Dashboard or `cktool`.

This folder keeps the required schema versioned with the project, so release builds can use the same source of truth.

## Validate

```bash
bash tools/cloudkit/deploy-schema.sh development validate
bash tools/cloudkit/deploy-schema.sh production validate
```

## Import

```bash
bash tools/cloudkit/deploy-schema.sh development import
bash tools/cloudkit/deploy-schema.sh production import
```

The script defaults to:

- Team: `677U99F8TX`
- Container: `iCloud.app.landlady.www.privacy`

Override with:

```bash
CKTOOL_TEAM_ID=YOUR_TEAM_ID CKTOOL_CONTAINER_ID=iCloud.your.container bash tools/cloudkit/deploy-schema.sh production import
```

## Export Current CloudKit Schema

```bash
bash tools/cloudkit/deploy-schema.sh development export-current
bash tools/cloudkit/deploy-schema.sh production export-current
```
