upload-service
==============

A File-Upload Web Application. The backend is written in Perl using
http://mojolicious.org, the frontend leverages
http://blueimp.github.io/jQuery-File-Upload/.

installation
------------
Use the classic ./configure; make install approach.

Once installed you will find a htdoc directory in your installation
target.

Copy this directory into your webserver and configure the webserver to
execute fcgi (fastcgi) scripts. Note that in the htdocs directory
there is also a .htaccess file.

Since the file-upload service is based on Mojolicious, you can use any of
the modes of operation supported by Mojolicious.

configuration
-------------

The upload service gets is configured via several environement variables.

Set US_ROOT to define where the uploaded files should end up

 US_ROOT=/path

The system has two modes of operatation. Single user mode and multi user mode

 US_SINGLEUSER=0|1

in single user mode the uploads go straight to $US_ROOT in multi user mode the
uploads go to $US_ROOT/$USERNAME/INBOX

in multi user mode the url for upload is expected to contain the $USERNAME
and the script must run as root (use sudo) so that it can suid to the
recipient of the files.

In single user mode you get

 http://your-site/script-url/

In multi-user mode you get

 http://your-site/script-url/USERNAME/

The system keeps track who has uploaded which files. So that the uploader sees
a list of files he has uploaded. You can even give the uploader the ability
to delete his uploades:

 US_ENABLE_DELETE=0|1

And to download them again:

 US_ENABLE_DOWNLOAD=0|1

In multi user mode, the MOJO_TMPDIR must point to an empty directory
with mode 0777.

Enjoy!
tobi

