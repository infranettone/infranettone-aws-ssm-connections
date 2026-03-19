#!/usr/bin/env bash

require_command() {
  local cmd=""

  [[ "$#" -gt 0 ]] || die "require_command expects at least one command name."

  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
  done
}

split_whitespace_to_array() {
  local raw="$1"
  local -n output_ref="$2"
  local normalized=""

  output_ref=()
  [[ -n "$raw" ]] || return 0

  normalized="${raw//$'\t'/$'\n'}"
  mapfile -t output_ref <<<"$normalized"
}

list_aws_profiles() {
  require_command aws

  local output=""
  local -a profiles=()
  local -a sorted_profiles=()

  output="$(aws configure list-profiles 2>/dev/null || true)"
  [[ -n "$output" ]] || die "No AWS profiles found. Configure one with: aws configure --profile <name>"

  mapfile -t profiles <<<"$output"
  mapfile -t sorted_profiles < <(printf "%s\n" "${profiles[@]}" | sort)
  printf "%s\n" "${sorted_profiles[@]}"
}

list_aws_regions() {
  local profile="$1"
  local -a regions=()
  local -a sorted_regions=()
  local region_output=""

  require_command aws

  region_output="$(aws ec2 describe-regions \
    --all-regions \
    --query "Regions[].RegionName" \
    --output text \
    --profile "$profile" \
    2>/dev/null || true)"

  split_whitespace_to_array "$region_output" regions

  if [[ "${#regions[@]}" -eq 0 ]]; then
    regions=(eu-west-1 eu-west-3 eu-central-1 us-east-1 us-east-2 us-west-1 us-west-2)
  fi

  mapfile -t sorted_regions < <(printf "%s\n" "${regions[@]}" | sort)
  printf "%s\n" "${sorted_regions[@]}"
}

list_secret_names() {
  local profile="$1"
  local region="$2"
  local secret_output=""
  local -a secret_names=()
  local -a sorted_secret_names=()

  require_command aws

  secret_output="$(aws secretsmanager list-secrets \
    --profile "$profile" \
    --region "$region" \
    --query "SecretList[].Name" \
    --output text \
    2>/dev/null || true)"

  split_whitespace_to_array "$secret_output" secret_names
  [[ "${#secret_names[@]}" -gt 0 ]] || die "No Secrets Manager secrets found in region '$region' for profile '$profile'."

  mapfile -t sorted_secret_names < <(printf "%s\n" "${secret_names[@]}" | sort)
  printf "%s\n" "${sorted_secret_names[@]}"
}

list_ec2_instances() {
  local profile="$1"
  local region="$2"
  local instance_output=""
  local line=""
  local instance_id=""
  local instance_name=""
  local private_ip=""
  local state_name=""
  local -a instance_options=()
  local -a sorted_instance_options=()

  require_command aws

  instance_output="$(aws ec2 describe-instances \
    --profile "$profile" \
    --region "$region" \
    --query "Reservations[].Instances[].[InstanceId, Tags[?Key=='Name']|[0].Value, PrivateIpAddress, State.Name]" \
    --output text \
    2>/dev/null || true)"

  [[ -n "$instance_output" ]] || die "No EC2 instances found in region '$region' for profile '$profile'."

  while IFS=$'\t' read -r instance_id instance_name private_ip state_name; do
    [[ -n "${instance_id:-}" ]] || continue
    [[ "${instance_id:-}" == "None" ]] && continue

    if [[ -z "${instance_name:-}" || "${instance_name:-}" == "None" ]]; then
      instance_name="unnamed"
    fi

    if [[ -z "${private_ip:-}" || "${private_ip:-}" == "None" ]]; then
      private_ip="no-private-ip"
    fi

    if [[ -z "${state_name:-}" || "${state_name:-}" == "None" ]]; then
      state_name="unknown"
    fi

    instance_options+=("$instance_id | $instance_name | $private_ip | $state_name")
  done <<<"$instance_output"

  [[ "${#instance_options[@]}" -gt 0 ]] || die "No EC2 instances found in region '$region' for profile '$profile'."

  mapfile -t sorted_instance_options < <(printf "%s\n" "${instance_options[@]}" | sort)
  printf "%s\n" "${sorted_instance_options[@]}"
}

fetch_secret_string() {
  local profile="$1"
  local region="$2"
  local secret_name="$3"

  require_command aws

  aws secretsmanager get-secret-value \
    --secret-id "$secret_name" \
    --profile "$profile" \
    --region "$region" \
    --query "SecretString" \
    --output text
}

secret_string_is_json() {
  local secret_string="${1:-}"

  if [[ -z "$secret_string" ]]; then
    secret_string="$(fetch_current_secret_string)"
  fi

  require_command jq
  jq -e . >/dev/null 2>&1 <<<"$secret_string"
}

get_secret_json_field() {
  local field_name="$1"
  local secret_string="${2:-}"

  if [[ -z "$secret_string" ]]; then
    secret_string="$(fetch_current_secret_string)"
  fi

  secret_string_is_json "$secret_string" || die "Current secret is not valid JSON."
  jq -r --arg key "$field_name" '.[$key] // empty' <<<"$secret_string"
}

fetch_current_secret_string() {
  for key in AWS_PROFILE AWS_REGION AWS_SECRET_NAME; do
    [[ -n "${!key:-}" ]] || die "Missing required AWS context value: $key"
  done

  fetch_secret_string "$AWS_PROFILE" "$AWS_REGION" "$AWS_SECRET_NAME"
}

save_config() {
  local config_file="$1"

  cat >"$config_file" <<EOF
AWS_PROFILE=$(printf "%q" "$AWS_PROFILE")
AWS_REGION=$(printf "%q" "$AWS_REGION")
AWS_SECRET_NAME=$(printf "%q" "$AWS_SECRET_NAME")
CONNECTION_TARGET=$(printf "%q" "$CONNECTION_TARGET")
RDS_BASTION_INSTANCE_ID=$(printf "%q" "${RDS_BASTION_INSTANCE_ID:-}")
EOF

  chmod 600 "$config_file"
}

load_config() {
  local config_file="$1"
  local key=""
  local had_legacy_secret_string="false"

  [[ -f "$config_file" ]] || die "Config file not found: $config_file"

  # shellcheck disable=SC1090
  source "$config_file"

  if [[ -n "${SECRET_STRING:-}" ]]; then
    had_legacy_secret_string="true"
  fi

  declare -g AWS_PROFILE AWS_REGION AWS_SECRET_NAME CONNECTION_TARGET RDS_BASTION_INSTANCE_ID

  unset -v SECRET_STRING 2>/dev/null || true

  for key in AWS_PROFILE AWS_REGION AWS_SECRET_NAME; do
    [[ -n "${!key:-}" ]] || die "Config file is missing required value: $key"
  done

  if [[ "$had_legacy_secret_string" == "true" ]]; then
    save_config "$config_file"
    info "Legacy secret value removed from $config_file"
  fi
}

select_connection_target() {
  local -a connection_targets=(
    "RDS"
    "RDS Proxy"
    "EC2"
    "ECS"
  )

  declare -g CONNECTION_TARGET
  CONNECTION_TARGET="$(select_from_options $'What do you want to connect to? ' connection_targets)"
}

select_rds_bastion_instance() {
  local -a instance_options=()
  local selected_instance=""

  mapfile -t instance_options < <(list_ec2_instances "$AWS_PROFILE" "$AWS_REGION")
  selected_instance="$(select_from_options $'Which EC2 bastion instance do you want to connect to via SSM? ' instance_options)"

  declare -g RDS_BASTION_INSTANCE_ID
  RDS_BASTION_INSTANCE_ID="${selected_instance%% | *}"
}

configure_connection_target_details() {
  declare -g RDS_BASTION_INSTANCE_ID
  RDS_BASTION_INSTANCE_ID=""

  case "${CONNECTION_TARGET:-}" in
    "RDS")
      select_rds_bastion_instance
      ;;
  esac
}

bootstrap_aws_context() {
  local -a profiles=()
  local -a regions=()
  local -a secrets=()

  mapfile -t profiles < <(list_aws_profiles)
  declare -g AWS_PROFILE
  AWS_PROFILE="$(select_from_options $'Select the AWS profile: ' profiles)"

  mapfile -t regions < <(list_aws_regions "$AWS_PROFILE")
  declare -g AWS_REGION
  AWS_REGION="$(select_from_options $'Select the AWS region: ' regions)"

  mapfile -t secrets < <(list_secret_names "$AWS_PROFILE" "$AWS_REGION")
  declare -g AWS_SECRET_NAME
  AWS_SECRET_NAME="$(select_from_options $'Select the AWS secret: ' secrets)"

  select_connection_target
  configure_connection_target_details
}

configure_and_save_context() {
  local config_file="$1"
  bootstrap_aws_context
  save_config "$config_file"
}

ensure_optional_context() {
  local config_file="$1"
  local needs_save="false"

  if [[ -z "${CONNECTION_TARGET:-}" ]]; then
    info "Connection target not configured yet."
    select_connection_target
    needs_save="true"
  fi

  if [[ "${CONNECTION_TARGET:-}" == "RDS" && -z "${RDS_BASTION_INSTANCE_ID:-}" ]]; then
    info "RDS bastion instance not configured yet."
    select_rds_bastion_instance
    needs_save="true"
  fi

  if [[ "${CONNECTION_TARGET:-}" != "RDS" && -n "${RDS_BASTION_INSTANCE_ID:-}" ]]; then
    RDS_BASTION_INSTANCE_ID=""
    needs_save="true"
  fi

  if [[ "$needs_save" == "true" ]]; then
    save_config "$config_file"
    info "Configuration updated in $config_file"
  fi
}

initialize_context() {
  local config_file="$1"

  if [[ -f "$config_file" ]]; then
    load_config "$config_file"
    ensure_optional_context "$config_file"
    info "Configuration loaded from $config_file"
    return 0
  fi

  info "No configuration file found. Starting setup wizard."
  configure_and_save_context "$config_file"
  info "Configuration saved to $config_file"
}

reconfigure_context() {
  local config_file="$1"
  configure_and_save_context "$config_file"
  info "Configuration updated in $config_file"
}
