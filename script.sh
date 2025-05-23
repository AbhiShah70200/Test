#!/bin/bash

# connection.sh
# Just checks if connection is successful

# Hardcoded parameters
HOST="myhost.mycompany.com"
PORT="2638"
USER="myuser"
PASS="mypassword"
ENGINE="my_engine"
DBNAME="my_database"

# Connection string
CONN_STR="HOST=$HOST;PORT=$PORT;UID=$USER;PWD=$PASS;ENG=$ENGINE;DBN=$DBNAME"

# Try connecting with a simple harmless SQL: SELECT 1
echo "SELECT 1;" | isql -b -d'\n' -S "$CONN_STR" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "Connection successful."
else
    echo "Connection failed." >&2
    exit 1
fi
