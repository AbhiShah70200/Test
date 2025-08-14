#!/bin/bash

#######################################
# Source required environment
#######################################
source /gns/software/infra/ci/credvault/CVBashBinding-prod/CVBashBinding/bashBinding2.sh
source "$APP_HOME/env.properties"

export SYBASE_ROOT="/gns/mw/dbclient/sybase/oc/openclient-15.7.0.EBF19872.ESD2.v01/"
export PATH="$PATH:$SYBASE_ROOT/OCS-15_0/bin"
source "$SYBASE_ROOT/SYBASE.sh"

#######################################
# Parse parameters
#######################################
while getopts "c:d:o:u:p:r:" opt; do
  case $opt in
    c) DB_CVREF_LOCAL="$OPTARG" ;;   # Credential reference
    d) DB_NAME_LOCAL="$OPTARG" ;;    # Database name
    o) PROC_CONDITION="$OPTARG" ;;   # Procedure condition
    u) NEW_USER_ID="$OPTARG" ;;      # New user ID
    p) NEW_PWSD="$OPTARG" ;;         # New password
    r) APP_ROLE="$OPTARG" ;;         # Application roles
    *) echo "Invalid option: $OPTARG" >&2; exit 1 ;;
  esac
done

#######################################
# Fallback defaults
#######################################
DB_CVREF_LOCAL=${DB_CVREF_LOCAL:-$DB_CVREF_PROC}
DB_NAME_LOCAL=${DB_NAME_LOCAL:-$DB_NAME_PROC}

#######################################
# Validate environment
#######################################
if [[ -z "$DB_CVREF_LOCAL" || -z "$DB_NAME_LOCAL" || -z "$LOG_DIR" ]]; then
  echo "Error: Required environment variables (DB_CVREF_LOCAL, DB_NAME_LOCAL, LOG_DIR) are not set." >&2
  exit 1
fi

#######################################
# Functions
#######################################
get_username_by_cref() {
  local CREDREF=$1
  if [[ -z "$CREDREF" ]]; then
    echo "Error: Credential reference is required." >&2
    exit 1
  fi

  local CREDENTIAL=$(_get_Cred_by_Cref "$CREDREF")
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to retrieve credentials." >&2
    exit 2
  fi

  echo "$CREDENTIAL" | awk '{print $1}'
}

get_pwsd_by_cref() {
  local CREDREF=$1
  if [[ -z "$CREDREF" ]]; then
    echo "Error: Credential reference is required." >&2
    exit 1
  fi

  local CREDENTIAL=$(_get_Cred_by_Cref "$CREDREF")
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to retrieve credentials." >&2
    exit 2
  fi

  echo "$CREDENTIAL" | awk '{print $2}'
}

execute_sql() {
  local SQL_COMMAND="$1"
  local ERROR_MESSAGE="$2"

  # 🔹 MASK password in SQL command before logging
  local LOGGED_SQL_COMMAND=$(echo "$SQL_COMMAND" | sed "s/${NEW_PWSD}/********/g")
  echo "Executing: $LOGGED_SQL_COMMAND"

  # 🔹 Run SQL and mask any password in output before printing
  isql -U"$DB_USER_NAME" -P"$DB_PWSD" -S"$DB_NAME_LOCAL" <<EOF | sed "s/${NEW_PWSD}/********/g"
$SQL_COMMAND
go
EOF

  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "Error: $ERROR_MESSAGE"
    echo "Procedure $PROC_CONDITION failed."
    exit 1
  fi
}

#######################################
# Main Logic
#######################################
if [[ -z "$PROC_CONDITION" || -z "$NEW_USER_ID" ]]; then
  echo "Usage: $0 -c <DB_CVREF_LOCAL> -d <DB_NAME_LOCAL> -o <PROC_CONDITION> -u <NEW_USER_ID> [-p <NEW_PWSD>] [-r <APP_ROLE>]"
  echo "PROC_CONDITION: create_user, change_pass, add_user"
  exit 1
fi

# Default password if not provided
NEW_PWSD=${NEW_PWSD:-default_pass}

# Retrieve DB credentials
DB_USER_NAME=$(get_username_by_cref "$DB_CVREF_LOCAL")
DB_PWSD=$(get_pwsd_by_cref "$DB_CVREF_LOCAL")

if [[ -z "$DB_USER_NAME" || -z "$DB_PWSD" ]]; then
  echo "Error: Failed to retrieve database credentials." >&2
  exit 1
fi

# 🔹 MASK password in connection log
echo "Connecting to database $DB_NAME_LOCAL with user $DB_USER_NAME"
echo "Using password: ********"

case $PROC_CONDITION in
  create_user)
    execute_sql "call sa.create_cobra_user('$NEW_USER_ID')" "Failed to create user"
    execute_sql "call sa.change_user_password('$NEW_USER_ID', '$NEW_PWSD')" "Failed to change password"
    if [[ -n "$APP_ROLE" ]]; then
      IFS=',' read -ra ROLES <<< "$APP_ROLE"
      for ROLE in "${ROLES[@]}"; do
        execute_sql "call sp_adduser('$NEW_USER_ID', '$ROLE')" "Failed to add role $ROLE"
      done
    else
      echo "APP_ROLE not provided. Skipping sp_adduser execution."
    fi
    ;;
  change_pass)
    if [[ -z "$NEW_PWSD" ]]; then
      echo "Error: NEW_PWSD is required for change_pass."
      exit 1
    fi
    execute_sql "call sa.change_user_password('$NEW_USER_ID', '$NEW_PWSD')" "Failed to change password"
    ;;
  add_user)
    if [[ -z "$APP_ROLE" ]]; then
      echo "Error: APP_ROLE is required for add_user."
      exit 1
    fi
    IFS=',' read -ra ROLES <<< "$APP_ROLE"
    for ROLE in "${ROLES[@]}"; do
      execute_sql "call sp_adduser('$NEW_USER_ID', '$ROLE')" "Failed to add role $ROLE"
    done
    ;;
  *)
    echo "Error: Invalid PROC_CONDITION."
    exit 1
    ;;
esac

echo "Procedure $PROC_CONDITION executed successfully."
