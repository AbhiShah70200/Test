#!/bin/bash

# connection.sh
# Usage: ./connection.sh <SQL_FILE>

SQL_FILE="$1"

# Hardcoded connection details
HOST="myhost.mycompany.com"
PORT="2638"
USER="myuser"
PASS="mypassword"
ENGINE="my_engine"
DBNAME="my_database"

if [ -z "$SQL_FILE" ]; then
    echo "Usage: $0 <sql_script.sql>"
    exit 1
fi

# Build the connection string
CONN_STR="HOST=$HOST;PORT=$PORT;UID=$USER;PWD=$PASS;ENG=$ENGINE;DBN=$DBNAME"

# Execute the SQL script
if isql -b -d'\n' -S "$CONN_STR" < "$SQL_FILE"; then
    echo "Connection successful and SQL executed successfully."
else
    echo "Connection failed or SQL error." >&2
    exit 1
fi
