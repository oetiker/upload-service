upload-service
==============

A mojolicious based webservice based on
http://blueimp.github.io/jQuery-File-Upload/
by Sebastian Tschan.

installation
------------
Use the classic ./configure; make install approach.

Once installed you will find a htdoc directory in your installation
target.

Copy this directory into your webserver and configure the webserver to
execute fcgi (fastcgi) scripts. Note that in the htdocs directory
there is also a .htaccess file.

configuration
-------------

The upload service gets configured via several environement variables

US_ROOT=/path

where should the uploads go

US_SINGLEUSER=0|1

in single user mode the uploads go straight to $US_ROOT in multi user mode the
uploads go to $US_ROOT/$USERNAME/INBOX

in multi user mode the url for upload is expected to contain the USER name and the script
must run a root (use sudo) so that it can suid to the recipient of the files.

US_ENABLE_DELETE=0|1

allow the uploader to delete the files he just uploaded

US_ENABLE_DOWNLOAD=0|1

allow the uploader to download the files he just uploaded

Enjoy!
tobi

