#!/bin/sh

###############################################################################
# Source required environment files
###############################################################################
# Load credential vault binding
. /gns/software/infra/ci/credvault/CVBashBinding-prod/CVBashBinding/bashBinding2.sh

# Load application-specific properties
. "$SAPP_HOME/env.properties"

###############################################################################
# Set Sybase environment variables
###############################################################################
export SYBASE_ROOT="/gns/me/dbclient/sybase/oc/openclient-15.7.0.1BF19872.E502.v01"
export PATH="$PATH:$SYBASE_ROOT/OCS-15_0/bin"

# Load Sybase environment setup
. "$SYBASE_ROOT/SYBASE.sh"

###############################################################################
# Parse command-line parameters
###############################################################################
while getopts "c:d:o:u:p:r:" opt; do
    case "$opt" in
        c) DB_CREF_LOCAL="$OPTARG" ;;        # Credential reference
        d) DB_NAME_LOCAL="$OPTARG" ;;        # Database name
        o) PROC_CONDITION="$OPTARG" ;;       # Procedure condition
        u) NEW_USER_ID="$OPTARG" ;;          # New user ID
        p) NEW_PSWD="$OPTARG" ;;              # New password
        r) APP_ROLE="$OPTARG" ;;              # Application roles (comma-separated)
        *) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done

###############################################################################
# Fallback to sourced values if not provided via command parameters
###############################################################################
DB_CREF_LOCAL="${DB_CREF_LOCAL:-$DB_CREF}"
DB_NAME_LOCAL="${DB_NAME_LOCAL:-$DB_NAME}"

###############################################################################
# Validate required environment variables
###############################################################################
if [ -z "$DB_CREF_LOCAL" ] || [ -z "$DB_NAME_LOCAL" ] || [ -z "$LOG_DIR" ]; then
    echo "Error: Required environment variables (DB_CREF_LOCAL, DB_NAME_LOCAL, LOG_DIR) are not set." >&2
    exit 1
fi

###############################################################################
# Functions
###############################################################################

# Retrieve username using credential reference
get_username_by_cref() {
    CREDREF="$1"
    if [ -z "$CREDREF" ]; then
        echo "Error: Credential reference is required." >&2
        exit 1
    fi

    CREDENTIAL="$(get_Cred_by_cref "$CREDREF")"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to retrieve credentials." >&2
        exit 2
    fi

    # Extract username (field 1)
    echo "$CREDENTIAL" | awk '{print $1}'
}

# Retrieve password using credential reference
get_pwd_by_cref() {
    CREDREF="$1"
    if [ -z "$CREDREF" ]; then
        echo "Error: Credential reference is required." >&2
        exit 1
    fi

    CREDENTIAL="$(get_Cred_by_cref "$CREDREF")"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to retrieve credentials." >&2
        exit 2
    fi

    # Extract password (field 2) - safely handle special chars
    echo "$CREDENTIAL" | awk '{print $2}'
}

# Execute SQL command safely
execute_sql() {
    SQL_COMMAND="$1"
    ERROR_MESSAGE="$2"

    echo "$SQL_COMMAND" | isql -U"$USERNAME" -P"$PASSWORD" -S"$SERVER" -D"$DB_NAME_LOCAL"
    if [ $? -ne 0 ]; then
        echo "Error: $ERROR_MESSAGE" >&2
        echo "Procedure $PROC_CONDITION failed due to SQL error or connection failure." >&2
        exit 1
    fi
}

###############################################################################
# Main Execution
###############################################################################

# If username/password not provided, fetch from credential vault
USERNAME="${NEW_USER_ID:-$(get_username_by_cref "$DB_CREF_LOCAL")}"
PASSWORD="${NEW_PSWD:-$(get_pwd_by_cref "$DB_CREF_LOCAL")}"

# Sample SQL execution (replace with your own SQL command)
# execute_sql "SELECT COUNT(*) FROM some_table" "Failed to execute SQL query"

echo "Script completed successfully."
