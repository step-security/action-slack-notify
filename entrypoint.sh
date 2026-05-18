#!/usr/bin/env bash

REPO_PRIVATE=$(jq -r '.repository.private | tostring' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "")
UPSTREAM="rtCamp/action-slack-notify"
ACTION_REPO="${GITHUB_ACTION_REPOSITORY:-}"
DOCS_URL="https://docs.stepsecurity.io/actions/stepsecurity-maintained-actions"

echo ""
echo -e "\033[1;36mStepSecurity Maintained Action\033[0m"
echo "Secure drop-in replacement for $UPSTREAM"
if [ "$REPO_PRIVATE" = "false" ]; then
  echo -e "\033[32m✓ Free for public repositories\033[0m"
fi
echo -e "\033[36mLearn more:\033[0m $DOCS_URL"
echo ""

if [ "$REPO_PRIVATE" != "false" ]; then
  SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"

  if [ "$SERVER_URL" != "https://github.com" ]; then
    BODY=$(printf '{"action":"%s","ghes_server":"%s"}' "$ACTION_REPO" "$SERVER_URL")
  else
    BODY=$(printf '{"action":"%s"}' "$ACTION_REPO")
  fi

  API_URL="https://agent.api.stepsecurity.io/v1/github/$GITHUB_REPOSITORY/actions/maintained-actions-subscription"

  RESPONSE=$(curl --max-time 3 -s -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$BODY" \
    "$API_URL" -o /dev/null) && CURL_EXIT_CODE=0 || CURL_EXIT_CODE=$?

  if [ $CURL_EXIT_CODE -ne 0 ]; then
    echo "Timeout or API not reachable. Continuing to next step."
  elif [ "$RESPONSE" = "403" ]; then
    echo -e "::error::\033[1;31mThis action requires a StepSecurity subscription for private repositories.\033[0m"
    echo -e "::error::\033[31mLearn how to enable a subscription: $DOCS_URL\033[0m"
    exit 1
  fi
fi

# Check required env variables
flag=0
mode="WEBHOOK"
if [[ -z "$SLACK_WEBHOOK" ]]; then
    flag=1
    missing_secret="SLACK_WEBHOOK"
    if [[ -n "$VAULT_ADDR" ]] && [[ -n "$VAULT_TOKEN" ]]; then
        flag=0
        echo -e "[\e[0;33mWARNING\e[0m] Both \`VAULT_ADDR\` and \`VAULT_TOKEN\` are provided. Using Vault for secrets. This feature is deprecated and will be removed in future versions. Please provide the credentials directly.\n"
    fi
    if [[ -n "$VAULT_ADDR" ]] || [[ -n "$VAULT_TOKEN" ]]; then
        missing_secret="VAULT_ADDR and/or VAULT_TOKEN"
    fi
fi

if [[ "$flag" -eq 1 ]] && [[ -n "$SLACK_TOKEN" || -n "$SLACK_CHANNEL" ]] ; then
    # Basically, if both SLACK_TOKEN and SLACK_CHANNEL are provided, then it's a token mode
    flag=0
    mode="TOKEN"
fi

if [[ "$flag" -eq 1 ]]; then
    echo -e "[\e[0;31mERROR\e[0m] Secret \`$missing_secret\` is missing. Alternatively, a pair of \`SLACK_TOKEN\` and \`SLACK_CHANNEL\` can be provided. Please add it to this action for proper execution.\nRefer https://github.com/step-security/action-slack-notify for more information.\n"
    exit 1
fi

export MSG_MODE="$mode"

if [[ -n "$SLACK_FILE_UPLOAD" ]]; then
  if [[ -z "$SLACK_TOKEN" ]]; then
    echo -e "[\e[0;31mERROR\e[0m] Secret \`SLACK_TOKEN\` is missing and a file upload is specified. File Uploads require an application token to be present.\n"
    exit 1
  fi
  if [[ -z "$SLACK_CHANNEL" ]]; then
    echo -e "[\e[0;31mERROR\e[0m] Secret \`SLACK_CHANNEL\` is missing and a file upload is specified. File Uploads require a channel to be specified.\n"
    exit 1
  fi
fi

# custom path for files to override default files
custom_path="$GITHUB_WORKSPACE/.github/slack"
main_script="/main.sh"

if [[ -d "$custom_path" ]]; then
    rsync -av "$custom_path/" /
    chmod +x /*.sh
fi

bash "$main_script"
