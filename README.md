upload-service
==============

A mojolicious based webservice provinding an
inbox.company.com website where users can receive uploads.

this package contains an almost complete 
copy of http://blueimp.github.io/jQuery-File-Upload/
thanks to Sebastian Tschan for makeing that package
available under the MIT License

installation
------------
The upload service uses the mojolicious perl module. In all likelyhood you
will not find this on your system.  I have therefore supplied a little
script which lets you install this package.  If you install it in a
directory called 'thirdparty' next to the bin directory, all the files will
be found automatically.

 ./setup/build-thirdparty.sh /home/inbox/software/backend/thirdparty

The upload service is suposed to run on a machine where all the users of the
service have an account.  The upload service assumes the uid of the user on
whoes behalve it is receiving data. In order todo so, it must run a root.

We like to run it as a fastcgi service from our webserver and use sudo to
run it as root. See the example fcgi script in the bin directory.

Since the upload-service is written using Mojo, you only have to place the
fcgi script into your web-doc-cgi directory together with the .htaccess file
as shown in the fcgi example script.

Enjoy!
tobi

