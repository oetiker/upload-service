#!/bin/sh
export US_ROOT=/slow/sandbox
export MOJO_LOG_LEVEL=info 
export US_SECRET_FILE=/root/upload-service-secret
## add something like this to sudo to allow the
## fcgi user to execture the script as root
# Defaults:inboxsrv env_keep="*"
# inboxsrv ALL = NOPASSWD: /home/inboxsrv/upload-service/backend/bin/us.pl fastcgi
#
## add this .htaccess file
# RewriteEngine On
# RewriteCond %{REQUEST_FILENAME} !-f
# RewriteRule (.*) upload-service.fcgi/$1 [L]
sudo /home/inboxsrv/upload-service/backend/bin/us.pl fastcgi
