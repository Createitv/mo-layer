#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="${SCHEMA_FILE:-"$SCRIPT_DIR/privacy-cloudkit.schema"}"
TEAM_ID="${CKTOOL_TEAM_ID:-677U99F8TX}"
CONTAINER_ID="${CKTOOL_CONTAINER_ID:-iCloud.app.landlady.www.privacy}"
ENVIRONMENT="${1:-development}"
ACTION="${2:-validate}"

usage() {
  cat <<USAGE
Usage:
  bash tools/cloudkit/deploy-schema.sh <development|production> <validate|import|export-current>

Environment variables:
  CKTOOL_TEAM_ID       Apple Developer team id. Default: $TEAM_ID
  CKTOOL_CONTAINER_ID  CloudKit container id. Default: $CONTAINER_ID
  SCHEMA_FILE          Schema file path. Default: $SCHEMA_FILE

Examples:
  bash tools/cloudkit/deploy-schema.sh development validate
  bash tools/cloudkit/deploy-schema.sh development import
  bash tools/cloudkit/deploy-schema.sh production import
USAGE
}

case "$ENVIRONMENT" in
  development|production) ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    echo "Unsupported environment: $ENVIRONMENT" >&2
    usage >&2
    exit 64
    ;;
esac

case "$ACTION" in
  validate|import|export-current) ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    echo "Unsupported action: $ACTION" >&2
    usage >&2
    exit 64
    ;;
esac

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required. Install Xcode command line tools first." >&2
  exit 69
fi

if [[ "$ACTION" != "export-current" && ! -f "$SCHEMA_FILE" ]]; then
  echo "Schema file not found: $SCHEMA_FILE" >&2
  exit 66
fi

echo "CloudKit container: $CONTAINER_ID"
echo "Team: $TEAM_ID"
echo "Environment: $ENVIRONMENT"

if [[ "$ACTION" == "export-current" ]]; then
  OUTPUT_FILE="${OUTPUT_FILE:-"$SCRIPT_DIR/current-$ENVIRONMENT.schema"}"
  xcrun cktool export-schema \
    --team-id "$TEAM_ID" \
    --container-id "$CONTAINER_ID" \
    --environment "$ENVIRONMENT" \
    --output-file "$OUTPUT_FILE"
  echo "Exported current schema to $OUTPUT_FILE"
  exit 0
fi

VALIDATION_ENVIRONMENT="$ENVIRONMENT"
if [[ "$ENVIRONMENT" == "production" ]]; then
  VALIDATION_ENVIRONMENT="development"
  echo "cktool validate-schema is not available for production; validating the schema against development first."
fi

echo "Validating schema: $SCHEMA_FILE"
xcrun cktool validate-schema \
  --team-id "$TEAM_ID" \
  --container-id "$CONTAINER_ID" \
  --environment "$VALIDATION_ENVIRONMENT" \
  --file "$SCHEMA_FILE"

if [[ "$ACTION" == "validate" ]]; then
  exit 0
fi

if [[ "$ENVIRONMENT" == "production" ]]; then
  echo "Importing schema into PRODUCTION. This changes live CloudKit schema."
else
  echo "Importing schema into development."
fi

xcrun cktool import-schema \
  --team-id "$TEAM_ID" \
  --container-id "$CONTAINER_ID" \
  --environment "$ENVIRONMENT" \
  --file "$SCHEMA_FILE"

echo "CloudKit schema import completed."
