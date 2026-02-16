#!/bin/sh
# Wait for PostgreSQL to accept connections
for i in $(seq 1 30); do
    if pg_isready -h 127.0.0.1 -q 2>/dev/null; then
        break
    fi
    sleep 1
done

# Create user and database if they don't exist
su -s /bin/sh postgres -c "psql -h 127.0.0.1 -tc \"SELECT 1 FROM pg_roles WHERE rolname='ccc'\" | grep -q 1 || createuser -h 127.0.0.1 ccc"
su -s /bin/sh postgres -c "psql -h 127.0.0.1 -tc \"SELECT 1 FROM pg_database WHERE datname='ccc'\" | grep -q 1 || createdb -h 127.0.0.1 -O ccc ccc"
su -s /bin/sh postgres -c "psql -h 127.0.0.1 -c \"ALTER USER ccc WITH PASSWORD 'ccc';\""
