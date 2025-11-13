#!/bin/bash
# Script to setup MySQL replication between master and slave

echo "Setting up MySQL replication..."

# Wait for both MySQL instances to be ready
sleep 30

# Get master status
MASTER_STATUS=$(mysql -h mysql-master -u root -proot_password -e "SHOW MASTER STATUS\G")
MASTER_LOG_FILE=$(echo "$MASTER_STATUS" | grep File | awk '{print $2}')
MASTER_LOG_POS=$(echo "$MASTER_STATUS" | grep Position | awk '{print $2}')

echo "Master log file: $MASTER_LOG_FILE"
echo "Master log position: $MASTER_LOG_POS"

# Configure slave
mysql -h mysql-slave -u root -proot_password <<EOF
STOP SLAVE;

CHANGE MASTER TO
  MASTER_HOST='mysql-master',
  MASTER_USER='replicator',
  MASTER_PASSWORD='repl_password',
  MASTER_AUTO_POSITION=1;

START SLAVE;
SHOW SLAVE STATUS\G;
EOF

echo "Replication setup completed"