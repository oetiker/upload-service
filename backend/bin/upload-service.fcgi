#!/bin/sh
export US_ROOT=/slow/sandbox
export MOJO_LOG_LEVEL=info 
export US_SECRET_FILE=/root/upload-service-secret
## add something like this to sudo to allow the
## fcgi user to execture the script as root
# Defaults:inboxsrv env_keep="*"
# inboxsrv ALL = NOPASSWD: /home/inboxsrv/upload-service/backend/bin/us.pl fastcgi
#
sudo /home/inboxsrv/upload-service/backend/bin/us.pl fastcgi
